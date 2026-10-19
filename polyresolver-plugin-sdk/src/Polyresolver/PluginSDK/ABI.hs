{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveAnyClass #-}

module Polyresolver.PluginSDK.ABI
  ( PluginRequest(..)
  , PluginResponse(..)
  , PluginCapabilities(..)
  , PluginInfo(..)
  , PluginError(..)
  , currentABIVersion
  , negotiateCapabilities
  , ResolveError(..)
  ) where

import Data.Binary (Binary)
import Data.Text (Text)
import GHC.Generics (Generic)
import Data.Word (Word32)

import Polyresolver.Types.Request (ResolveRequest)
import Polyresolver.Types.Result (ResolveResult, HealthStatus)
import Polyresolver.Types.Errors (ResolveError)

data PluginRequest = PluginRequest
  { prRequest :: !ResolveRequest
  } deriving (Eq, Show, Generic)

data PluginResponse = PluginResponse
  { prResult :: !(Either ResolveError ResolveResult)
  } deriving (Eq, Show, Generic)

data PluginCapabilities = PluginCapabilities
  { pcStreamingResults :: !Bool
  , pcAsyncCancel      :: !Bool
  , pcPartialResults   :: !Bool
  } deriving (Eq, Show, Generic)

data PluginInfo = PluginInfo
  { piName         :: !Text
  , piVersion      :: !Text
  , piABIVersion   :: !Word32
  , piCapabilities :: !PluginCapabilities
  } deriving (Eq, Show, Generic)

data PluginError
  = PluginInitError Text
  | PluginResolveError Text
  | PluginShutdownError Text
  deriving (Eq, Show, Generic)

currentABIVersion :: Word32
currentABIVersion = 1

negotiateCapabilities :: PluginCapabilities -> PluginCapabilities -> PluginCapabilities
negotiateCapabilities client server = PluginCapabilities
  { pcStreamingResults = pcStreamingResults client && pcStreamingResults server
  , pcAsyncCancel      = pcAsyncCancel client && pcAsyncCancel server
  , pcPartialResults   = pcPartialResults client && pcPartialResults server
  }
