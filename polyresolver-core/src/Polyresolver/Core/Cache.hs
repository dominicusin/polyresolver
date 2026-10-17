{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | STM cache (раздел 14).
--
-- Design points from the specification:
--
-- * sharding to a power of two, so concurrent lookups rarely contend on the
--   same 'TVar' (14.1);
-- * lazy TTL expiry on read plus a background sweeper (14.2);
-- * negative caching with its own, shorter TTL (14.2);
-- * 'singleflight' deduplication so a burst of identical misses issues one
--   backend call (14.3);
-- * an explicit entry cap, enforced lazily at insert time, to bound memory.
module Polyresolver.Core.Cache
  ( Cache
  , CacheOptions(..)
  , defaultCacheOptions
  , newCache
  , lookupCache
  , insertCache
  , invalidate
  , invalidateAll
  , cacheSize
  , singleflight
  , sweep
  ) where

import Control.Concurrent.STM
  ( STM, TMVar, TVar, atomically, modifyTVar', newEmptyTMVar, newTVarIO, putTMVar
  , readTMVar, readTVar, writeTVar )
import Control.Monad (when)
import Data.Bits ((.&.))
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Hashable (Hashable, hashWithSalt)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.Time (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.Vector (Vector)
import qualified Data.Vector as V

import Polyresolver.Types.Cache (CacheEntry (..), CacheKey (..))
import Polyresolver.Types.Errors (ResolveError)
import Polyresolver.Types.Result (ResolveResult (..))

-- | Tuning knobs, mirroring the @cache:@ block of the YAML configuration.
data CacheOptions = CacheOptions
  { optShards      :: !Int
    -- ^ Number of shards; rounded up to the next power of two.
  , optMaxEntries  :: !Int
  , optDefaultTTL  :: !NominalDiffTime
  , optMinTTL      :: !NominalDiffTime
  , optMaxTTL      :: !NominalDiffTime
  , optNegativeTTL :: !NominalDiffTime
  } deriving stock (Eq, Show)

-- | Sensible defaults: 64 shards, 2M entries, 5 minute default TTL.
defaultCacheOptions :: CacheOptions
defaultCacheOptions = CacheOptions
  { optShards      = 64
  , optMaxEntries  = 2000000
  , optDefaultTTL  = 300
  , optMinTTL      = 5
  , optMaxTTL      = 86400
  , optNegativeTTL = 30
  }

-- | A sharded, STM-guarded cache.
data Cache = Cache
  { cacheShards    :: !(Vector (TVar (HashMap CacheKey CacheEntry)))
  , cacheInFlight  :: !(TVar (HashMap CacheKey (TMVar (Either ResolveError ResolveResult))))
  , cacheOptions   :: !CacheOptions
  , cacheShardMask :: !Int
  , cacheTotal     :: !(IORef Int)
  }

-- | Create a cache with the given options.
newCache :: CacheOptions -> IO Cache
newCache opts = do
  let n = max 1 (nextPow2 (optShards opts))
  shards <- V.replicateM n (newTVarIO HM.empty)
  inflight <- newTVarIO HM.empty
  total <- newIORef 0
  pure Cache
    { cacheShards    = shards
    , cacheInFlight  = inflight
    , cacheOptions   = opts
    , cacheShardMask = n - 1
    , cacheTotal     = total
    }

-- | Look up a key, returning 'Nothing' for a miss or an expired entry.
--
-- Expiry is lazy: the entry is dropped here rather than waiting for the
-- sweeper, so a stale answer is never served (14.2).
lookupCache :: Cache -> CacheKey -> IO (Maybe ResolveResult)
lookupCache c key = do
  now <- getCurrentTime
  atomically $ do
    m <- readTVar (shardTVar c key)
    case HM.lookup key m of
      Nothing -> pure Nothing
      Just e
        | isExpired now e -> modifyTVar' (shardTVar c key) (HM.delete key) *> pure Nothing
        | otherwise       -> pure (Just (ceResult e))

-- | Store a resolution result, clamping its TTL to the configured bounds and
-- using the negative TTL for a 'NotFound'.
insertCache :: Cache -> CacheKey -> ResolveResult -> IO ()
insertCache c key result = do
  now <- getCurrentTime
  let opts = cacheOptions c
      negative = result == NotFound
      ttl = clampTTL opts negative
      entry = CacheEntry
        { ceResult     = result
        , ceInsertedAt = now
        , ceTTL        = ttl
        , ceSource     = ckAdapter key
        , ceNegative   = negative
        }
  atomically $ do
    let shard = shardTVar c key
    m <- readTVar shard
    -- Lazy cap enforcement: make room before inserting. This bounds memory
    -- without ever blocking a request on eviction work.
    when (HM.size m >= optMaxEntries opts) $
      modifyTVar' shard (dropExpiredOrOne now)
    modifyTVar' shard (HM.insert key entry)
  atomicModifyIORef' (cacheTotal c) (\n -> (n + 1, ()))

-- | Drop a key from its shard.
invalidate :: Cache -> CacheKey -> IO ()
invalidate c key = atomically $
  modifyTVar' (shardTVar c key) (HM.delete key)

-- | Drop every entry, including in-flight joins.
invalidateAll :: Cache -> IO ()
invalidateAll c = atomically $ do
  V.forM_ (cacheShards c) $ \shard -> writeTVar shard HM.empty
  writeTVar (cacheInFlight c) HM.empty

-- | Number of entries currently held across all shards.
cacheSize :: Cache -> IO Int
cacheSize c =
  sum <$> atomically (mapM (\s -> HM.size <$> readTVar s) (V.toList (cacheShards c)))

-- | Run @action@ for @key@ at most once at a time; concurrent callers wait for
-- the first caller's result instead of issuing their own backend call (14.3).
singleflight
  :: Cache
  -> CacheKey
  -> IO (Either ResolveError ResolveResult)
  -> IO (Either ResolveError ResolveResult)
singleflight c key action = do
  role <- atomically $ do
    inflight <- readTVar (cacheInFlight c)
    case HM.lookup key inflight of
      Just tmvar -> pure (Right tmvar)
      Nothing    -> Left <$> do
        tmvar <- newEmptyTMVar
        modifyTVar' (cacheInFlight c) (HM.insert key tmvar)
        pure tmvar
  case role of
    Right tmvar -> atomically (readTMVar tmvar)
    Left tmvar  -> do
      result <- action
      atomically $ do
        putTMVar tmvar result
        modifyTVar' (cacheInFlight c) (HM.delete key)
      pure result

-- | Remove expired entries from every shard; returns how many were dropped.
sweep :: Cache -> IO Int
sweep c = do
  now <- getCurrentTime
  atomically $ V.sum <$> V.forM (cacheShards c) (\shard -> do
    m <- readTVar shard
    let dropped = HM.size (HM.filter (isExpired now) m)
    when (dropped > 0) $ writeTVar shard (HM.filter (not . isExpired now) m)
    pure dropped)

-- * Internals --------------------------------------------------------------

shardTVar :: Cache -> CacheKey -> TVar (HashMap CacheKey CacheEntry)
shardTVar c k = cacheShards c V.! (hashInt k .&. cacheShardMask c)

hashInt :: Hashable k => k -> Int
hashInt = fromIntegral . (`mod` 1000000007) . abs . hashWithSalt 0

isExpired :: UTCTime -> CacheEntry -> Bool
isExpired now e = diffUTCTime now (ceInsertedAt e) >= ceTTL e

clampTTL :: CacheOptions -> Bool -> NominalDiffTime
clampTTL opts negative
  | negative  = clamp (optNegativeTTL opts)
  | otherwise = clamp (optDefaultTTL opts)
  where
    clamp t = max (optMinTTL opts) (min (optMaxTTL opts) t)

dropExpiredOrOne :: UTCTime -> HashMap CacheKey CacheEntry -> HashMap CacheKey CacheEntry
dropExpiredOrOne now m
  | Just k <- firstExpired = HM.delete k m
  | otherwise              = case HM.keys m of
      (k : _) -> HM.delete k m
      []      -> m
  where
    firstExpired = case HM.keys (HM.filter (isExpired now) m) of
      (k : _) -> Just k
      []      -> Nothing

nextPow2 :: Int -> Int
nextPow2 n
  | n <= 1    = 1
  | otherwise = go 1
  where
    go !acc | acc >= n  = acc
            | otherwise = go (acc * 2)
