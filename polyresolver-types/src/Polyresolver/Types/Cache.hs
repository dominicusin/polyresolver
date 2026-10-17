{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

-- | Cache key and entry (раздел 14.1).
module Polyresolver.Types.Cache
  ( CacheKey(..)
  , CacheEntry(..)
  , CacheShard
  , mkCacheKey
  ) where

import Data.Hashable (Hashable)
import Data.Text (Text)
import Data.Time (UTCTime, NominalDiffTime)
import GHC.Generics (Generic)

import Polyresolver.Types.Adapters (AdapterId)
import Polyresolver.Types.QType (QType (..))
import Polyresolver.Types.Result (ResolveResult)

-- | Cache identity: the same query always maps to the same shard key.
--
-- @polyresolver-core@ hashes this value to select one of the @2^k@ shards,
-- which keeps STM transaction contention flat under high concurrency
-- (раздел 14.1).
data CacheKey = CacheKey
  { ckName    :: !Text
  , ckType    :: !QType
  , ckAdapter :: !AdapterId
  } deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (Hashable)

-- | A cached resolution outcome.
data CacheEntry = CacheEntry
  { ceResult     :: !ResolveResult
  , ceInsertedAt :: !UTCTime
  , ceTTL        :: !NominalDiffTime
  , ceSource     :: !AdapterId
  , ceNegative   :: !Bool
    -- ^ Negative caching (NotFound) — usually a shorter TTL, see 14.2.
  } deriving stock (Eq, Show, Generic)

-- | One STM-atomically guarded hash map. The 'TVar' lives in @polyresolver-core@;
-- the type is declared here so the shard layout is part of the public contract.
data CacheShard = CacheShard
  deriving stock (Show)

-- | Convenience constructor.
mkCacheKey :: Text -> QType -> AdapterId -> CacheKey
mkCacheKey = CacheKey