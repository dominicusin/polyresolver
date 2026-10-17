{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Metrics
  ( MetricsConfig(..)
  , defaultMetricsConfig
  , runMetricsServer
  , recordQuery
  , recordCacheHit
  , recordCacheMiss
  , recordAdapterLatency
  , recordAdapterRestart
  , recordCacheSize
  , recordDNSError
  , recordGraphDepth
  , recordGraphCycle
  ) where

import Control.Concurrent (forkIO)
import Control.Monad (forever, void)
import Data.Text (Text)
import qualified Data.Text as T
import Network.Wai (Application, responseLBS)
import Network.Wai.Handler.Warp (run)
import Network.HTTP.Types (status200)
import Data.Time (NominalDiffTime)

data MetricsConfig = MetricsConfig
  { mcEnabled  :: !Bool
  , mcAddress  :: !Text
  , mcPort     :: !Int
  } deriving stock (Eq, Show)

defaultMetricsConfig :: MetricsConfig
defaultMetricsConfig = MetricsConfig
  { mcEnabled = True
  , mcAddress = "127.0.0.1"
  , mcPort = 9153
  }

runMetricsServer :: MetricsConfig -> IO ()
runMetricsServer config = do
  if mcEnabled config
    then do
      let port = mcPort config
      run port metricsApp
    else pure ()

recordQuery :: Text -> Text -> Text -> IO ()
recordQuery adapter zone result = void $ pure ()

recordCacheHit :: Text -> IO ()
recordCacheHit adapter = void $ pure ()

recordCacheMiss :: Text -> IO ()
recordCacheMiss adapter = void $ pure ()

recordAdapterLatency :: Text -> NominalDiffTime -> IO ()
recordAdapterLatency adapter latency = void $ pure ()

recordAdapterRestart :: Text -> IO ()
recordAdapterRestart adapter = void $ pure ()

recordCacheSize :: Int -> IO ()
recordCacheSize size = void $ pure ()

recordDNSError :: Text -> IO ()
recordDNSError rcode = void $ pure ()

recordGraphDepth :: Int -> IO ()
recordGraphDepth depth = void $ pure ()

recordGraphCycle :: Text -> IO ()
recordGraphCycle adapterPair = void $ pure ()

metricsApp :: Application
metricsApp = \req send -> send $ responseLBS status200 [] "Prometheus metrics"
