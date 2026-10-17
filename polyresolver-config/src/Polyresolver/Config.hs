{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Config
  ( Config(..)
  , AdapterConfig(..)
  , DNSConfig(..)
  , APIConfig(..)
  , MetricsConfig(..)
  , loadConfig
  , defaultConfig
  , validateConfig
  ) where

import Control.Exception (try, SomeException)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Yaml (decodeFileEither, FromJSON(..), (.:), (.:?), (.!=))
import qualified Data.Yaml as Y

import Polyresolver.Types.Adapters (AdapterId(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data AdapterConfig = AdapterConfig
  { acName     :: !Text
  , acEnabled  :: !Bool
  , acConfig   :: !Y.Value
  } deriving stock (Eq, Show)

data DNSConfig = DNSConfig
  { dcAddress :: !Text
  , dcPort    :: !Int
  } deriving stock (Eq, Show)

data APIConfig = APIConfig
  { acAddress :: !Text
  , acPort    :: !Int
  } deriving stock (Eq, Show)

data MetricsConfig = MetricsConfig
  { mcEnabled :: !Bool
  , mcAddress :: !Text
  , mcPort    :: !Int
  } deriving stock (Eq, Show)

data Config = Config
  { cAdapters :: ![AdapterConfig]
  , cDNS      :: !(Maybe DNSConfig)
  , cAPI      :: !(Maybe APIConfig)
  , cMetrics  :: !(Maybe MetricsConfig)
  } deriving stock (Eq, Show)

instance FromJSON AdapterConfig where
  parseJSON = Y.withObject "AdapterConfig" $ \o -> AdapterConfig
    <$> o .: "name"
    <*> o .:? "enabled" .!= True
    <*> o .: "config"

instance FromJSON Config where
  parseJSON = Y.withObject "Config" $ \o -> Config
    <$> o .:? "adapters" .!= []
    <*> o .:? "dns"
    <*> o .:? "api"
    <*> o .:? "metrics"

instance FromJSON DNSConfig where
  parseJSON = Y.withObject "DNSConfig" $ \o -> DNSConfig
    <$> o .:? "address" .!= "127.0.0.1"
    <*> o .:? "port" .!= 5300

instance FromJSON APIConfig where
  parseJSON = Y.withObject "APIConfig" $ \o -> APIConfig
    <$> o .:? "address" .!= "127.0.0.1"
    <*> o .:? "port" .!= 8080

instance FromJSON MetricsConfig where
  parseJSON = Y.withObject "MetricsConfig" $ \o -> MetricsConfig
    <$> o .:? "enabled" .!= True
    <*> o .:? "address" .!= "127.0.0.1"
    <*> o .:? "port" .!= 9153

loadConfig :: FilePath -> IO (Either String Config)
loadConfig path = do
  result <- decodeFileEither path
  case result of
    Left err -> pure (Left (show err))
    Right cfg -> pure (Right cfg)

defaultConfig :: Config
defaultConfig = Config
  { cAdapters = []
  , cDNS = Just (DNSConfig "127.0.0.1" 5300)
  , cAPI = Just (APIConfig "127.0.0.1" 8080)
  , cMetrics = Just (MetricsConfig True "127.0.0.1" 9153)
  }

validateConfig :: Config -> Either String Config
validateConfig cfg = Right cfg
