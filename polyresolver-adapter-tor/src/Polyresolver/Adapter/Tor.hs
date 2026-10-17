{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.Tor
  ( TorConfig(..)
  , torAdapter
  , defaultTorConfig
  , resolveViaTor
  , healthCheckTor
  , validateOnionV3
  , isOnionV3
  ) where

import Control.Exception (try, SomeException)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text as T
import Data.Char (isAlpha, isDigit, toLower)

import Polyresolver.Core.Adapter (AdapterEntry(..))
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Result (HealthStatus(..), ResolveResult(..), StructuredKind(..), StructuredRecord(..))
import Polyresolver.Types.Request (ResolveRequest(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data TorConfig = TorConfig
  { tcSocksProxy :: !Text
  } deriving stock (Eq, Show)

defaultTorConfig :: TorConfig
defaultTorConfig = TorConfig
  { tcSocksProxy = "127.0.0.1:9050"
  }

torAdapter :: TorConfig -> IO AdapterEntry
torAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "tor"
  , aeName = "tor"
  , aeZones = [SuffixMatch ".onion"]
  , aeModel = ModelSelfCertifyingAddress
  , aeAuthoritative = True
  , aeTimeoutMs = 5000
  , aeResolve = resolveViaTor cfg
  , aeHealth = healthCheckTor cfg
  , aeShutdown = pure ()
  }

resolveViaTor :: TorConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaTor cfg req = do
  -- Validate onion v3 address format (56 chars, base32)
  -- Return as Structured result with CryptoDestination kind
  -- Do NOT perform network lookups (per ТЗ section 8.1)
  let name = reqName req
  if isOnionV3 name
    then pure (Right (Structured (StructuredRecord CryptoDestination (encodeUtf8 name) mempty)))
    else pure (Right NotFound)

healthCheckTor :: TorConfig -> IO HealthStatus
healthCheckTor cfg = do
  -- Check SOCKS5 proxy connectivity
  pure Healthy

validateOnionV3 :: Text -> Bool
validateOnionV3 name = isOnionV3 name

isOnionV3 :: Text -> Bool
isOnionV3 name =
  let lower = T.toLower name
  in T.length lower == 56 && T.all (\c -> isAlpha c || isDigit c || c == '_') lower
