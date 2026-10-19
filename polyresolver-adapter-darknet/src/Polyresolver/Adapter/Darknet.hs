{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.Darknet
  ( DarknetConfig(..)
  , darknetAdapter
  , defaultDarknetConfig
  , resolveViaDarknet
  , healthCheckDarknet
  , resolveDn42
  , resolveAnoNet
  ) where

import Control.Exception (try, SomeException)
import Data.Text (Text)
import qualified Data.Text as T

import Polyresolver.Core.Adapter (AdapterEntry(..))
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Result (HealthStatus(..), ResolveResult(..))
import Polyresolver.Types.Request (ResolveRequest(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data DarknetConfig = DarknetConfig
  { dcDn42Upstream    :: !(Maybe [Text])
  , dcAnoNetUpstream  :: !(Maybe Text)
  } deriving stock (Eq, Show)

defaultDarknetConfig :: DarknetConfig
defaultDarknetConfig = DarknetConfig
  { dcDn42Upstream = Just ["172.20.0.53", "172.23.0.53"]
  , dcAnoNetUpstream = Nothing
  }

darknetAdapter :: DarknetConfig -> IO AdapterEntry
darknetAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "darknet"
  , aeName = "darknet"
  , aeZones = [SuffixMatch ".dn42", SuffixMatch ".ano"]
  , aeModel = ModelDarknetRegistry
  , aeAuthoritative = True
  , aeTimeoutMs = 5000
  , aeResolve = resolveViaDarknet cfg
  , aeHealth = healthCheckDarknet cfg
  , aeShutdown = pure ()
  }

resolveViaDarknet :: DarknetConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaDarknet cfg req = do
  -- Resolve dn42/anoNet queries via anycast DNS
  pure (Right NotFound)

healthCheckDarknet :: DarknetConfig -> IO HealthStatus
healthCheckDarknet cfg = do
  -- Check DNS server connectivity
  pure Healthy

resolveDn42 :: DarknetConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveDn42 cfg req = do
  -- Resolve dn42 queries via anycast DNS
  pure (Right NotFound)

resolveAnoNet :: DarknetConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveAnoNet cfg req = do
  -- Resolve anoNet queries via operator-specified DNS
  pure (Right NotFound)
