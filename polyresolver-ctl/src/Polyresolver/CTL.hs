{-# LANGUAGE DerivingStrategies #-}

module Polyresolver.CTL
  ( CTLCommand(..)
  , CTLConfig(..)
  , runCTL
  , main
  ) where

import Control.Exception (try, SomeException)
import Control.Monad (void)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import Polyresolver.Core.Engine (Engine, resolve, engineAdapters, engineStats)
import Polyresolver.Types.Request (ResolveRequest(..), newResolveRequest)
import Polyresolver.Types.ClientContext (ClientContext(..))
import Polyresolver.Types.QType (QType(..))
import Polyresolver.Types.Graph (ResolutionGraph(..))
import Polyresolver.Types.Result (ResolveResult(..))
import Polyresolver.Types.Errors (ResolveError(..))

data CTLCommand
  = Resolve Text (Maybe Text)
  | Graph Text
  | Cache
  | CacheInvalidate Text
  | Adapters
  | AdapterHealth Text
  | AdapterReload Text
  | Health
  | Config
  deriving stock (Eq, Show)

data CTLConfig = CTLConfig
  { ctlAddress :: !String
  , ctlPort    :: !Int
  } deriving stock (Eq, Show)

runCTL :: CTLConfig -> CTLCommand -> IO ()
runCTL config cmd = case cmd of
  Resolve name mtype -> resolveCmd name mtype
  Graph name -> graphCmd name
  Cache -> cacheCmd
  CacheInvalidate name -> cacheInvalidateCmd name
  Adapters -> adaptersCmd
  AdapterHealth name -> adapterHealthCmd name
  AdapterReload name -> adapterReloadCmd name
  Health -> healthCmd
  Config -> configCmd

resolveCmd :: Text -> Maybe Text -> IO ()
resolveCmd name mtype = do
  putStrLn $ "Resolving " ++ T.unpack name

graphCmd :: Text -> IO ()
graphCmd name = do
  putStrLn $ "Graph for " ++ T.unpack name

cacheCmd :: IO ()
cacheCmd = putStrLn "Cache stats"

cacheInvalidateCmd :: Text -> IO ()
cacheInvalidateCmd name = putStrLn $ "Invalidating " ++ T.unpack name

adaptersCmd :: IO ()
adaptersCmd = putStrLn "Adapters"

adapterHealthCmd :: Text -> IO ()
adapterHealthCmd name = putStrLn $ "Health of " ++ T.unpack name

adapterReloadCmd :: Text -> IO ()
adapterReloadCmd name = putStrLn $ "Reloading " ++ T.unpack name

healthCmd :: IO ()
healthCmd = putStrLn "Health"

configCmd :: IO ()
configCmd = putStrLn "Config"

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("resolve" : name : mtype : _) -> runCTL defaultConfig (Resolve (T.pack name) (Just (T.pack mtype)))
    ("resolve" : name : _) -> runCTL defaultConfig (Resolve (T.pack name) Nothing)
    ("graph" : name : _) -> runCTL defaultConfig (Graph (T.pack name))
    ("cache" : _) -> runCTL defaultConfig Cache
    ("adapters" : _) -> runCTL defaultConfig Adapters
    ("health" : _) -> runCTL defaultConfig Health
    ("config" : _) -> runCTL defaultConfig Config
    _ -> do
      hPutStrLn stderr "Usage: polyresolver-ctl <command> [args]"
      exitFailure

defaultConfig :: CTLConfig
defaultConfig = CTLConfig "127.0.0.1" 8080
