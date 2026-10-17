{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Supervisor tree (раздел 5.3).
--
-- An Erlang/OTP-shaped supervision model built from GHC's own concurrency
-- primitives — lightweight threads and 'STM' — rather than a port of an OTP
-- library. Each long-lived concurrent component (an adapter's health loop, an
-- IPC channel, the cache sweeper) is a child; a crash is contained to its own
-- subtree (ТРЕБ-020/022).
module Polyresolver.Core.Supervisor
  ( RestartStrategy(..)
  , RestartPolicy(..)
  , ChildSpec(..)
  , Supervisor(..)
  , RestartReport(..)
  , newSupervisor
  , startChild
  , stopChild
  , stopAll
  , supervisorChildren
  , childRestartCount
  , backoffDelay
  ) where

import Control.Concurrent (ThreadId, forkFinally, killThread, threadDelay)
import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVar, writeTVar)
import Control.Exception (SomeException, displayException)
import Control.Monad (when)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Foldable (toList)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)

-- | Which children are restarted when one crashes.
data RestartStrategy
  = OneForOne     -- ^ Only the crashed child.
  | RestForOne    -- ^ The crashed child and everything started after it.
  | AllForOne     -- ^ The whole subtree.
  deriving stock (Eq, Show)

-- | Whether a child is restarted at all, and under what circumstances.
data RestartPolicy
  = Permanent     -- ^ Always restarted, with backoff.
  | Transient     -- ^ Restarted only if it exited abnormally.
  | Temporary     -- ^ Never restarted.
  deriving stock (Eq, Show)

-- | Description of a supervised component.
data ChildSpec = ChildSpec
  { childName     :: !Text
  , childAction   :: !(IO ())
    -- ^ The component body. Expected to block until shutdown; it must treat
    --   an asynchronous exception as the shutdown signal.
  , childRestart  :: !RestartPolicy
  , childShutdown :: !NominalDiffTime
    -- ^ How long to wait for a graceful exit before the thread is killed.
  }

-- | 'IO ()' has no 'Show' instance, so 'ChildSpec' cannot derive one.
instance Show ChildSpec where
  show s = "ChildSpec { childName = " ++ show (childName s)
        ++ ", childRestart = " ++ show (childRestart s)
        ++ ", childShutdown = " ++ show (childShutdown s)
        ++ " }"

-- | What the supervisor decided after a child exited.
data RestartReport = RestartReport
  { reportChild     :: !Text
  , reportAbnormal  :: !Bool
  , reportRestarted :: !Bool
  , reportReason    :: !(Maybe Text)
  } deriving stock (Eq, Show)

-- | A supervisor: a strategy plus the children currently running under it.
data Supervisor = Supervisor
  { supStrategy    :: !RestartStrategy
  , supChildren    :: !(TVar (Seq (ChildSpec, ThreadId)))
  , supMaxRestarts :: !Int
  , supPeriod     :: !NominalDiffTime
  , supRestarts    :: !(TVar [UTCTime])
  , supLastReport  :: !(TVar [RestartReport])
  }

-- | Create a supervisor with a restart-intensity limit.
newSupervisor
  :: RestartStrategy
  -> Int                 -- ^ max restarts inside 'supPeriod'
  -> NominalDiffTime     -- ^ the window, in seconds
  -> IO Supervisor
newSupervisor strategy maxRestarts period = Supervisor
  <$> pure strategy
  <*> newTVarIO Seq.empty
  <*> pure maxRestarts
  <*> pure period
  <*> newTVarIO []
  <*> newTVarIO []

-- | Start a child and begin supervising it.
startChild :: Supervisor -> ChildSpec -> IO ()
startChild sup spec = do
  tid <- forkFinally (childAction spec) (handleExit sup spec)
  atomically $ modifyTVar' (supChildren sup) (Seq.|> (spec, tid))

-- | Stop a child: drop it from the table and interrupt its thread.
--
-- The thread is interrupted rather than cooperatively signalled, because
-- 'childAction' is an opaque blocking action. A child that must release
-- resources should install an exception handler.
stopChild :: Supervisor -> Text -> IO ()
stopChild sup name = do
  mTid <- atomically $ do
    children <- readTVar (supChildren sup)
    let (match, rest) = Seq.partition ((== name) . childName . fst) children
    writeTVar (supChildren sup) rest
    pure (fmap snd (Seq.lookup 0 match))
  case mTid of
    Nothing  -> pure ()
    Just tid -> killThread tid

-- | Stop every child.
stopAll :: Supervisor -> IO ()
stopAll sup = do
  tids <- atomically $ do
    children <- readTVar (supChildren sup)
    writeTVar (supChildren sup) Seq.empty
    pure (map snd (toList children))
  mapM_ killThread tids

-- | Names of the currently supervised children.
supervisorChildren :: Supervisor -> IO [Text]
supervisorChildren sup =
  map (childName . fst) . toList <$> atomically (readTVar (supChildren sup))

-- | How many times the named child has been restarted.
childRestartCount :: Supervisor -> Text -> IO Int
childRestartCount sup name =
  length . filter ((== name) . reportChild)
    <$> atomically (readTVar (supLastReport sup))

-- | Exponential backoff for a restart, in microseconds.
--
-- Attempt @n@ waits @min (2^n * 100ms) 10s@; the ceiling keeps a flapping
-- adapter from spinning the CPU.
backoffDelay :: Int -> Int
backoffDelay n = min 10000000 (100000 * (2 ^ n))

-- * Internals --------------------------------------------------------------

handleExit
  :: Supervisor
  -> ChildSpec
  -> Either SomeException ()   -- ^ Right = clean exit, Left = crashed
  -> IO ()
handleExit sup spec outcome = do
  now <- getCurrentTime
  let abnormal = either (const True) (const False) outcome
      shouldRestart = case childRestart spec of
        Permanent -> True
        Transient -> abnormal
        Temporary -> False
  within <- atomically $ do
    rs <- readTVar (supRestarts sup)
    let recent = [ t | t <- rs, diffUTCTime now t < supPeriod sup ]
    writeTVar (supRestarts sup) (now : recent)
    pure (length recent < supMaxRestarts sup)
  let restarted = shouldRestart && within
  recordRestart sup spec abnormal restarted (either Just (const Nothing) outcome)
  when restarted $ do
    threadDelay (backoffDelay 0)
    startChild sup spec

recordRestart
  :: Supervisor
  -> ChildSpec
  -> Bool
  -> Bool
  -> Maybe SomeException
  -> IO ()
recordRestart sup spec abnormal restarted mexc = atomically $
  modifyTVar' (supLastReport sup) (take 100 . (report :))
  where
    report = RestartReport
      { reportChild     = childName spec
      , reportAbnormal  = abnormal
      , reportRestarted = restarted
      , reportReason    = fmap (T.pack . displayException) mexc
      }
