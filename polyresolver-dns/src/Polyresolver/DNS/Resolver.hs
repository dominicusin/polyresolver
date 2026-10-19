{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, LambdaCase, DerivingStrategies, RecordWildCards, NumericUnderscores, BinaryLiterals, TypeApplications, AllowAmbiguousTypes, GADTs, FlexibleInstances, TypeSynonymInstances, StandaloneDeriving #-}

module Polyresolver.DNS.Resolver
  ( ResolveRequest(..)
  , ResolveResult(..)
  , StructuredRecord(..)
  , DelegateTarget(..)
  , DNSConfig(..)
  , defaultDNSConfig
  , handleDNSQuery
  , encodeDNSMessage
  , decodeDNSMessage
  , DNSMessage(..)
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word8, Word16, Word32)
import Data.Int (Int64)
import Data.Time (NominalDiffTime)
import Network.Socket (SockAddr)
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB
import Control.Concurrent (forkIO)
import Control.Monad (void)
import Control.Exception (bracket, try, SomeException, catch)

import Polyresolver.Core.Engine (Engine, resolve)
import Polyresolver.Types.Adapters (AdapterId(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Result (ResolveResult(..), StructuredRecord(..), DelegateTarget(..))
import Polyresolver.Types.Request (ResolveRequest(..), ClientContext(..))
import Polyresolver.Types.QType (QType(..))
import Polyresolver.Types.Graph (ResolutionGraph(..))
import Polyresolver.Types.Namespace (ZonePattern(..))

data DNSConfig = DNSConfig
  { dcAddress :: !Text
  , dcPort    :: !Int
  } deriving (Eq, Show)

defaultDNSConfig :: DNSConfig
defaultDNSConfig = DNSConfig
  { dcAddress = "127.0.0.1"
  , dcPort    = 5300
  }

handleDNSQuery :: Engine -> DNSMessage -> IO DNSMessage
handleDNSQuery engine msg = do
  -- Decode query, route through engine, encode response
  -- For now, return the message as-is (stub)
  pure msg

encodeDNSMessage :: DNSMessage -> ByteString
encodeDNSMessage (DNSMessage{..}) = BS.pack
  [ fromIntegral (dmId `div` 256), fromIntegral (dmId `mod` 256)
  , fromIntegral (dmFlags `div` 256), fromIntegral (dmFlags `mod` 256)
  , fromIntegral (dmQuestions `div` 256), fromIntegral (dmQuestions `mod` 256)
  , fromIntegral (dmAnswer `div` 256), fromIntegral (dmAnswer `mod` 256)
  , fromIntegral (dmAuthority `div` 256), fromIntegral (dmAuthority `mod` 256)
  , fromIntegral (dmAdditional `div` 256), fromIntegral (dmAdditional `mod` 256)
  ]

decodeDNSMessage :: ByteString -> Either String DNSMessage
decodeDNSMessage bs
  | BS.length bs < 12 = Left "DNS message too short"
  | otherwise = Right $ DNSMessage
      { dmId        = fromIntegral (BS.index bs 0) * 256 + fromIntegral (BS.index bs 1)
      , dmFlags     = fromIntegral (BS.index bs 2) * 256 + fromIntegral (BS.index bs 3)
      , dmQuestions  = fromIntegral (BS.index bs 4) * 256 + fromIntegral (BS.index bs 5)
      , dmAnswer    = fromIntegral (BS.index bs 6) * 256 + fromIntegral (BS.index bs 7)
      , dmAuthority = fromIntegral (BS.index bs 8) * 256 + fromIntegral (BS.index bs 9)
      , dmAdditional = fromIntegral (BS.index bs 10) * 256 + fromIntegral (BS.index bs 11)
      }

data DNSMessage = DNSMessage
  { dmId        :: !Word16
  , dmFlags     :: !Word16
  , dmQuestions :: !Word16
  , dmAnswer    :: !Word16
  , dmAuthority :: !Word16
  , dmAdditional :: !Word16
  } deriving (Eq, Show)

data DNSResourceRecord = DNSResourceRecord
  { rrName     :: !DNSDomain
  , rrType     :: !RQType
  , rrClass    :: !Word16
  , rrTtl      :: !Word32
  , rrRdlength :: !Word16
  , rrRdata    :: !ByteString
  } deriving (Eq, Show)

type DNSDomain = Text
type RQType = Word16