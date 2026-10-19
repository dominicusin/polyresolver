{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, DeriveGeneric, DerivingStrategies #-}

-- | DNS wire codec for polyresolver (RFC 1035).
--
module Polyresolver.DNS.Codec
  ( DNSHeader(..)
  , DNSQuestion(..)
  , DNSResourceRecord(..)
  , DNSMessage(..)
  , encodeMessage
  , decodeMessage
  , encodeHeader
  , decodeHeader
  , encodeQuestion
  , decodeQuestion
  , encodeRR
  , decodeRR
  , encodeName
  , decodeName
  ) where

import Control.Applicative ((<|>))
import Control.Exception (Exception)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List.NonEmpty (NonEmpty(..), nonEmpty, toList)
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import qualified Data.Text.Encoding as TE
import qualified Data.Text as T
import Data.Word (Word8, Word16, Word32)
import Data.Bits (shiftR, (.&.))
import GHC.Generics (Generic)

-- | DNS Header (12 bytes, RFC 1035 section 4.1.1)
data DNSHeader = DNSHeader
  { dhId      :: !Word16
  , dhFlags   :: !Word16
  , dhQdCount :: !Word16
  , dhAnCount :: !Word16
  , dhNsCount :: !Word16
  , dhArCount :: !Word16
  } deriving stock (Eq, Show, Generic)

-- | DNS Question (RFC 1035 section 4.1.2)
data DNSQuestion = DNSQuestion
  { qName  :: !Text
  , qType  :: !Word16
  , qClass :: !Word16
  } deriving stock (Eq, Show, Generic)

-- | DNS Resource Record (RFC 1035 section 4.1.3)
data DNSResourceRecord = DNSResourceRecord
  { rrName  :: !Text
  , rrType  :: !Word16
  , rrClass :: !Word16
  , rrTTL   :: !Word32
  , rrRData :: !ByteString
  } deriving stock (Eq, Show, Generic)

-- | Full DNS Message (RFC 1035 section 4)
data DNSMessage = DNSMessage
  { msgHeader     :: !DNSHeader
  , msgQuestions  :: !(NonEmpty DNSQuestion)
  , msgAnswers    :: ![DNSResourceRecord]
  , msgAuthority  :: ![DNSResourceRecord]
  , msgAdditional :: ![DNSResourceRecord]
  } deriving stock (Eq, Show, Generic)

data DNSError = DNSError Text
  deriving stock (Eq, Show, Generic)

instance Exception DNSError

-------------------------------------------------------------------------------
-- Header
-------------------------------------------------------------------------------

encodeHeader :: DNSHeader -> ByteString
encodeHeader h = BS.concat
  [ be16 (dhId h), be16 (dhFlags h)
  , be16 (dhQdCount h), be16 (dhAnCount h)
  , be16 (dhNsCount h), be16 (dhArCount h)
  ]

decodeHeader :: ByteString -> Either Text DNSHeader
decodeHeader bs
  | BS.length bs < 12 = Left (pack "DNS message too short for header")
  | otherwise = Right $ DNSHeader
      { dhId      = be16To (at 0) (at 1)
      , dhFlags   = be16To (at 2) (at 3)
      , dhQdCount = be16To (at 4) (at 5)
      , dhAnCount = be16To (at 6) (at 7)
      , dhNsCount = be16To (at 8) (at 9)
      , dhArCount = be16To (at 10) (at 11)
      }
  where at i = fromMaybe 0 (bs BS.!? i)

-------------------------------------------------------------------------------
-- Name encoding/decoding (RFC 1035 section 4.1.4)
-------------------------------------------------------------------------------

encodeName :: Text -> ByteString
encodeName name =
  let labels = filter (not . T.null) (T.splitOn "." name)
      encoded = map (\lbl -> let enc = TE.encodeUtf8 lbl
                             in BS.cons (fromIntegral (BS.length enc)) enc) labels
  in BS.concat encoded <> BS.singleton 0

-- | Decode a name starting at offset. Returns (name, next-offset).
-- | Follows compression pointers (RFC 1035 section 4.1.4).
decodeName :: ByteString -> Int -> Either Text (Text, Int)
decodeName bs startOff = do
  (labels, finalOff) <- go startOff []
  pure (T.intercalate "." (map TE.decodeUtf8 (reverse labels)), finalOff)
  where
    -- go: current offset, accumulated labels; returns (labels, offset-after-name)
    go :: Int -> [ByteString] -> Either Text ([ByteString], Int)
    go curOff labels
      | curOff >= BS.length bs = Left (pack "DNS name truncated")
      | otherwise = do
          len <- maybe (Left (pack "DNS name truncated")) Right (bs BS.!? curOff)
          if len >= 0xC0
            then -- compression pointer
              case bs BS.!? (curOff + 1) of
                Nothing -> Left (pack "DNS compression pointer truncated")
                Just lo -> let ptr = fromIntegral (len .&. 0x3F) * 256 + fromIntegral lo
                           in case go ptr labels of
                                Left err -> Left err
                                Right r -> Right (fst r, curOff + 2)
            else if len == 0
              then Right (labels, curOff + 1)
              else if curOff + 1 + fromIntegral len > BS.length bs
                then Left (pack "DNS label truncated")
                else let lbl = BS.take (fromIntegral len) (BS.drop (curOff + 1) bs)
                     in go (curOff + 1 + fromIntegral len) (lbl:labels)

-------------------------------------------------------------------------------
-- Question
-------------------------------------------------------------------------------

encodeQuestion :: DNSQuestion -> ByteString
encodeQuestion q = BS.concat
  [ encodeName (qName q), be16 (qType q), be16 (qClass q) ]

decodeQuestion :: ByteString -> Int -> Either Text (DNSQuestion, Int)
decodeQuestion bs offset = do
  (name, nameEnd) <- decodeName bs offset
  if nameEnd + 4 > BS.length bs
    then Left (pack "DNS question truncated")
    else Right (DNSQuestion
      { qName  = name
      , qType  = be16To (fromMaybe 0 (bs BS.!? nameEnd)) (fromMaybe 0 (bs BS.!? (nameEnd + 1)))
      , qClass = be16To (fromMaybe 0 (bs BS.!? (nameEnd + 2))) (fromMaybe 0 (bs BS.!? (nameEnd + 3)))
      }, nameEnd + 4)

-------------------------------------------------------------------------------
-- Resource Record
-------------------------------------------------------------------------------

encodeRR :: DNSResourceRecord -> ByteString
encodeRR rr = BS.concat
  [ encodeName (rrName rr)
  , be16 (rrType rr), be16 (rrClass rr)
  , be32 (rrTTL rr)
  , be16 (fromIntegral (BS.length (rrRData rr)))
  , rrRData rr
  ]

decodeRR :: ByteString -> Int -> Either Text (DNSResourceRecord, Int)
decodeRR bs offset = do
  (name, nameEnd) <- decodeName bs offset
  if nameEnd + 10 > BS.length bs
    then Left (pack "DNS RR truncated")
    else
      let at i = fromMaybe 0 (bs BS.!? i)
          tt    = be16To (at nameEnd) (at (nameEnd + 1))
          cl    = be16To (at (nameEnd + 2)) (at (nameEnd + 3))
          ttl   = be32To (at (nameEnd + 4)) (at (nameEnd + 5)) (at (nameEnd + 6)) (at (nameEnd + 7))
          rdLen = fromIntegral (be16To (at (nameEnd + 8)) (at (nameEnd + 9)))
      in if nameEnd + 10 + rdLen > BS.length bs
         then Left (pack "DNS RR RDATA truncated")
         else Right (DNSResourceRecord
           { rrName  = name
           , rrType  = tt
           , rrClass = cl
           , rrTTL   = ttl
           , rrRData = BS.take rdLen (BS.drop (nameEnd + 10) bs)
           }, nameEnd + 10 + rdLen)

-------------------------------------------------------------------------------
-- Full Message
-------------------------------------------------------------------------------

encodeMessage :: DNSMessage -> ByteString
encodeMessage msg = BS.concat
  [ encodeHeader (msgHeader msg)
  , BS.concat (map encodeQuestion (toList (msgQuestions msg)))
  , BS.concat (map encodeRR (msgAnswers msg))
  , BS.concat (map encodeRR (msgAuthority msg))
  , BS.concat (map encodeRR (msgAdditional msg))
  ]

decodeMessage :: ByteString -> Either Text DNSMessage
decodeMessage bs
  | BS.length bs < 12 = Left (pack "DNS message too short")
  | otherwise = do
      hdr <- decodeHeader bs
      if dhQdCount hdr == 0
        then Left (pack "DNS message must have at least one question")
        else do
          (qs, qEnd)  <- decodeN (fromIntegral (dhQdCount hdr)) decodeQuestion bs 12 []
          (ans, aEnd) <- decodeN (fromIntegral (dhAnCount hdr)) decodeRR bs qEnd []
          (auth, auEnd) <- decodeN (fromIntegral (dhNsCount hdr)) decodeRR bs aEnd []
          (add, _)    <- decodeN (fromIntegral (dhArCount hdr)) decodeRR bs auEnd []
          case nonEmpty qs of
            Nothing -> Left (pack "DNS message has no questions")
            Just qs' -> Right DNSMessage
              { msgHeader     = hdr
              , msgQuestions  = qs'
              , msgAnswers    = ans
              , msgAuthority  = auth
              , msgAdditional = add
              }
  where
    decodeN :: Int -> (ByteString -> Int -> Either Text (a, Int)) -> ByteString -> Int -> [a]
            -> Either Text ([a], Int)
    decodeN 0 _ _ off acc = Right (reverse acc, off)
    decodeN n f bs' off acc = do
      (x, off') <- f bs' off
      decodeN (n - 1) f bs' off' (x:acc)

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

be16 :: Word16 -> ByteString
be16 w = BS.pack [fromIntegral (w `shiftR` 8), fromIntegral w]

be32 :: Word32 -> ByteString
be32 w = BS.pack
  [ fromIntegral (w `shiftR` 24), fromIntegral (w `shiftR` 16)
  , fromIntegral (w `shiftR` 8), fromIntegral w
  ]

be16To :: Word8 -> Word8 -> Word16
be16To hi lo = fromIntegral hi * 256 + fromIntegral lo

be32To :: Word8 -> Word8 -> Word8 -> Word8 -> Word32
be32To b3 b2 b1 b0 =
  fromIntegral b3 * 16777216 +
  fromIntegral b2 * 65536 +
  fromIntegral b1 * 256 +
  fromIntegral b0