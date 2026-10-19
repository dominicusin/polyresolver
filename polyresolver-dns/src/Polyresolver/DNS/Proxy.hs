{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, LambdaCase, DerivingStrategies, RecordWildCards, NumericUnderscores, BinaryLiterals, TypeApplications, AllowAmbiguousTypes, GADTs, FlexibleInstances, TypeSynonymInstances, StandaloneDeriving #-}

module Polyresolver.DNS.Proxy
  ( DelegatedZone(..)
  , delegatedZones
  , proxyDNSQuery
  , extractQueryName
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Word (Word16, Word8)
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.List (find)

import Network.Socket (SockAddr)
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB

import Control.Exception (try, SomeException)

import Polyresolver.Types.Namespace (ZonePattern(..))
import Polyresolver.DNS.Codec (DNSHeader(..), decodeHeader)

-- | A zone that is delegated to a backend (e.g., Unbound for ICANN).
data DelegatedZone = DelegatedZone
  { dzName  :: !Text       -- ^ Zone suffix, e.g. "unbound"
  , dzZone  :: !ZonePattern -- ^ Pattern that matches names in this zone
  , dzHost  :: !Text       -- ^ Backend host
  , dzPort  :: !Int        -- ^ Backend port
  , dzProto :: !Text       -- ^ "udp" or "tcp"
  } deriving stock (Eq, Show)

-- | Default delegated zones.
delegatedZones :: [DelegatedZone]
delegatedZones =
  [ DelegatedZone "unbound" (SuffixMatch "*") "127.0.0.1" 5335 "udp"
  , DelegatedZone "ncdns"   (SuffixMatch ".bit") "127.0.0.1" 5333 "udp"
  , DelegatedZone "emerdns" (SuffixMatch ".emc") "127.0.0.1" 5333 "udp"
  , DelegatedZone "emerdns" (SuffixMatch ".coin") "127.0.0.1" 5333 "udp"
  , DelegatedZone "emerdns" (SuffixMatch ".lib") "127.0.0.1" 5333 "udp"
  , DelegatedZone "emerdns" (SuffixMatch ".bazar") "127.0.0.1" 5333 "udp"
  , DelegatedZone "hsd"     (SuffixMatch ".hns") "127.0.0.1" 5350 "udp"
  , DelegatedZone "hsd"     (SuffixMatch ".hns") "127.0.0.1" 5349 "udp"
  ]

-- | Extract the query name from a raw DNS packet (question section).
extractQueryName :: ByteString -> Either Text Text
extractQueryName bs
  | BS.length bs < 12 = Left (pack "DNS message too short")
  | otherwise = parseName 12 bs

-- | Parse a DNS name from wire format starting at offset.
parseName :: Int -> ByteString -> Either Text Text
parseName offset bs
  | offset >= BS.length bs = Left (pack "truncated DNS name")
  | otherwise = do
      len <- if offset < BS.length bs
             then Right (fromIntegral (BS.index bs offset) :: Word8)
             else Left (pack "truncated DNS name")
      if len == 0
        then Right ""
        else do
          rest <- parseName (offset + 1 + fromIntegral len) bs
          let label = BS.take (fromIntegral len) (BS.drop (offset + 1) bs)
          let labelText = bytesToText label
          if T.null rest
            then Right labelText
            else Right (labelText <> "." <> rest)

-- | Convert bytes to text (naive UTF-8 decoding).
bytesToText :: ByteString -> Text
bytesToText = pack . map (toEnum . fromIntegral) . BS.unpack

-- | Check if a DNS query should be proxied to a delegated backend.
proxyDNSQuery :: [DelegatedZone] -> ByteString -> Maybe (Text, Int)
proxyDNSQuery zones bs = do
  name <- either (const Nothing) Just (extractQueryName bs)
  let zone = find (\z -> matchesZone (dzZone z) name) zones
  fmap (\z -> (dzHost z, dzPort z)) zone

-- | Check if a name matches a zone pattern.
matchesZone :: ZonePattern -> Text -> Bool
matchesZone (SuffixMatch s) n = T.isSuffixOf s n
matchesZone (ExactMatch s) n = s == n
matchesZone (PredicateMatch _) _ = False

-- | Proxy a DNS query to a backend via UDP.
proxyUDP :: Text -> Int -> ByteString -> IO (Either Text ByteString)
proxyUDP host port query = do
  let addr = NS.SockAddrInet (fromIntegral port) (NS.tupleToHostAddress (127, 0, 0, 1))
  result <- try $ do
    sock <- NS.socket NS.AF_INET NS.Datagram 0
    NS.connect sock addr
    NSB.sendAll sock query
    response <- NSB.recv sock 4096
    NS.close sock
    pure (Right response)
  case result of
    Left err -> pure (Left (pack (show (err :: SomeException))))
    Right (Left err) -> pure (Left (pack err))
    Right (Right response) -> pure (Right response)