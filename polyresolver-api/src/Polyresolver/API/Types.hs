{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Backend API types.
module Polyresolver.API.Types
  ( ResolveResponse(..)
  , AdapterStatus(..)
  , CacheStats(..)
  , HealthCheckResponse(..)
  , NoContent(..)
  ) where

import Data.Aeson (ToJSON)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS

-- | Response for /v1/resolve/{name}
data ResolveResponse = ResolveResponse
  { rrStatus   :: !Text
  , rrData     :: ![ByteString]
  , rrGraph    :: ![Text]
  } deriving (Generic)

-- | Status of an adapter.
data AdapterStatus = AdapterStatus
  { asName   :: !Text
  , asHealth :: !Text
  , asZones  :: ![Text]
  } deriving (Generic)

-- | Cache statistics.
data CacheStats = CacheStats
  { csSize   :: !Int
  , csHits   :: !Int
  , csMisses :: !Int
  } deriving (Generic)

-- | Health check response.
data HealthCheckResponse = HealthCheckResponse
  { hcrStatus  :: !Text
  , hcrDetails :: !(Maybe Text)
  } deriving (Generic)

-- | No content response (for DELETE, POST no-content).
newtype NoContent = NoContent
  { unNoContent :: ()
  } deriving (Generic)