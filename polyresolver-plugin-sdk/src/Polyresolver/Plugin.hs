{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Plugin
  ( Plugin(..)
  , PluginConfig(..)
  , loadPlugin
  , withPlugin
  ) where

import Control.Exception (try, SomeException)
import Data.Text (Text)
import qualified Data.Text as T

import Polyresolver.Core.Adapter (AdapterEntry(..))
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Request (ResolveRequest(..))
import Polyresolver.Types.Result (HealthStatus(..), ResolveResult(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data PluginConfig = PluginConfig
  { pcName    :: !Text
  , pcVersion :: !Text
  , pcAuthor  :: !Text
  } deriving stock (Eq, Show)

data Plugin = Plugin
  { pConfig   :: !PluginConfig
  , pAdapter  :: !AdapterEntry
  }

loadPlugin :: PluginConfig -> IO (Either String Plugin)
loadPlugin config = do
  let adapter = AdapterEntry
        { aeId = AdapterId (pcName config)
        , aeName = pcName config
        , aeZones = []
        , aeModel = ModelSelfCertifyingAddress
        , aeAuthoritative = False
        , aeTimeoutMs = 5000
        , aeResolve = \_ -> pure (Right NotFound)
        , aeHealth = pure Healthy
        , aeShutdown = pure ()
        }
  pure (Right (Plugin config adapter))

withPlugin :: Plugin -> (AdapterEntry -> IO a) -> IO a
withPlugin plugin action = action (pAdapter plugin)
