{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.PluginSDK.Server
  ( PluginServer
  , startPluginServer
  , stopPluginServer
  , acceptPlugin
  , ResolveError(..)
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Control.Exception (bracket, try, SomeException)
import Control.Monad (forever, when)
import Data.Text (Text)
import Network.Socket (Socket)
import qualified Network.Socket as NS
import System.Directory (removeFile)

import Polyresolver.Types.Errors (ResolveError (..))
import Polyresolver.PluginSDK.ABI
import Polyresolver.PluginSDK.IPC

data PluginServer = PluginServer
  { psSocket  :: !Socket
  , psPath    :: !FilePath
  , psRunning :: !(TVar Bool)
  }

startPluginServer :: FilePath -> PluginInfo -> IO (Either String PluginServer)
startPluginServer sockPath info = do
  result <- try $ do
    sock <- NS.socket NS.AF_UNIX NS.Stream 0
    NS.setSocketOption sock NS.ReuseAddr 1
    NS.bind sock (NS.SockAddrUnix sockPath)
    NS.listen sock 5
    running <- newTVarIO True
    let server = PluginServer sock sockPath running
    _ <- forkIO $ acceptLoop server info
    pure server
  case result of
    Left err -> pure (Left (show (err :: SomeException)))
    Right res -> pure (Right res)

stopPluginServer :: PluginServer -> IO ()
stopPluginServer server = do
  atomically $ writeTVar (psRunning server) False
  NS.close (psSocket server)
  removeFile (psPath server)

acceptLoop :: PluginServer -> PluginInfo -> IO ()
acceptLoop server info = forever $ do
  running <- atomically $ readTVar (psRunning server)
  when running $ do
    (sock, _) <- NS.accept (psSocket server)
    _ <- forkIO $ handleClient sock info
    pure ()

handleClient :: Socket -> PluginInfo -> IO ()
handleClient sock info = do
  sendIPCMessage sock (IPCPluginInfo info)
  msg <- recvIPCMessage sock
  case msg of
    Right IPCPing -> sendIPCMessage sock IPCPong
    Right (IPCRequest req) -> do
      -- Plugin-specific resolution logic goes here
      sendIPCMessage sock (IPCResponse (PluginResponse (Left (InvalidRequest "not implemented"))))
    _ -> sendIPCMessage sock (IPCPluginError (PluginInitError "bad request"))

acceptPlugin :: PluginServer -> IO (Either String Socket)
acceptPlugin server = do
  result <- try $ do
    (sock, _) <- NS.accept (psSocket server)
    pure sock
  case result of
    Left err -> pure (Left (show (err :: SomeException)))
    Right res -> pure (Right res)
