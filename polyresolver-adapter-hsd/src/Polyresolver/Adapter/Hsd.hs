{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Adapter.Hsd
  ( HSDConfig(..)
  , hsdAdapter
  , defaultHSDConfig
  , resolveViaHSD
  , healthCheckHSD
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

data HSDConfig = HSDConfig
  { hcMode            :: !Text
  , hcUpstream        :: !Text
  , hcTimeoutMs       :: !Int
  , hcNativeRootView  :: !(Maybe Text)
  } deriving stock (Eq, Show)

defaultHSDConfig :: HSDConfig
defaultHSDConfig = HSDConfig
  { hcMode = "delegated"
  , hcUpstream = "127.0.0.1:5350"
  , hcTimeoutMs = 2000
  , hcNativeRootView = Nothing
  }

hsdAdapter :: HSDConfig -> IO AdapterEntry
hsdAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "hsd"
  , aeName = "hsd"
  , aeZones = [SuffixMatch ".hns"]
  , aeModel = ModelHierarchicalRegistry
  , aeAuthoritative = True
  , aeTimeoutMs = hcTimeoutMs cfg
  , aeResolve = resolveViaHSD cfg
  , aeHealth = healthCheckHSD cfg
  , aeShutdown = pure ()
  }

resolveViaHSD :: HSDConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaHSD cfg req = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (hcTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure (Right NotFound)
  case result of
    Left err -> pure (Left (AdapterFailed (AdapterId "hsd") (UnknownError (T.pack (show (err :: SomeException))))))
    Right res -> pure res

healthCheckHSD :: HSDConfig -> IO HealthStatus
healthCheckHSD cfg = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (hcTimeoutMs cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    sendAll sock (BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    _ <- recv sock 4096
    NS.close sock
    pure ()
  case result of
    Left err -> pure (Unhealthy (T.pack (show (err :: SomeException))))
    Right () -> pure Healthy
