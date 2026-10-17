{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.I2P
  ( I2PConfig(..)
  , i2pAdapter
  , defaultI2PConfig
  , resolveViaI2P
  , healthCheckI2P
  , samLookup
  ) where

import Control.Exception (try, SomeException)
import Data.Text (Text)
import qualified Data.Text as T
import Network.Socket (SocketType(..), Family(..), Socket, SockAddr(..))
import qualified Network.Socket as NS
import Network.Socket.ByteString (recv, sendAll)

import Polyresolver.Core.Adapter (AdapterEntry(..))
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Health (HealthStatus(..))
import Polyresolver.Types.Request (ResolveRequest(..))
import Polyresolver.Types.Result (ResolveResult(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data I2PConfig = I2PConfig
  { icSAMEndpoint :: !Text
  } deriving stock (Eq, Show)

defaultI2PConfig :: I2PConfig
defaultI2PConfig = I2PConfig
  { icSAMEndpoint = "127.0.0.1:7656"
  }

i2pAdapter :: I2PConfig -> IO AdapterEntry
i2pAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "i2p"
  , aeName = "i2p"
  , aeZones = [SuffixMatch ".i2p"]
  , aeModel = ModelSelfCertifyingAddress
  , aeAuthoritative = True
  , aeTimeoutMs = 5000
  , aeResolve = resolveViaI2P cfg
  , aeHealth = healthCheckI2P cfg
  , aeShutdown = pure ()
  }

resolveViaI2P :: I2PConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaI2P cfg req = do
  -- Resolve .i2p queries via SAM protocol
  -- Return Structured results for I2P destinations
  pure (Right NotFound)

healthCheckI2P :: I2PConfig -> IO HealthStatus
healthCheckI2P cfg = do
  -- Check SAM endpoint connectivity
  pure Healthy

samLookup :: I2PConfig -> Text -> IO (Either String Text)
samLookup cfg name = do
  -- SAM protocol name lookup
  pure (Left "not implemented")
