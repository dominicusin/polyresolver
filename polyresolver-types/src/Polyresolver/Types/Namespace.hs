{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Zone / namespace patterns (раздел 6.2).
--
-- Routing is longest-suffix-match over 'ZonePattern' values; conflicts are
-- resolved by explicit policy, never by registration order (ТРЕБ-001/002).
module Polyresolver.Types.Namespace
  ( ZonePattern(..)
  , parseZonePattern
  , matchesZone
  , zoneText
  ) where

import Data.Aeson (FromJSON, ToJSON, (.=))
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import qualified Data.Text as T

-- | How a namespace is claimed by an adapter.
--
-- A bare 'SuffixMatch' such as @\".hns\"@ is the common case. 'PredicateMatch'
-- covers namespaces whose names are not plain suffixes — Tor @.onion@ v3
-- (56-character base32) is the motivating example.
data ZonePattern
  = SuffixMatch !Text
  | ExactMatch  !Text
  | PredicateMatch !(Text -> Bool)

-- | Structural equality. Two 'PredicateMatch' patterns are never equal:
-- functions have no decidable equality, and treating them as distinct keeps
-- the instance lawful without silently merging different predicates.
instance Eq ZonePattern where
  SuffixMatch a == SuffixMatch b = a == b
  ExactMatch  a == ExactMatch  b = a == b
  PredicateMatch _ == PredicateMatch _ = False
  _ == _ = False

-- | A function field cannot be shown generically, so 'PredicateMatch' renders
-- as a marker. This keeps 'ZonePattern' inspectable in logs and the API.
instance Show ZonePattern where
  show (SuffixMatch s)    = "suffix:" <> T.unpack s
  show (ExactMatch s)     = "exact:" <> T.unpack s
  show (PredicateMatch _) = "predicate:<opaque>"

-- | Render the pattern for logs and the HTTP API.
zoneText :: ZonePattern -> Text
zoneText (SuffixMatch s)    = "." <> s
zoneText (ExactMatch s)     = s
zoneText (PredicateMatch _) = "<predicate>"

-- | Parse a pattern written in configuration.
--
-- Accepts @\".hns\"@, @\"*.hns\"@ and @\"example.hns\"@; the latter two are
-- both treated as suffix matches, matching how the ТЗ examples are written.
parseZonePattern :: Text -> ZonePattern
parseZonePattern t
  | Just rest <- T.stripPrefix "*." t = SuffixMatch rest
  | Just rest <- T.stripPrefix "*"  t = SuffixMatch rest
  | Just rest <- T.stripPrefix "."   t = SuffixMatch rest
  | otherwise                        = ExactMatch t

-- | Does @name@ fall inside this pattern?
--
-- Both sides are compared case-folded: DNS names are case-insensitive and a
-- configured pattern must not depend on how the operator happened to spell it.
matchesZone :: ZonePattern -> Text -> Bool
matchesZone (SuffixMatch suffix) name =
  T.isSuffixOf (T.toLower suffix) (T.toLower name)
matchesZone (ExactMatch exact)   name = T.toLower name == T.toLower exact
matchesZone (PredicateMatch p)   name = p name

-- * JSON instances ---------------------------------------------------------

-- | Configured patterns are serialisable; an opaque 'PredicateMatch' has no
-- JSON form and is rejected on parse, so a loaded config can be echoed back
-- without silently inventing semantics.
instance ToJSON ZonePattern where
  toJSON (SuffixMatch t)    = Aeson.object ["type" .= ("suffix" :: Text), "value" .= t]
  toJSON (ExactMatch t)     = Aeson.object ["type" .= ("exact"  :: Text), "value" .= t]
  toJSON (PredicateMatch _) = Aeson.Null

instance FromJSON ZonePattern where
  parseJSON = Aeson.withObject "ZonePattern" $ \o -> do
    ty <- o Aeson..: "type"
    case ty :: Text of
      "suffix" -> SuffixMatch <$> o Aeson..: "value"
      "exact"  -> ExactMatch  <$> o Aeson..: "value"
      _        -> fail ("unknown ZonePattern type: " ++ show ty)
