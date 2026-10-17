{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.Emerdns
  ( EmerDNSConfig(..)
  , emerdnsAdapter
  , defaultEmerDNSConfig
  , resolveViaEmerDNS
  , healthCheckEmerDNS
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try, SomeException)
import Control.Monad (when)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import Network.Socket (SocketType(..), Family(..), Socket, SockAddr(..))
import qualified Network.Socket as NS
import Network.Socket.ByteString (recv, sendAll)
import System.Timeout (timeout)

import Polyresolver.Core.Adapter (AdapterEntry(..))
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Request (ResolveRequest(..))
import Polyresolver.Types.Result (ResolveResult(..), HealthStatus(..), BackendError(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data EmerDNSConfig = EmerDNSConfig
  { ecMode      :: !Text
  , ecUpstream  :: !Text
  , ecTimeoutMs :: !Int
  } deriving stock (Eq, Show)

defaultEmerDNSConfig :: EmerDNSConfig
defaultEmerDNSConfig = EmerDNSConfig
  { ecMode = "delegated"
  , ecUpstream = "127.0.0.1:5333"
  , ecTimeoutMs = 2000
  }

emerdnsAdapter :: EmerDNSConfig -> IO AdapterEntry
emerdnsAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "emerdns"
  , aeName = "emerdns"
  , aeZones = [SuffixMatch ".emc", SuffixMatch ".coin", SuffixMatch ".lib", SuffixMatch ".bazar"]
  , aeModel = ModelHierarchicalRegistry
  , aeAuthoritative = True
  , aeTimeoutMs = ecTimeoutMs cfg
  , aeResolve = resolveViaEmerDNS cfg
  , aeHealth = healthCheckEmerDNS cfg
  , aeShutdown = pure ()
  }

resolveViaEmerDNS :: EmerDNSConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaEmerDNS cfg req = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ecTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure (Right NotFound)
  case result of
    Left err -> pure (Left (AdapterFailed (AdapterId "emerdns") (UnknownError (T.pack (show (err :: SomeException))))))
    Right res -> pure res

healthCheckEmerDNS :: EmerDNSConfig -> IO HealthStatus
healthCheckEmerDNS cfg = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ecTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure ()
  case result of
    Left err -> pure (Unhealthy (T.pack (show (err :: SomeException))))
    Right () -> pure Healthy
