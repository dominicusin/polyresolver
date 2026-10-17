{-# LANGUAGE DerivingStrategies #-}
-- | Common types for the polyresolver ecosystem.
--
-- This module re-exports the vocabulary every other polyresolver package
-- speaks: requests, results, zones, adapters, graphs, cache keys and errors.
module Polyresolver.Types
  ( -- * Requests
    ResolveRequest(..)
  , ClientContext(..)
  , QType(..)
  , qTypeText
  , newResolveRequest
    -- * Results
  , ResolveResult(..)
  , StructuredRecord(..)
  , StructuredKind(..)
  , BackendError(..)
  , HealthStatus(..)
  , DelegateTarget(..)
    -- * Namespaces and adapters
  , ZonePattern(..)
  , AdapterId
  , AdapterMeta(..)
  , NamingModel(..)
  , Priority
    -- * Resolution graph
  , ResolutionNode(..)
  , ResolutionGraph(..)
  , CycleError(..)
  , detectCycle
  , graphDepth
  , graphNodes
  , emptyGraph
  , appendNode
    -- * Cache
  , CacheKey(..)
  , CacheEntry(..)
  , CacheShard
  , mkCacheKey
    -- * Errors and the extension point
  , ResolveError(..)
  , resolveErrorToText
  , Resolver(..)
  , AdapterHandle(..)
  ) where

import Polyresolver.Types.Adapters
import Polyresolver.Types.Cache
import Polyresolver.Types.Errors
import Polyresolver.Types.Graph
import Polyresolver.Types.Namespace
import Polyresolver.Types.QType
import Polyresolver.Types.Request
import Polyresolver.Types.Resolver
import Polyresolver.Types.Result