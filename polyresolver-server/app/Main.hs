{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (race)
import Control.Exception (try, SomeException)
import Control.Monad (forever, unless, void)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (getArgs)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import Polyresolver.Config
import Polyresolver.Config.Loader
import Polyresolver.Config.Schema
import Polyresolver.Core
import Polyresolver.Core.Cache
import Polyresolver.Core.Engine
import Polyresolver.Core.Routing
import Polyresolver.Core.Supervisor
import Polyresolver.DNS
import Polyresolver.API
import Polyresolver.Metrics
import Polyresolver.CTL

main :: IO ()
main = do
  args <- getArgs
  case args of
    ("--config" : path : _) -> runServer path
    ("--help" : _)          -> showHelp
    _                       -> showHelp

runServer :: FilePath -> IO ()
runServer configPath = do
  putStrLn "polyresolver-server starting..."
  configResult <- loadConfigWithEnv configPath
  case configResult of
    Left err -> do
      hPutStrLn stderr ("Failed to load config: " ++ err)
      exitFailure
    Right config -> do
      putStrLn ("Loaded config from " ++ configPath)
      cache <- newCache (cacheOptionsFromConfig config)
      adapters <- initAdapters (cfgAdapters config)
      case newEngine cache adapters of
        Left err -> do
          hPutStrLn stderr ("Failed to create engine: " ++ T.unpack err)
          exitFailure
        Right engine -> do
          putStrLn ("Engine created with " ++ show (length adapters) ++ " adapters")
          let dnsConfig = dnsConfigFromConfig config
          let apiConfig = apiConfigFromConfig config
          let metricsConfig = metricsConfigFromConfig config
          _ <- forkIO $ runDNSServer engine dnsConfig
          _ <- forkIO $ runAPI engine apiConfig
          _ <- forkIO $ runMetricsServer metricsConfig
          putStrLn "All servers started"
          forever $ threadDelay 1000000

initAdapters :: HashMap Text AdapterConfig -> IO [(Priority, AdapterEntry)]
initAdapters configs = do
  results <- mapM (\(name, cfg) -> do
    result <- try $ initAdapter name cfg
    case result of
      Left err -> do
        hPutStrLn stderr ("Failed to init adapter " ++ T.unpack name ++ ": " ++ show (err :: SomeException))
        pure Nothing
      Right entry -> pure (Just entry)
    ) (HM.toList configs)
  pure [ (aePriority e, e) | Just e <- results ]

initAdapter :: Text -> AdapterConfig -> IO AdapterEntry
initAdapter name cfg
  | name == "unbound" = unboundAdapter (adapterConfigToUnboundConfig cfg)
  | name == "ncdns"   = ncdnsAdapter (adapterConfigToNcdnsConfig cfg)
  | name == "emerdns" = emerdnsAdapter (adapterConfigToEmerDNSConfig cfg)
  | name == "hsd"     = hsdAdapter (adapterConfigToHSDConfig cfg)
  | name == "ens"     = ensAdapter (adapterConfigToENSConfig cfg)
  | name == "tor"     = torAdapter (adapterConfigToTorConfig cfg)
  | name == "i2p"     = i2pAdapter (adapterConfigToI2PConfig cfg)
  | name == "mesh"    = meshAdapter (adapterConfigToMeshConfig cfg)
  | name == "decentweb" = decentwebAdapter (adapterConfigToDecentWebConfig cfg)
  | name == "darknet" = darknetAdapter (adapterConfigToDarknetConfig cfg)
  | name == "filter"  = filterAdapter (adapterConfigToFilterConfig cfg)
  | otherwise         = error ("Unknown adapter: " ++ T.unpack name)

showHelp :: IO ()
showHelp = do
  putStrLn "polyresolver-server - universal DNS-compatible name resolver"
  putStrLn ""
  putStrLn "Usage: polyresolver-server --config <path>"
  putStrLn ""
  putStrLn "Options:"
  putStrLn "  --config <path>  Path to YAML configuration file"
  putStrLn "  --help           Show this help message"

cacheOptionsFromConfig :: Config -> CacheOptions
cacheOptionsFromConfig config = CacheOptions
  { optShards       = ccShards (cfgCache config)
  , optMaxEntries   = ccMaxEntries (cfgCache config)
  , optDefaultTTL   = fromIntegral (ccDefaultTTL (cfgCache config))
  , optMinTTL       = fromIntegral (ccMinTTL (cfgCache config))
  , optMaxTTL       = fromIntegral (ccMaxTTL (cfgCache config))
  , optNegativeTTL  = fromIntegral (ccNegativeTTL (cfgCache config))
  }

dnsConfigFromConfig :: Config -> DNSConfig
dnsConfigFromConfig config = DNSConfig
  { dcAddress = lcAddress (head (cfgListeners config))
  , dcPort    = lcPort (head (cfgListeners config))
  }

apiConfigFromConfig :: Config -> APIConfig
apiConfigFromConfig config = APIConfig
  { acAddress = apiAddress (cfgAPI config)
  , acPort    = apiPort (cfgAPI config)
  }

metricsConfigFromConfig :: Config -> MetricsConfig
metricsConfigFromConfig config = MetricsConfig
  { mcEnabled = mcEnabled (cfgMetrics config)
  , mcAddress = mcAddress (cfgMetrics config)
  , mcPort    = mcPort (cfgMetrics config)
  }

adapterConfigToUnboundConfig :: AdapterConfig -> UnboundConfig
adapterConfigToUnboundConfig cfg = UnboundConfig
  { ucUpstream = fromMaybe "127.0.0.1:5335" (acUpstream cfg)
  , ucTimeoutMs = acTimeoutMs cfg
  }

adapterConfigToNcdnsConfig :: AdapterConfig -> NcdnsConfig
adapterConfigToNcdnsConfig cfg = NcdnsConfig
  { ncMode = acMode cfg
  , ncUpstream = fromMaybe "127.0.0.1:5333" (acUpstream cfg)
  , ncTimeoutMs = acTimeoutMs cfg
  }

adapterConfigToEmerDNSConfig :: AdapterConfig -> EmerDNSConfig
adapterConfigToEmerDNSConfig cfg = EmerDNSConfig
  { ecMode = acMode cfg
  , ecUpstream = fromMaybe "127.0.0.1:5333" (acUpstream cfg)
  , ecTimeoutMs = acTimeoutMs cfg
  }

adapterConfigToHSDConfig :: AdapterConfig -> HSDConfig
adapterConfigToHSDConfig cfg = HSDConfig
  { hcMode = acMode cfg
  , hcUpstream = fromMaybe "127.0.0.1:5350" (acUpstream cfg)
  , hcTimeoutMs = acTimeoutMs cfg
  , hcNativeRootView = Nothing
  }

adapterConfigToENSConfig :: AdapterConfig -> ENSConfig
adapterConfigToENSConfig cfg = ENSConfig
  { ecMode = acMode cfg
  , ecEthereumRPC = fromMaybe "https://localhost:8545" (acUpstream cfg)
  , ecRegistryAddress = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"
  , ecTimeoutMs = acTimeoutMs cfg
  , ecFabricateAAAA = False
  }

adapterConfigToTorConfig :: AdapterConfig -> TorConfig
adapterConfigToTorConfig cfg = TorConfig
  { tcSocksProxy = fromMaybe "127.0.0.1:9050" (acUpstream cfg)
  }

adapterConfigToI2PConfig :: AdapterConfig -> I2PConfig
adapterConfigToI2PConfig cfg = I2PConfig
  { icSAMEndpoint = fromMaybe "127.0.0.1:7656" (acUpstream cfg)
  }

adapterConfigToMeshConfig :: AdapterConfig -> MeshConfig
adapterConfigToMeshConfig cfg = MeshConfig
  { mcYggdrasilRegistry = fromMaybe "/etc/polyresolver/yggdrasil-names.yaml" (HM.lookup "yggdrasil_registry" (acOptions cfg))
  , mcCjdnsUpstream = acUpstream cfg
  , mcReticulumRegistry = fromMaybe "/etc/polyresolver/reticulum-names.yaml" (HM.lookup "reticulum_registry" (acOptions cfg))
  , mcOLSRHostsPath = fromMaybe "/var/run/hosts_olsr" (HM.lookup "olsr_hosts_path" (acOptions cfg))
  }

adapterConfigToDecentWebConfig :: AdapterConfig -> DecentWebConfig
adapterConfigToDecentWebConfig cfg = DecentWebConfig
  { dcIPFSAPIEndpoint = fromMaybe "127.0.0.1:5001" (HM.lookup "ipfs_api_endpoint" (acOptions cfg))
  , dcDNSLink = True
  , dcHyphanetFCPEndpoint = fromMaybe "127.0.0.1:9481" (HM.lookup "hyphanet_fcp_endpoint" (acOptions cfg))
  , dcGNSUpstream = fromMaybe "127.0.0.1:5353" (HM.lookup "gns_upstream" (acOptions cfg))
  }

adapterConfigToDarknetConfig :: AdapterConfig -> DarknetConfig
adapterConfigToDarknetConfig cfg = DarknetConfig
  { dcDn42Upstream = fromMaybe ["172.20.0.53", "172.23.0.53"] (readMaybe =<< HM.lookup "dn42_upstream" (acOptions cfg))
  , dcAnoNetUpstream = acUpstream cfg
  }

adapterConfigToFilterConfig :: AdapterConfig -> FilterConfig
adapterConfigToFilterConfig cfg = FilterConfig
  { fcEnabled = acEnabled cfg
  , fcZones = acZones cfg
  , fcMode = acMode cfg
  }

readMaybe :: String -> Maybe [String]
readMaybe s = case reads s of
  [(xs, "")] -> Just xs
  _          -> Nothing

import Control.Concurrent (forkIO)
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
