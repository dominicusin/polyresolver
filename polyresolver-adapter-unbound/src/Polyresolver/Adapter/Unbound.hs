{-# LANGUAGE DerivingStrategies, OverloadedStrings, ScopedTypeVariables, LambdaCase, RecordWildCards #-}

-- | Unbound adapter — delegates ICANN-DNS queries to a local Unbound
-- | instance (ТРЕБ-004: the only backend for standard DNS).
module Polyresolver.Adapter.Unbound
  ( UnboundConfig(..)
  , unboundAdapter
  , defaultUnboundConfig
  , resolveViaUnbound
  , healthCheckUnbound
  ) where

import Control.Exception (try, SomeException)
import Data.Bits ((.&.))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word16)
import Network.Socket (SocketType(..), Family(..), Socket, close, socket, connect, setSocketOption, SocketOption(..))
import qualified Network.Socket as NS
import qualified Network.Socket.ByteString as NSB

import Polyresolver.Core.Adapter (AdapterEntry(..))
import Polyresolver.DNS.Codec
  ( DNSMessage(..), DNSHeader(..), DNSQuestion(..), DNSResourceRecord(..)
  , encodeMessage, decodeMessage, encodeName
  )
import Polyresolver.Types.Adapters (AdapterId(..), NamingModel(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Request (ResolveRequest(..))
import Polyresolver.Types.Result
  ( ResolveResult(..), HealthStatus(..), BackendError(..), ClassicRecord(..)
  )
import Polyresolver.Types.Namespace (ZonePattern(..))
import Polyresolver.Types.QType (QType(..), qTypeText)

data UnboundConfig = UnboundConfig
  { ucHost :: !Text
  , ucPort :: !Int
  , ucTimeoutMs :: !Int
  } deriving stock (Eq, Show)

defaultUnboundConfig :: UnboundConfig
defaultUnboundConfig = UnboundConfig
  { ucHost = "127.0.0.1"
  , ucPort = 5335
  , ucTimeoutMs = 2000
  }

unboundAdapter :: UnboundConfig -> IO AdapterEntry
unboundAdapter cfg = pure AdapterEntry
  { aeId = AdapterId "unbound"
  , aeName = "unbound"
  , aeZones = [SuffixMatch "*"]
  , aeModel = ModelHierarchicalRegistry
  , aeAuthoritative = False
  , aeTimeoutMs = ucTimeoutMs cfg
  , aeResolve = resolveViaUnbound cfg
  , aeHealth = healthCheckUnbound cfg
  , aeShutdown = pure ()
  }

-- | Build a DNS message from a ResolveRequest.
buildDNSQuery :: ResolveRequest -> DNSMessage
buildDNSQuery req =
  let q = DNSQuestion
        { qName = reqName req
        , qType = qTypeToWord (reqType req)
        , qClass = 1
        }
      hdr = DNSHeader
        { dhId = 0x1234
        , dhFlags = 0x0100  -- RD (recursion desired)
        , dhQdCount = 1
        , dhAnCount = 0
        , dhNsCount = 0
        , dhArCount = 0
        }
  in DNSMessage
       { msgHeader = hdr
       , msgQuestions = (q :| [])
       , msgAnswers = []
       , msgAuthority = []
       , msgAdditional = []
       }

-- | Resolve via Unbound by forwarding the DNS query.
resolveViaUnbound :: UnboundConfig -> ResolveRequest -> IO (Either ResolveError ResolveResult)
resolveViaUnbound cfg req = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.setSocketOption sock ReuseAddr 1
    NS.connect sock (NS.SockAddrInet (fromIntegral (ucPort cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    let query = buildDNSQuery req
    NSB.sendAll sock (encodeMessage query)
    response <- NSB.recv sock 4096
    NS.close sock
    pure (parseDNSResponse response)
  case result of
    Left err -> pure (Left (AdapterFailed (AdapterId "unbound") (UnknownError (T.pack (show (err :: SomeException))))))
    Right (Left err) -> pure (Left err)
    Right (Right res) -> pure (Right res)

-- | Parse a DNS response from Unbound.
parseDNSResponse :: ByteString -> Either ResolveError ResolveResult
parseDNSResponse bs =
  case decodeMessage bs of
    Left err -> Left (AdapterFailed (AdapterId "unbound") (InvalidResponse err))
    Right msg ->
      let flags = dhFlags (msgHeader msg)
          rcode = fromIntegral (flags .&. 0x000F) :: Int
      in if null (msgAnswers msg)
           then if rcode == 3
                  then Right NotFound
                  else Right (Classic ((ClassicRecord "" "" BS.empty) :| []))
           else case NE.nonEmpty (map dnsRRToClassic (msgAnswers msg)) of
                  Nothing -> Right NotFound
                  Just ne -> Right (Classic ne)

-- | Convert a wire-format RR to a ClassicRecord.
dnsRRToClassic :: DNSResourceRecord -> ClassicRecord
dnsRRToClassic rr = ClassicRecord
  { crName = rrName rr
  , crRType = wordToTypeText (rrType rr)
  , crRData = rrRData rr
  }

qTypeToWord :: QType -> Word16
qTypeToWord QTA = 1
qTypeToWord QTAAAA = 28
qTypeToWord QTTXT = 16
qTypeToWord QTCNAME = 5
qTypeToWord QTMX = 15
qTypeToWord QTSRV = 33
qTypeToWord (QTRaw n) = fromIntegral n

wordToTypeText :: Word16 -> Text
wordToTypeText 1 = "A"
wordToTypeText 28 = "AAAA"
wordToTypeText 16 = "TXT"
wordToTypeText 5 = "CNAME"
wordToTypeText 15 = "MX"
wordToTypeText 33 = "SRV"
wordToTypeText n = "TYPE" <> T.pack (show n)

healthCheckUnbound :: UnboundConfig -> IO HealthStatus
healthCheckUnbound cfg = do
  result <- try $ do
    sock <- NS.socket AF_INET Datagram 0
    NS.connect sock (NS.SockAddrInet (fromIntegral (ucPort cfg)) (NS.tupleToHostAddress (127, 0, 0, 1)))
    NSB.sendAll sock (encodeMessage (newResolveRequest))
    _ <- NSB.recv sock 4096
    NS.close sock
    pure ()
  case result of
    Left err -> pure (Unhealthy (T.pack (show (err :: SomeException))))
    Right () -> pure Healthy

newResolveRequest :: DNSMessage
newResolveRequest = DNSMessage
  { msgHeader = DNSHeader 0x0000 0x0100 1 0 0 0
  , msgQuestions = (DNSQuestion "health.check" 1 1 :| [])
  , msgAnswers = []
  , msgAuthority = []
  , msgAdditional = []
  }

-- Re-export hidden helpers for tests
_hidden :: ()
_hidden = ()
