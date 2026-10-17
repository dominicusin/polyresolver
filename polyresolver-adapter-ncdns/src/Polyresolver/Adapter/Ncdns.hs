{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.Ncdns
  ( NcdnsConfig(..)
  , ncdnsAdapter
  , defaultNcdnsConfig
  , resolveViaNcdns
  , healthCheckNcdns
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

data NcdnsConfig = NcdnsConfig
  { ncMode      :: !Text
  , ncUpstream  :: !Text
  , ncTimeoutMs :: !Int
  } deriving stock (Eq, Show)

defaultNcdnsConfig :: NcdnsConfig
defaultNcdnsConfig = NcdnsConfig
  { ncMode = "delegated"
  , ncUpstream = "127.0.0.1:5333"
  , ncTimeoutMs = 2000
  }

ncdnsAdapter :: NcdnsConfig -> IO AdapterEntry
ncdnsAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "ncdns"
  , aeName = "ncdns"
  , aeZones = [SuffixMatch ".bit"]
  , aeModel = ModelHierarchicalRegistry
  , aeAuthoritative = True
  , aeTimeoutMs = ncTimeoutMs cfg
  , aeResolve = resolveViaNcdns cfg
  , aeHealth = healthCheckNcdns cfg
  , aeShutdown = pure ()
  }

resolveViaNcdns :: NcdnsConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaNcdns cfg req = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ncTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure (Right NotFound)
  case result of
    Left err -> pure (Left (AdapterFailed (AdapterId "ncdns") (UnknownError (T.pack (show (err :: SomeException))))))
    Right res -> pure res

healthCheckNcdns :: NcdnsConfig -> IO HealthStatus
healthCheckNcdns cfg = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ncTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure ()
  case result of
    Left err -> pure (Unhealthy (T.pack (show (err :: SomeException))))
    Right () -> pure Healthy
