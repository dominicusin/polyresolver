{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, LambdaCase, DerivingStrategies, RecordWildCards, NumericUnderscores, BinaryLiterals, TypeApplications, AllowAmbiguousTypes, GADTs, FlexibleInstances, TypeSynonymInstances, StandaloneDeriving #-}

module Polyresolver.DNS.Server
  ( runDNSServer
  , handleDNSQuery
  , DNSConfig (..)
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (bracket, SomeException, catch, try)
import Control.Monad (forever, void)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Network.Socket (SockAddr, Socket, Family (AF_INET), SocketType (Datagram, Stream), SocketOption (ReuseAddr), SockAddr (SockAddrInet))
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB

import Polyresolver.Core.Engine (Engine)
import Polyresolver.DNS.Resolver (handleDNSQuery, DNSConfig (..))
import Polyresolver.DNS.Codec (DNSMessage, encodeMessage, decodeMessage)
import Polyresolver.DNS.Proxy (delegatedZones, proxyDNSQuery)

runDNSServer :: Engine -> DNSConfig -> IO ()
runDNSServer engine cfg = do
  void $ forkIO $ runUDPServer engine cfg
  void $ forkIO $ runTCPServer engine cfg
  forever $ threadDelay 3600000000

runUDPServer :: Engine -> DNSConfig -> IO ()
runUDPServer engine cfg = do
  let addr = NS.SockAddrInet (fromIntegral (dcPort cfg)) (NS.tupleToHostAddress (127, 0, 0, 1))
  sock <- NS.socket NS.AF_INET NS.Datagram NS.defaultProtocol
  NS.setSocketOption sock NS.ReuseAddr 1
  NS.bind sock addr
  bracket (return sock) NS.close $ \_ -> do
    let loop = do
          (msg, peer) <- NSB.recvFrom sock 4096
          void $ forkIO $ handleUDPSession engine sock msg peer
          loop
    loop

runTCPServer :: Engine -> DNSConfig -> IO ()
runTCPServer engine cfg = do
  let addr = NS.SockAddrInet (fromIntegral (dcPort cfg)) (NS.tupleToHostAddress (127, 0, 0, 1))
  sock <- NS.socket NS.AF_INET NS.Stream NS.defaultProtocol
  NS.bind sock addr
  NS.listen sock 1024
  bracket (return sock) NS.close $ \_ -> do
    let loop = do
          (conn, _) <- NS.accept sock
          void $ forkIO $ handleTCPSession engine conn
          loop
    loop

handleUDPSession :: Engine -> Socket -> ByteString -> SockAddr -> IO ()
handleUDPSession engine sock msg peer = do
  result <- processDNSMessage engine msg `catch` (\(_e :: SomeException) -> return msg)
  void $ (NSB.sendTo sock result peer `catch` (\(_e :: SomeException) -> return 0) :: IO Int)

processDNSMessage :: Engine -> ByteString -> IO ByteString
processDNSMessage engine bs =
  -- Check if this query should be proxied to a delegated backend
  case proxyDNSQuery delegatedZones bs of
    Just (_host, port) -> do
      -- Proxy to delegated backend (e.g., Unbound)
      let backendAddr = NS.SockAddrInet (fromIntegral port) (NS.tupleToHostAddress (127, 0, 0, 1))
      result <- try $ do
        sock <- NS.socket NS.AF_INET NS.Datagram 0
        NS.connect sock backendAddr
        NSB.sendAll sock bs
        response <- NSB.recv sock 4096
        NS.close sock
        pure response
      case result of
        Left (_e :: SomeException) -> return bs
        Right response -> return response
    Nothing -> fallbackToEngine engine bs

fallbackToEngine :: Engine -> ByteString -> IO ByteString
fallbackToEngine engine bs = do
  case decodeMessage bs of
    Left _err -> return bs  -- Return query as-is on decode error
    Right dnsMsg -> do
      response <- handleDNSQuery engine dnsMsg
      return $ encodeMessage response

handleTCPSession :: Engine -> Socket -> IO ()
handleTCPSession engine conn = do
  let loop = do
        chunk <- NSB.recv conn 4096
        if BS.null chunk
          then return ()
          else do
            result <- processDNSMessage engine chunk
            void $ NSB.sendAll conn result `catch` (\(_e :: SomeException) -> return ())
            loop
  loop