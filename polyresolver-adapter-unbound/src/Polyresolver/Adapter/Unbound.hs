{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.Unbound
  ( UnboundConfig(..)
  , unboundAdapter
  , defaultUnboundConfig
  , resolveViaUnbound
  , healthCheckUnbound
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

data UnboundConfig = UnboundConfig
  { ucUpstream  :: !Text
  , ucTimeoutMs  :: !Int
  } deriving stock (Eq, Show)

defaultUnboundConfig :: UnboundConfig
defaultUnboundConfig = UnboundConfig
  { ucUpstream = "127.0.0.1:5335"
  , ucTimeoutMs = 2000
  }

unboundAdapter :: UnboundConfig -> IO AdapterEntry
unboundAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "unbound"
  , aeName = "unbound"
  , aeZones = [SuffixMatch "*"]
  , aeModel = ModelHierarchicalRegistry
  , aeAuthoritative = False
  , aeTimeoutMs = ucTimeoutMs cfg
  , aeResolve = resolveViaUnbound cfg
  , aeHealth = healthCheckUnbound cfg
  , aeShutdown = pure ()
  }

resolveViaUnbound :: UnboundConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaUnbound cfg req = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ucTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    msg <- recv sock 4096
    NS.close sock
    pure (Right NotFound)
  case result of
    Left err -> pure (Left (AdapterFailed (AdapterId "unbound") (UnknownError (T.pack (show (err :: SomeException))))))
    Right res -> pure res

healthCheckUnbound :: UnboundConfig -> IO HealthStatus
healthCheckUnbound cfg = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ucTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure ()
  case result of
    Left err -> pure (Unhealthy (T.pack (show (err :: SomeException))))
    Right () -> pure Healthy
