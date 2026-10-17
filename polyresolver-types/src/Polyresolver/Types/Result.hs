{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

-- | Result types for the resolution pipeline (раздел 6.3).
--
-- ТРЕБ-006: an adapter MUST NOT synthesise DNS RR types (above all A/AAAA)
-- where the source system offers no semantically correct equivalent. Typed
-- non-standard data travels as 'Structured' and is never coerced into a DNS RR.
module Polyresolver.Types.Result
  ( ResolveResult(..)
  , StructuredRecord(..)
  , StructuredKind(..)
  , BackendError(..)
  , HealthStatus(..)
  , DelegateTarget(..)
  , ClassicRecord(..)
  ) where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON, ToJSON, (.=), (.!=))
import qualified Data.Aeson as Aeson
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Text (Text)
import GHC.Generics (Generic)

import Polyresolver.Types.Namespace (ZonePattern)

-- | A record of the classic RR shape.
--
-- Deliberately abstract: @polyresolver-dns@ binds this to the concrete wire
-- record type of the DNS library, so the types package stays independent of
-- the wire format (раздел 6.1).
data ClassicRecord = ClassicRecord
  { crName  :: !Text
  , crRType :: !Text
  , crRData :: !ByteString
  } deriving stock (Eq, Show, Generic)

-- | RR payloads are raw wire bytes; JSON carries them as a byte array so no
-- base64 dependency is needed.
instance ToJSON ClassicRecord where
  toJSON r = Aeson.object
    [ "name"  .= crName r
    , "rtype" .= crRType r
    , "rdata" .= BS.unpack (crRData r)
    ]

instance FromJSON ClassicRecord where
  parseJSON = Aeson.withObject "ClassicRecord" $ \o ->
    ClassicRecord <$> o Aeson..: "name"
                 <*> o Aeson..: "rtype"
                 <*> (BS.pack <$> o Aeson..: "rdata")

-- | Outcome of one resolution step.
data ResolveResult
  = Classic !(NonEmpty ClassicRecord)
    -- ^ Standard DNS RRs. Category A adapters (Handshake, ncdns, EmerDNS)
    --   and the DNSLink path of category C.
  | Structured !StructuredRecord
    -- ^ Typed non-standard data preserving the source semantics: Ethereum
    --   account/contract address, ENS contenthash, I2P destination, Reticulum
    --   destination hash, Hyphanet KSK. Returned to HTTP clients as-is; a DNS
    --   TXT projection happens only when policy explicitly allows it.
  | Delegate !DelegateTarget
    -- ^ The request must be handed to another adapter/view (e.g. an ENS
    --   contenthash pointing at @ipfs:\/\/@). Each hop adds a ResolutionNode
    --   (ТРЕБ-018).
  | NotFound
    -- ^ Authoritative "not found" for this namespace (client-facing NXDOMAIN).
  | TemporarilyUnavailable !BackendError
    -- ^ Backend unreachable; SERVFAIL vs serve-stale is decided by ТРЕБ-021.
  deriving stock (Show, Eq, Generic)

-- | Typed payload with no DNS-RR equivalent.
data StructuredRecord = StructuredRecord
  { srKind  :: !StructuredKind
  , srValue :: !ByteString
  , srMeta  :: !(Map Text Text)
    -- ^ System-specific extras, e.g. contenthash codec or RPC endpoint.
  } deriving stock (Show, Eq, Generic)

-- | Discriminator for structured payloads.
data StructuredKind
  = EthAddress        -- ^ 20-byte Ethereum address
  | ContentHash       -- ^ CID / multihash (IPFS, Arweave, …)
  | CryptoDestination  -- ^ Tor .onion v3, I2P .i2p destination
  | ContentKey        -- ^ Hyphanet KSK, IPNS name
  | NamecoinKey       -- ^ Namecoin NVS entry
  | Custom !Text      -- ^ Forward-compatible extension point
  deriving stock (Show, Eq, Ord, Generic)

