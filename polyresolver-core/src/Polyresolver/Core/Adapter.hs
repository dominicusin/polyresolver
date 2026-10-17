{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Adapter registration (раздел 6.2/6.5).
--
-- The core must hold adapters without knowing their concrete types, so this
-- module defines the type-erased handle that the routing engine, cache and
-- supervisor all operate on. An in-process adapter is a 'Resolver' instance;
-- an out-of-process Plugin SDK adapter satisfies the same record through its
-- IPC channel, which is what keeps ТРЕБ-012 true.
module Polyresolver.Core.Adapter
  ( AdapterEntry(..)
  , mkAdapterEntry
  , entryRoutes
  ) where

import Data.Text (Text)

import Polyresolver.Types.Adapters (AdapterId, NamingModel, Priority)
import Polyresolver.Types.Namespace (ZonePattern)
import Polyresolver.Types.Request (ResolveRequest)
import Polyresolver.Types.Errors (ResolveError)
import Polyresolver.Types.Result (HealthStatus, ResolveResult)

import Polyresolver.Core.Routing (Route (..))

-- | A running adapter, type-erased.
data AdapterEntry = AdapterEntry
  { aeId            :: !AdapterId
  , aeName          :: !Text
  , aeZones         :: ![ZonePattern]
  , aeModel         :: !NamingModel
  , aeAuthoritative :: !Bool
  , aeTimeoutMs     :: !Int
  , aeResolve       :: !(ResolveRequest -> IO (Either ResolveError ResolveResult))
  , aeHealth        :: !(IO HealthStatus)
  , aeShutdown      :: !(IO ())
  }

-- | Build an 'AdapterEntry' from concrete operations.
--
-- This avoids the 'Resolver' multi-parameter class at the call site: adapters
-- that satisfy 'Resolver' can still use 'wrapResolver', while test doubles and
-- IPC-backed plugins build the entry directly.
mkAdapterEntry
  :: AdapterId
  -> Text
  -> [ZonePattern]
  -> NamingModel
  -> Bool
  -> Int
  -> (ResolveRequest -> IO (Either ResolveError ResolveResult))
  -> IO HealthStatus
  -> IO ()
  -> AdapterEntry
mkAdapterEntry aid name zones model authoritative timeout resolve health shutdown = AdapterEntry
  { aeId            = aid
  , aeName          = name
  , aeZones         = zones
  , aeModel         = model
  , aeAuthoritative = authoritative
  , aeTimeoutMs     = timeout
  , aeResolve       = resolve
  , aeHealth        = health
  , aeShutdown      = shutdown
  }

-- | One routing claim per namespace the adapter owns.
--
-- ТРЕБ-001 requires exactly one authoritative adapter per namespace, so an
-- adapter listing the same zone twice is a configuration error caught by
-- 'Polyresolver.Core.Routing.buildTable'.
entryRoutes :: Priority -> AdapterEntry -> [Route]
entryRoutes prio e =
  [ Route { routeAdapter = aeId e, routePattern = z, routePriority = prio }
  | z <- aeZones e
  ]
