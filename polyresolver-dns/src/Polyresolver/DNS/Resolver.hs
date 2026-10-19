{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, LambdaCase, DerivingStrategies, RecordWildCards #-}

module Polyresolver.DNS.Resolver
  ( DNSConfig(..)
  , defaultDNSConfig
  , handleDNSQuery
  ) where

import Data.Bits ((.&.), (.|.))
import Data.ByteString (ByteString)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import Data.Time (getCurrentTime, UTCTime)
import Data.Word (Word16)

import Polyresolver.Core.Engine (Engine, resolve)
import Polyresolver.DNS.Codec
  ( DNSMessage(..), DNSHeader(..), DNSQuestion(..), DNSResourceRecord(..)
  , encodeMessage
  )
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Result
  ( ResolveResult(..), ClassicRecord(..)
  )
import Polyresolver.Types.Request (ResolveRequest(..), ClientContext(..))
import Polyresolver.Types.Graph (ResolutionNode(..))
import Polyresolver.Types.QType (QType(..))

data DNSConfig = DNSConfig
  { dcAddress :: !Text
  , dcPort    :: !Int
  } deriving (Eq, Show)

defaultDNSConfig :: DNSConfig
defaultDNSConfig = DNSConfig
  { dcAddress = "127.0.0.1"
  , dcPort    = 5300
  }

-- | Process a DNS query through the engine and return the response message.
handleDNSQuery :: Engine -> DNSMessage -> IO DNSMessage
handleDNSQuery engine query = do
  now <- getCurrentTime
  let req = messageToRequest now query
  result <- resolve engine req
  pure (either (\_ -> buildResponse query NotFound) (buildResponse query) result)

-- | Convert a DNSMessage to a ResolveRequest.
messageToRequest :: UTCTime -> DNSMessage -> ResolveRequest
messageToRequest now msg =
  let q = NE.head (msgQuestions msg)
  in ResolveRequest
       { reqName  = qName q
       , reqType  = wordToQType (qType q)
  , reqCtx   = ClientContext "127.0.0.1" "default" "dns-query"
  , reqGraph = Seq.empty
  , reqAt    = now
  }

-- | Build a DNS response message from the query and resolution result.
buildResponse :: DNSMessage -> ResolveResult -> DNSMessage
buildResponse query result =
  let hdr = msgHeader query
      flags = setQrBit (dhFlags hdr)
  in case result of
    Classic rrSet ->
      let answers = map classicRecordToWire (toListNE rrSet)
      in DNSMessage
           { msgHeader = hdr { dhAnCount = fromIntegral (length answers), dhFlags = flags }
           , msgQuestions = msgQuestions query
           , msgAnswers = answers
           , msgAuthority = []
           , msgAdditional = []
           }
    NotFound ->
      let flags' = setRcode flags 3  -- NXDOMAIN
      in DNSMessage
           { msgHeader = hdr { dhAnCount = 0, dhFlags = flags' }
           , msgQuestions = msgQuestions query
           , msgAnswers = []
           , msgAuthority = []
           , msgAdditional = []
           }
    TemporarilyUnavailable _ ->
      let flags' = setRcode flags 2  -- SERVFAIL
      in DNSMessage
           { msgHeader = hdr { dhAnCount = 0, dhFlags = flags' }
           , msgQuestions = msgQuestions query
           , msgAnswers = []
           , msgAuthority = []
           , msgAdditional = []
           }
    _ ->
      -- Structured / Delegate: NOERROR, empty answer (handled via HTTP API)
      DNSMessage
        { msgHeader = hdr { dhAnCount = 0, dhFlags = flags }
        , msgQuestions = msgQuestions query
        , msgAnswers = []
        , msgAuthority = []
        , msgAdditional = []
        }

-- | Convert a ClassicRecord to wire format.
classicRecordToWire :: ClassicRecord -> DNSResourceRecord
classicRecordToWire cr = DNSResourceRecord
  { rrName  = crName cr
  , rrType  = textToTypeWord (crRType cr)
  , rrClass = 1  -- IN
  , rrTTL   = 300
  , rrRData = crRData cr
  }

setQrBit :: Word16 -> Word16
setQrBit flags = flags .|. 0x8000

setRcode :: Word16 -> Int -> Word16
setRcode flags rc = (flags .&. 0xFFF0) .|. fromIntegral rc

textToTypeWord :: Text -> Word16
textToTypeWord "A"     = 1
textToTypeWord "AAAA"  = 28
textToTypeWord "CNAME" = 5
textToTypeWord "MX"    = 15
textToTypeWord "TXT"   = 16
textToTypeWord "NS"    = 2
textToTypeWord "SOA"   = 6
textToTypeWord "PTR"   = 12
textToTypeWord "SRV"   = 33
textToTypeWord "ANY"   = 255
textToTypeWord _       = 0

wordToQType :: Word16 -> QType
wordToQType 1   = QTA
wordToQType 28  = QTAAAA
wordToQType 5   = QTCNAME
wordToQType 15  = QTMX
wordToQType 16  = QTTXT
wordToQType 2   = QTRaw 2
wordToQType 6   = QTRaw 6
wordToQType 12  = QTRaw 12
wordToQType 33  = QTSRV
wordToQType 255 = QTRaw 255
wordToQType n   = QTRaw (fromIntegral n)

toListNE :: NonEmpty a -> [a]
toListNE = NE.toList