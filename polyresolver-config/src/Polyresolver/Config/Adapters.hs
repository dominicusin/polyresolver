{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, LambdaCase, DerivingStrategies, RecordWildCards #-}

-- | Load adapters from configuration (Phase 0.2).
--
-- This module bridges the YAML configuration to concrete adapter
-- implementations. Each adapter is loaded by name from the config,
-- and its specific configuration section is parsed and passed to
-- the adapter constructor.
module Polyresolver.Config.Adapters
  ( loadAdapters
  , loadUnboundAdapter
  ) where

import Control.Exception (try, SomeException)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Yaml (FromJSON(..), (.:), (.:?), (.!=), parseEither)
import qualified Data.Yaml as Y

import Polyresolver.Adapter.Unbound (UnboundConfig(..), unboundAdapter)
import Polyresolver.Config (AdapterConfig(..))
import Polyresolver.Core.Adapter (AdapterEntry)
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

-- | Load all enabled adapters from configuration.
loadAdapters :: [AdapterConfig] -> IO [(Int, AdapterEntry)]
loadAdapters configs = do
  results <- mapM loadAdapter configs
  pure [ (10, entry) | (True, entry) <- results ]

-- | Load a single adapter from its configuration.
loadAdapter :: AdapterConfig -> IO (Bool, AdapterEntry)
loadAdapter cfg = do
  if not (acEnabled cfg)
    then pure (False, undefined)
    else case acName cfg of
      "unbound" -> do
        let uc = parseUnboundConfig (acConfig cfg)
        entry <- unboundAdapter uc
        pure (True, entry)
      _ -> pure (False, undefined)

-- | Parse Unbound-specific configuration.
parseUnboundConfig :: Y.Value -> UnboundConfig
parseUnboundConfig val = case parseEither parseJSON val of
  Left _ -> UnboundConfig "127.0.0.1" 5335 2000
  Right cfg -> cfg

instance FromJSON UnboundConfig where
  parseJSON = Y.withObject "UnboundConfig" $ \o -> UnboundConfig
    <$> o .:? "host" .!= "127.0.0.1"
    <*> o .:? "port" .!= 5335
    <*> o .:? "timeout_ms" .!= 2000

-- | Load only the Unbound adapter (convenience).
loadUnboundAdapter :: AdapterConfig -> IO (Maybe AdapterEntry)
loadUnboundAdapter cfg = do
  if acName cfg /= "unbound" || not (acEnabled cfg)
    then pure Nothing
    else do
      let uc = parseUnboundConfig (acConfig cfg)
      entry <- unboundAdapter uc
      pure (Just entry)
