{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.PluginSDK.IPC
  ( IPCMessage(..)
  , encodeIPCMessage
  , decodeIPCMessage
  , sendIPCMessage
  , recvIPCMessage
  ) where

import Control.Exception (try, SomeException)
import Data.Binary (Binary, encode, decode)
import qualified Data.Binary as Binary
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.Text (Text)
import Network.Socket (Socket)
import qualified Network.Socket as NS
import Network.Socket.ByteString (recv, sendAll)

import Polyresolver.PluginSDK.ABI

data IPCMessage
  = IPCRequest PluginRequest
  | IPCResponse PluginResponse
  | IPCPluginInfo PluginInfo
  | IPCPluginError PluginError
  | IPCPing
  | IPCPong
  deriving stock (Eq, Show, Generic)
    deriving anyclass (Binary)

encodeIPCMessage :: IPCMessage -> ByteString
encodeIPCMessage = BSL.toStrict . Binary.encode

decodeIPCMessage :: ByteString -> Either String IPCMessage
decodeIPCMessage bs = case Binary.decodeOrFail (BSL.fromStrict bs) of
  Left (_, _, err) -> Left err
  Right (_, _, msg) -> Right msg

sendIPCMessage :: Socket -> IPCMessage -> IO ()
sendIPCMessage sock msg = do
  let bs = encodeIPCMessage msg
  let len = BS.length bs
  sendAll sock (encode len)
  sendAll sock bs

recvIPCMessage :: Socket -> IO (Either String IPCMessage)
recvIPCMessage sock = do
  lenBs <- recv sock 4
  if BS.length lenBs < 4
    then pure (Left "connection closed")
    else do
      let len = Binary.decode (BSL.fromStrict lenBs) :: Int
      msgBs <- recv sock len
      if BS.length msgBs < len
        then pure (Left "incomplete message")
        else pure (decodeIPCMessage msgBs)
