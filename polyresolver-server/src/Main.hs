{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (void)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getArgs)

import Polyresolver.Config (loadConfig, defaultConfig, Config(..), DNSConfig(..), APIConfig(..), MetricsConfig(..))
import Polyresolver.Core.Engine (Engine, newEngine, resolve)
import Polyresolver.Core.Cache (newCache, defaultCacheOptions)
import qualified Polyresolver.DNS as DNS
import qualified Polyresolver.API as API
import qualified Polyresolver.Metrics as Metrics

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("--config" : path : _) -> do
      cfgResult <- loadConfig path
      case cfgResult of
        Left err -> putStrLn $ "Config error: " ++ err
        Right cfg -> runServer cfg
    _ -> runServer defaultConfig

runServer :: Config -> IO ()
runServer cfg = do
  cache <- newCache defaultCacheOptions
  engResult <- newEngine cache []
  case engResult of
    Left err -> error (T.unpack err)
    Right engine -> do
      -- Start DNS server
      case cDNS cfg of
        Just dnsCfg -> void $ forkIO $ DNS.runDNSServer engine (DNS.DNSConfig (dcAddress dnsCfg) (dcPort dnsCfg))
        Nothing -> pure ()

      -- Start API server
      case cAPI cfg of
        Just apiCfg -> void $ forkIO $ API.runAPI engine (API.APIConfig (acAddress apiCfg) (acPort apiCfg))
        Nothing -> pure ()

      -- Start metrics server
      case cMetrics cfg of
        Just metricsCfg -> void $ forkIO $ Metrics.runMetricsServer (Metrics.MetricsConfig (mcEnabled metricsCfg) (mcAddress metricsCfg) (mcPort metricsCfg))
        Nothing -> pure ()

      -- Keep main thread alive
      forever (threadDelay 1000000)
  where
    forever m = m >> forever m
