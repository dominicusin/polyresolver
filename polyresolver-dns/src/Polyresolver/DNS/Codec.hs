{-# LANGUAGE DerivingStrategies #-}
-- | DNS wire codec for the polyresolver DNS facade.
--
-- This module handles the encoding and decoding of DNS wire-format messages,
-- using only the @dns@ package as a dependency. The wire format follows RFC 1035
-- (and RFC 1034 for the presentation format).
--
-- At this stage, we implement the 12-byte header (RFC 1035, section 4.1.1)
-- and provide stubs for question/RR encoding, to be expanded when the
-- integration with dnsext is ready.
module Polyresolver.DNS.Codec
  ( -- * Header
    encodeHeader
  , decodeHeader
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text, pack)
import Data.Word (Word8, Word16)

data DNSHeader = DNSHeader
  { dhId       :: !Word16
  , dhFlags    :: !Word16
  , dhQdCount  :: !Word16
  , dhAnCount  :: !Word16
  , dhNsCount  :: !Word16
  , dhArCount  :: !Word16
  } deriving stock (Eq, Show)

-- | Encode a 12-byte DNS header (RFC 1035, section 4.1.1).
--
-- All fields are encoded in network byte order (big-endian).
encodeHeader :: DNSHeader -> ByteString
encodeHeader h = BS.concat
  [ be16 (dhId h)
  , be16 (dhFlags h)
  , be16 (dhQdCount h)
  , be16 (dhAnCount h)
  , be16 (dhNsCount h)
  , be16 (dhArCount h)
  ]
  where
    be16 :: Word16 -> ByteString
    be16 w = BS.pack [fromIntegral (w `div` 0x100), fromIntegral (w `mod` 0x100)]

-- | Decode a 12-byte DNS header.
--
-- Returns 'Left' if the input is shorter than 12 bytes.
decodeHeader :: ByteString -> Either Text DNSHeader
decodeHeader bs
  | BS.length bs < 12 = Left (pack "DNS message too short")
  | otherwise = Right $ DNSHeader
      { dhId       = be16To (BS.index bs 0) (BS.index bs 1)
      , dhFlags    = be16To (BS.index bs 2) (BS.index bs 3)
      , dhQdCount  = be16To (BS.index bs 4) (BS.index bs 5)
      , dhAnCount  = be16To (BS.index bs 6) (BS.index bs 7)
      , dhNsCount  = be16To (BS.index bs 8) (BS.index bs 9)
      , dhArCount  = be16To (BS.index bs 10) (BS.index bs 11)
      }
  where
    be16To :: Word8 -> Word8 -> Word16
    be16To hi lo = fromIntegral hi * 0x100 + fromIntegral lo

