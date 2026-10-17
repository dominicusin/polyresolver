{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.DNS
  ( DNSConfig(..)
  , defaultDNSConfig
  , runDNSServer
  , handleDNSQuery
  , encodeDNSMessage
  , decodeDNSMessage
  ) where

import Control.Concurrent (forkIO)
import Control.Exception (try, SomeException)
import Control.Monad (forever, void)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import Network.Socket (SocketType(..), Family(..), Socket, SockAddr(..))
import qualified Network.Socket as NS
import Network.Socket.ByteString (recvFrom, sendAll, sendTo)

import Polyresolver.Core.Engine (Engine, resolve)
import Polyresolver.Types.Request (ResolveRequest(..), newResolveRequest)
import Polyresolver.Types.ClientContext (ClientContext(..))
import Polyresolver.Types.QType (QType(..))
import Polyresolver.Types.Graph (ResolutionGraph(..))
import Polyresolver.Types.Result (ResolveResult(..))
import Polyresolver.Types.Errors (ResolveError(..))

data DNSConfig = DNSConfig
  { dcAddress :: !Text
  , dcPort    :: !Int
  } deriving stock (Eq, Show)

defaultDNSConfig :: DNSConfig
defaultDNSConfig = DNSConfig
  { dcAddress = "127.0.0.1"
  , dcPort = 5300
  }

runDNSServer :: Engine -> DNSConfig -> IO ()
runDNSServer engine config = do
  sock <- NS.socket AF_INET Datagram 0
  NS.setSocketOption sock NS.ReuseAddr 1
  NS.bind sock (NS.SockAddrInet (fromIntegral (dcPort config)) (NS.tupleToHostAddress (127, 0, 0, 1)))
  forever $ do
    (msg, peerAddr) <- recvFrom sock 4096
    _ <- forkIO $ do
      response <- handleDNSQuery engine msg
      void $ sendTo sock response peerAddr
    pure ()

handleDNSQuery :: Engine -> ByteString -> IO ByteString
handleDNSQuery engine query = do
  -- Decode DNS query, resolve via engine, encode response
  -- For now, return empty response
  pure query

encodeDNSMessage :: ByteString -> ByteString
encodeDNSMessage = id

decodeDNSMessage :: ByteString -> Either String ByteString
decodeDNSMessage = Right
