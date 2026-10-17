{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Resolution-level errors (раздел 6.3).
--
-- These describe failures of the pipeline itself; per-backend call failures are
-- 'Polyresolver.Types.Result.BackendError'.
module Polyresolver.Types.Errors
  ( ResolveError(..)
  , resolveErrorToText
  , backendErrorToText
  ) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import Polyresolver.Types.Adapters (AdapterId (..))
import Polyresolver.Types.Graph (CycleError)
import Polyresolver.Types.Result (BackendError (..))

-- | Failure of the resolution pipeline.
data ResolveError
  = CycleDetected !CycleError
    -- ^ Delegation cycle aborted the resolution (ТРЕБ-018).
  | ZoneConflict !Text
    -- ^ Two adapters claim the same namespace (ТРЕБ-001 violated).
  | AdapterFailed !AdapterId !BackendError
  | InvalidRequest !Text
  | MaxDepthExceeded !Int
    -- ^ Safety net for delegation chains; the primary guard is
    --   'Polyresolver.Types.Graph.detectCycle'.
  deriving stock (Eq, Show, Generic)

-- | Human-readable rendering for logs and HTTP API error bodies.
resolveErrorToText :: ResolveError -> Text
resolveErrorToText = \case
  CycleDetected _    -> "delegation cycle detected"
  ZoneConflict z     -> "namespace conflict: " <> z
  AdapterFailed a e  -> "adapter " <> unAdapterId a <> " failed: " <> backendErrorToText e
  InvalidRequest m   -> "invalid request: " <> m
  MaxDepthExceeded n -> "delegation depth " <> showT n <> " exceeded"

-- | Human-readable rendering of a backend failure.
backendErrorToText :: BackendError -> Text
backendErrorToText = \case
  Timeout ms         -> "timeout after " <> showT ms <> "ms"
  ConnectionFailed m -> "connection failed: " <> m
  InvalidResponse m  -> "invalid response: " <> m
  RateLimitExceeded s -> "rate limited, retry in " <> showT s <> "s"
  UnknownError m     -> "unknown error: " <> m

showT :: Show a => a -> Text
showT = T.pack . show
-- * JSON instances ---------------------------------------------------------

instance ToJSON ResolveError where
  toJSON = Aeson.genericToJSON Aeson.defaultOptions

instance FromJSON ResolveError where
  parseJSON = Aeson.genericParseJSON Aeson.defaultOptions
