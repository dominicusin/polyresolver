{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.PluginSDK.Client
  ( PluginClient
  , connectPlugin
  , disconnectPlugin
  , sendRequest
  , recvResponse
  , pingPlugin
  ) where

import Control.Exception (bracket, try, SomeException)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, writeTVar)
import Data.Text (Text)
import Network.Socket (Socket)
import qualified Network.Socket as NS

import Polyresolver.PluginSDK.ABI
import Polyresolver.PluginSDK.IPC

data PluginClient = PluginClient
  { pcSocket  :: !Socket
  , pcInfo    :: !PluginInfo
  , pcRunning :: !(TVar Bool)
  }

connectPlugin :: FilePath -> IO (Either String PluginClient)
connectPlugin sockPath = do
  result <- try $ do
    sock <- NS.socket NS.AF_UNIX NS.Stream 0
    NS.connect sock (NS.SockAddrUnix sockPath)
    sendIPCMessage sock (IPCPluginInfo PluginInfo
      { piName = "polyresolver-plugin"
      , piVersion = "0.1.0.0"
      , piABIVersion = 1
      , piCapabilities = PluginCapabilities
        { pcStreamingResults = False
        , pcAsyncCancel = False
        , pcPartialResults = False
        }
      })
    response <- recvIPCMessage sock
    case response of
      Right (IPCPluginInfo info) -> do
        running <- newTVarIO True
        pure (Right (PluginClient sock info running))
      Right (IPCPluginError err) -> pure (Left (show err))
      _ -> pure (Left "unexpected response")
  case result of
    Left err -> pure (Left (show (err :: SomeException)))
    Right (Left errMsg) -> pure (Left errMsg)
    Right (Right client) -> pure (Right client)

disconnectPlugin :: PluginClient -> IO ()
disconnectPlugin client = do
  sendIPCMessage (pcSocket client) IPCPong
  NS.close (pcSocket client)
  atomically $ writeTVar (pcRunning client) False

sendRequest :: PluginClient -> PluginRequest -> IO (Either String PluginResponse)
sendRequest client req = do
  result <- try $ do
    sendIPCMessage (pcSocket client) (IPCRequest req)
    recvIPCMessage (pcSocket client)
  case result of
    Left err -> pure (Left (show (err :: SomeException)))
    Right (Left err) -> pure (Left err)
    Right (Right (IPCResponse resp)) -> pure (Right resp)
    Right (Right _) -> pure (Left "unexpected response")

pingPlugin :: PluginClient -> IO (Either String ())
pingPlugin client = do
  result <- try $ do
    sendIPCMessage (pcSocket client) IPCPing
    recvIPCMessage (pcSocket client)
  case result of
    Left err -> pure (Left (show (err :: SomeException)))
    Right (Left err) -> pure (Left err)
    Right (Right IPCPong) -> pure (Right ())
    Right (Right _) -> pure (Left "unexpected response")

recvResponse :: Socket -> IO (Either String IPCMessage)
recvResponse sock = recvIPCMessage sock
