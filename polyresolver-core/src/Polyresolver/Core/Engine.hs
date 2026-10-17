{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | The resolution engine: routing → cache → adapter, with delegation and
-- cycle detection (раздел 5.4).
--
-- Request flow (5.4):
--
-- 1. route the query name to exactly one adapter (ТРЕБ-001/002);
-- 2. consult the STM cache by @(name, type, adapter)@;
-- 3. on a miss, call the adapter under its supervisor timeout, deduplicated
--    by 'singleflight';
-- 4. normalise the answer; a 'Delegate' result appends a node to the
--    'ResolutionGraph' and re-enters at step 1 after 'detectCycle' (ТРЕБ-018);
-- 5. cache the outcome and return it.
module Polyresolver.Core.Engine
  ( Engine
  , EngineStats(..)
  , defaultMaxDepth
  , newEngine
  , engineAdapters
  , resolve
  , engineStats
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar)
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text, intercalate, pack)


import Polyresolver.Types.Adapters (AdapterId (..), Priority)
import Polyresolver.Types.Cache (CacheKey (..))
import Polyresolver.Types.Errors (ResolveError (..))
import Polyresolver.Types.Graph
  ( ResolutionGraph (..), ResolutionNode (..), detectCycle, graphDepth, unGraph )
import Polyresolver.Types.Request (ResolveRequest (..))
import Polyresolver.Types.Result
  ( BackendError (..), DelegateTarget (..), ResolveResult (..) )

import Polyresolver.Core.Adapter (AdapterEntry (..), entryRoutes)
import Polyresolver.Core.Cache (Cache, insertCache, lookupCache, singleflight)
import Polyresolver.Core.Routing
  ( ConflictPolicy (..), RouteDecision (..), RoutingTable, buildTable, lookupRoute )

-- | Default delegation depth guard. The real bound is 'detectCycle'; this is
-- a second net in case a future adapter family grows the chain without
-- repeating a node.
defaultMaxDepth :: Int
defaultMaxDepth = 16

-- | Counters surfaced by the metrics package (раздел 17).
data EngineStats = EngineStats
  { statsQueries     :: !Int
  , statsCacheHits   :: !Int
  , statsDelegations :: !Int
  , statsCycles      :: !Int
  , statsNoRoute     :: !Int
  } deriving stock (Eq, Show)

-- | The running engine.
data Engine = Engine
  { engRoutes   :: !(TVar RoutingTable)
  , engAdapters :: !(TVar (HashMap AdapterId AdapterEntry))
  , engCache    :: !Cache
  , engMaxDepth :: !Int
  , engStats    :: !(IORef EngineStats)
  }

-- | Build an engine from a cache and adapters with explicit priorities.
-- Refuses a namespace claimed by two adapters (ТРЕБ-001).
newEngine
  :: Cache
  -> [(Priority, AdapterEntry)]
  -> IO (Either Text Engine)
newEngine cache adapters = case buildTable Explicit routes of
  Left err -> pure (Left err)
  Right table -> do
    routesVar <- newTVarIO table
    adaptersVar <- newTVarIO (HM.fromList [ (aeId e, e) | (_, e) <- adapters ])
    stats <- newIORef (EngineStats 0 0 0 0 0)
    pure (Right Engine
      { engRoutes   = routesVar
      , engAdapters = adaptersVar
      , engCache    = cache
      , engMaxDepth = defaultMaxDepth
      , engStats    = stats
      })
  where
    routes = concat [ entryRoutes prio e | (prio, e) <- adapters ]

-- | Names of the adapters currently registered.
engineAdapters :: Engine -> IO [Text]
engineAdapters eng =
  map aeName . HM.elems <$> atomically (readTVar (engAdapters eng))

-- | Snapshot of the counters.
engineStats :: Engine -> IO EngineStats
engineStats = readIORef . engStats

