{-# LANGUAGE DeriveGeneric #-}

module Polyresolver.PluginSDK.ABI
  ( PluginRequest(..)
  , PluginResponse(..)
  , PluginCapabilities(..)
  , PluginInfo(..)
  , PluginError(..)
  , currentABIVersion
  , negotiateCapabilities
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
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (Binary)

data PluginResponse = PluginResponse
  { prResult :: !(Either ResolveError ResolveResult)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (Binary)

data PluginCapabilities = PluginCapabilities
  { pcStreamingResults :: !Bool
  , pcAsyncCancel      :: !Bool
  , pcPartialResults   :: !Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (Binary)

data PluginInfo = PluginInfo
  { piName         :: !Text
  , piVersion      :: !Text
  , piABIVersion   :: !Word32
  , piCapabilities :: !PluginCapabilities
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (Binary)

data PluginError
  = PluginInitError Text
  | PluginResolveError Text
  | PluginShutdownError Text
  deriving stock (Eq, Show, Generic)
    deriving anyclass (Binary)

currentABIVersion :: Word32
currentABIVersion = 1

negotiateCapabilities :: PluginCapabilities -> PluginCapabilities -> PluginCapabilities
negotiateCapabilities client server = PluginCapabilities
  { pcStreamingResults = pcStreamingResults client && pcStreamingResults server
  , pcAsyncCancel      = pcAsyncCancel client && pcAsyncCancel server
  , pcPartialResults   = pcPartialResults client && pcPartialResults server
  }
