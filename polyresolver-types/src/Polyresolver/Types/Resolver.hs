{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

-- | The 'Resolver' typeclass: the single extension point of polyresolver
-- (раздел 6.2).
--
-- A new adapter is a new 'Resolver' instance plus a routing entry — no changes
-- to the routing engine, cache or API (ТРЕБ-012).
module Polyresolver.Types.Resolver
  ( Resolver(..)
  , AdapterHandle(..)
  ) where

import Data.Text (Text)

import Polyresolver.Types.Adapters (AdapterId, NamingModel)
import Polyresolver.Types.Namespace (ZonePattern)
import Polyresolver.Types.Request (ResolveRequest)
import Polyresolver.Types.Errors (ResolveError)
import Polyresolver.Types.Result (HealthStatus, ResolveResult)

-- | Everything the core needs from an adapter.
--
-- The class is deliberately small and effect-polymorphic: in-process adapters
-- instantiate it at @m ~ IO@, while the Plugin SDK (раздел 6.5) instantiates it
-- at an IPC-backed monad. The core only ever sees @Resolver m a@.
class Monad m => Resolver m a where
  -- | Stable identity used for routing, metric labels and cache keys.
  resolverId :: a -> AdapterId

  -- | Human-readable adapter name.
  resolverName :: a -> Text

  -- | Namespaces this adapter is authoritative for. ТРЕБ-001 requires exactly
  -- one authoritative adapter per namespace, with no implicit fallback.
  resolverZones :: a -> [ZonePattern]

  -- | Taxonomy category (раздел 3) — diagnostics and metrics only.
  resolverModel :: a -> NamingModel

  -- | True for authoritative backends, false for convenience adapters.
  -- Authoritative adapters fail closed (SERVFAIL, ТРЕБ-021); convenience
  -- adapters may serve stale when policy allows it.
  resolverAuthoritative :: a -> Bool

  -- | Timeout budget for one call, in milliseconds.
  resolverTimeoutMs :: a -> Int

  -- | Perform one resolution step.
  resolve :: a -> ResolveRequest -> m (Either ResolveError ResolveResult)

  -- | Lightweight liveness probe; drives @polyresolver_adapter_up@.
  healthCheck :: a -> m HealthStatus

  -- | Release resources. Idempotent.
  shutdown :: a -> m ()

-- | Opaque reference to a running adapter, as stored by the supervisor tree.
--
-- In-process adapters keep the adapter value itself; out-of-process adapters
-- keep the IPC channel. The core never inspects it.
data AdapterHandle m a = AdapterHandle
  { ahSpec      :: !a
  , ahIsRunning :: !(m Bool)
  }