-- | Resolve one query.
resolve :: Engine -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolve eng req = do
  incQueries eng
  table <- atomically (readTVar (engRoutes eng))
  case lookupRoute (reqName req) table of
    NoRoute -> do
      incNoRoute eng
      pure (Right NotFound)          -- ТРЕБ-003: no heuristic guessing
    RouteConflict claims -> do
      incNoRoute eng
      pure (Left (ZoneConflict ("routing conflict: " <> renderClaims claims)))
    RouteTo adapterId -> do
      adapters <- atomically (readTVar (engAdapters eng))
      case HM.lookup adapterId adapters of
        Nothing -> pure (Left (ZoneConflict ("unknown adapter " <> unAdapterId adapterId)))
        Just entry -> resolveVia eng entry req

-- * Internals --------------------------------------------------------------

resolveVia
  :: Engine
  -> AdapterEntry
  -> ResolveRequest
  -> IO (Either ResolveError ResolveResult)
resolveVia eng entry req = do
  let key = CacheKey (reqName req) (reqType req) (aeId entry)
  cached <- lookupCache (engCache eng) key
  case cached of
    Just r -> do
      incCacheHits eng
      pure (Right r)
    Nothing -> do
      result <- singleflight (engCache eng) key (callAdapter entry req)
      case result of
        Left err -> pure (Left err)
        Right r  -> do
          insertCache (engCache eng) key r
          case r of
            Delegate target -> handleDelegate eng entry req target
            _               -> pure (Right r)

-- | Call the adapter, bounded by its supervisor timeout (ТРЕБ-020).
--
-- On timeout the in-flight thread is abandoned (its result is discarded by
-- 'race'); the answer is 'TemporarilyUnavailable', which the policy layer maps
-- to SERVFAIL for authoritative adapters (ТРЕБ-021).
callAdapter
  :: AdapterEntry
  -> ResolveRequest
  -> IO (Either ResolveError ResolveResult)
callAdapter entry req = do
  let budgetUs = aeTimeoutMs entry * 1000
  won <- race (threadDelay budgetUs) (Just <$> aeResolve entry req)
  pure $ case won of
    Left  _      -> Right (TemporarilyUnavailable (Timeout (aeTimeoutMs entry)))
    Right Nothing -> Right (TemporarilyUnavailable (Timeout (aeTimeoutMs entry)))
    Right (Just result) -> result

handleDelegate
  :: Engine
  -> AdapterEntry
  -> ResolveRequest
  -> DelegateTarget
  -> IO (Either ResolveError ResolveResult)
handleDelegate eng entry req target = do
  incDelegations eng
  let node = ResolutionNode
        { rnAdapter = aeName entry
        , rnName    = reqName req
        , rnType    = reqType req
        }
  case detectCycle (ResolutionGraph (reqGraph req)) node of
    Left err -> do
      incCycles eng
      pure (Left (CycleDetected err))
    Right graph
      | graphDepth graph >= engMaxDepth eng ->
          pure (Left (MaxDepthExceeded (graphDepth graph)))
      | otherwise ->
          resolve eng (req { reqName = dtName target, reqGraph = unGraph graph })

-- * Counters --------------------------------------------------------------

inc :: Engine -> (EngineStats -> EngineStats) -> IO ()
inc eng f = atomicModifyIORef' (engStats eng) $ \s -> (f s, ())

incField :: (EngineStats -> EngineStats) -> Engine -> IO ()
incField f eng = inc eng f

incQueries, incCacheHits, incDelegations, incCycles, incNoRoute :: Engine -> IO ()
incQueries     = incField (\s -> s { statsQueries     = statsQueries s + 1 })
incCacheHits   = incField (\s -> s { statsCacheHits   = statsCacheHits s + 1 })
incDelegations = incField (\s -> s { statsDelegations = statsDelegations s + 1 })
incCycles      = incField (\s -> s { statsCycles      = statsCycles s + 1 })
incNoRoute     = incField (\s -> s { statsNoRoute     = statsNoRoute s + 1 })

renderClaims :: [(AdapterId, Priority)] -> Text
renderClaims = intercalate ", " . map (\(a, p) -> unAdapterId a <> "@" <> pack (show p))
