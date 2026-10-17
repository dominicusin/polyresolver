{-# LANGUAGE DeriveGeneric #-}

module Polyresolver.Config.Schema
  ( Config(..)
  , ListenerConfig(..)
  , APIConfig(..)
  , EdgeConfig(..)
  , ViewConfig(..)
  , RoutingConfig(..)
  , CacheConfig(..)
  , MetricsConfig(..)
  , LoggingConfig(..)
  , SecretsConfig(..)
  , AdapterConfig(..)
  , defaultConfig
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Data.Aeson (FromJSON, ToJSON)
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Scientific (Scientific)
import Data.Vector (Vector)

data Config = Config
  { cfgListeners :: ![ListenerConfig]
  , cfgAPI       :: !APIConfig
  , cfgEdge      :: !(Maybe EdgeConfig)
  , cfgViews     :: !(HashMap Text ViewConfig)
  , cfgRouting   :: !RoutingConfig
  , cfgCache     :: !CacheConfig
  , cfgAdapters  :: !(HashMap Text AdapterConfig)
  , cfgMetrics   :: !MetricsConfig
  , cfgLogging   :: !LoggingConfig
  , cfgSecrets   :: !(Maybe SecretsConfig)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data ListenerConfig = ListenerConfig
  { lcTransport :: !Text
  , lcAddress   :: !Text
  , lcPort      :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data APIConfig = APIConfig
  { apiAddress :: !Text
  , apiPort    :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data EdgeConfig = EdgeConfig
  { ecEnabled       :: !Bool
  , ecPublicBinds   :: ![ListenerConfig]
  , ecACL           :: ![Text]
  , ecRateLimitQPS  :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data ViewConfig = ViewConfig
  { vcACL               :: ![Text]
  , vcNativeRootAdapters :: ![Text]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data RoutingConfig = RoutingConfig
  { rcConflictPolicy :: !Text
  , rcConflicts      :: !(Vector Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data CacheConfig = CacheConfig
  { ccShards        :: !Int
  , ccMaxEntries    :: !Int
  , ccDefaultTTL    :: !Int
  , ccMinTTL        :: !Int
  , ccMaxTTL        :: !Int
  , ccNegativeTTL   :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data MetricsConfig = MetricsConfig
  { mcEnabled  :: !Bool
  , mcAddress  :: !Text
  , mcPort     :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data LoggingConfig = LoggingConfig
  { logFormat :: !Text
  , logLevel  :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data SecretsConfig = SecretsConfig
  { scEthRPCKeyFile :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data AdapterConfig = AdapterConfig
  { acEnabled  :: !Bool
  , acMode     :: !Text
  , acUpstream :: !(Maybe Text)
  , acZones    :: ![Text]
  , acPriority :: !Int
  , acTimeoutMs :: !Int
  , acOptions  :: !(HashMap Text Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

defaultConfig :: Config
defaultConfig = Config
  { cfgListeners = [ ListenerConfig "udp" "127.0.0.1" 5300
                   , ListenerConfig "tcp" "127.0.0.1" 5300
                   ]
  , cfgAPI = APIConfig "127.0.0.1" 8080
  , cfgEdge = Nothing
  , cfgViews = HM.fromList [("default", ViewConfig ["0.0.0.0/0"] [])]
  , cfgRouting = RoutingConfig "explicit" []
  , cfgCache = CacheConfig 64 2000000 300 5 86400 30
  , cfgAdapters = HM.empty
  , cfgMetrics = MetricsConfig True "127.0.0.1" 9153
  , cfgLogging = LoggingConfig "json" "info"
  , cfgSecrets = Nothing
  }
