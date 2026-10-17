{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Query type (раздел 6.2).
--
-- Kept in its own module so that both 'Polyresolver.Types.Request' (which
-- carries it) and 'Polyresolver.Types.Graph' (which records hops) can name it
-- without a module cycle. @polyresolver-dns@ supplies the mapping to the
-- concrete wire-format type.
module Polyresolver.Types.QType
  ( QType(..)
  , qTypeText
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Hashable (Hashable)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | DNS query type, abstracted over the wire-format library.
data QType
  = QTA | QTAAAA | QTTXT | QTCNAME | QTMX | QTSRV | QTRaw !Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON, FromJSON, Hashable)

-- | Presentation form, as used in logs and in the HTTP API's @type@ parameter.
qTypeText :: QType -> Text
qTypeText qt = case qt of
  QTA     -> "A"
  QTAAAA  -> "AAAA"
  QTTXT   -> "TXT"
  QTCNAME -> "CNAME"
  QTMX    -> "MX"
  QTSRV   -> "SRV"
  QTRaw n -> "TYPE" <> showT n
  where
    showT = T.pack . show