-- | Why a backend call failed.
data BackendError
  = Timeout !Int            -- ^ Timeout budget in milliseconds
  | ConnectionFailed !Text
  | InvalidResponse !Text
  | RateLimitExceeded !Int  -- ^ Retry-after in seconds
  | UnknownError !Text
  deriving stock (Show, Eq, Generic)

-- | Adapter health, mirrored by the @polyresolver_adapter_up@ gauge.
data HealthStatus
  = Healthy
  | Degraded !Text
  | Unhealthy !Text
  deriving stock (Show, Eq, Generic)

-- | Where a resolution hop should go next.
data DelegateTarget = DelegateTarget
  { dtZone   :: !ZonePattern
  , dtName   :: !Text
  , dtReason :: !Text
  } deriving stock (Show, Eq, Generic)

-- * JSON instances ---------------------------------------------------------

instance ToJSON StructuredKind where
  toJSON = Aeson.genericToJSON Aeson.defaultOptions
instance FromJSON StructuredKind where
  parseJSON = Aeson.genericParseJSON Aeson.defaultOptions

-- | @srValue@ is raw bytes; it travels as a JSON byte array so the package
-- needs no base64 dependency.
instance ToJSON StructuredRecord where
  toJSON r = Aeson.object
    [ "kind"  .= srKind r
    , "value" .= BS.unpack (srValue r)
    , "meta"  .= srMeta r
    ]
instance FromJSON StructuredRecord where
  parseJSON = Aeson.withObject "StructuredRecord" $ \o ->
    StructuredRecord <$> o Aeson..: "kind"
                    <*> (BS.pack <$> o Aeson..: "value")
                    <*> o Aeson..: "meta"

instance ToJSON BackendError where
  toJSON = Aeson.genericToJSON Aeson.defaultOptions
instance FromJSON BackendError where
  parseJSON = Aeson.genericParseJSON Aeson.defaultOptions

instance ToJSON DelegateTarget where
  toJSON = Aeson.genericToJSON Aeson.defaultOptions
instance FromJSON DelegateTarget where
  parseJSON = Aeson.genericParseJSON Aeson.defaultOptions

instance ToJSON HealthStatus where
  toJSON Healthy         = Aeson.String "healthy"
  toJSON (Degraded msg)  = Aeson.object ["status" .= ("degraded" :: Text), "detail" .= msg]
  toJSON (Unhealthy msg) = Aeson.object ["status" .= ("unhealthy" :: Text), "detail" .= msg]

instance FromJSON HealthStatus where
  parseJSON = Aeson.withText "HealthStatus" $ \case
    "healthy" -> pure Healthy
    other     -> fail ("unknown health status: " ++ show other)

instance ToJSON ResolveResult where
  toJSON (Classic recs)              = Aeson.object ["kind" .= ("classic" :: Text), "records" .= recs]
  toJSON (Structured rec)            = Aeson.object ["kind" .= ("structured" :: Text), "record" .= rec]
  toJSON (Delegate target)           = Aeson.object ["kind" .= ("delegate" :: Text), "target" .= target]
  toJSON NotFound                    = Aeson.object ["kind" .= ("notfound" :: Text)]
  toJSON (TemporarilyUnavailable be) = Aeson.object ["kind" .= ("temporarily_unavailable" :: Text), "error" .= be]

instance FromJSON ResolveResult where
  parseJSON = Aeson.withObject "ResolveResult" $ \o ->
        (Classic                  <$> o Aeson..: "records")
    <|> (Structured               <$> o Aeson..: "record")
    <|> (Delegate                 <$> o Aeson..: "target")
    <|> (pure NotFound            <*  o Aeson..:? "kind" Aeson..!= Aeson.String "notfound")
    <|> (TemporarilyUnavailable   <$> o Aeson..: "error")

-- Retained for downstream packages that need the full delegation chain.
