{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Core.Test.Adapters where

import Data.Text (Text)

import Polyresolver.Core.Adapter (AdapterEntry (..))
import Polyresolver.Types.Adapters (AdapterId (..), NamingModel (..))
import Polyresolver.Types.Namespace (ZonePattern (..))
import Polyresolver.Types.Result (HealthStatus (..), ResolveResult (..))
import Polyresolver.Types.Request (ResolveRequest (..))
import Polyresolver.Types.QType (QType (..))
import Polyresolver.Types.Graph (ResolutionGraph (..))
import Polyresolver.Types.Errors (ResolveError (..))

data FakeAdapter = FakeAdapter
  { fakeId            :: !AdapterId
  , fakeName          :: !Text
  , fakeZones         :: ![ZonePattern]
  , fakeModel         :: !NamingModel
  , fakeAuthoritative :: !Bool
  , fakeTimeoutMs     :: !Int
  , fakeResolve       :: !(ResolveRequest -> IO (Either ResolveError ResolveResult))
  , fakeHealth        :: !(IO HealthStatus)
  }

fakeEntry :: FakeAdapter -> AdapterEntry
fakeEntry fa = AdapterEntry
  { aeId            = fakeId fa
  , aeName          = fakeName fa
  , aeZones         = fakeZones fa
  , aeModel         = fakeModel fa
  , aeAuthoritative = fakeAuthoritative fa
  , aeTimeoutMs     = fakeTimeoutMs fa
  , aeResolve       = fakeResolve fa
  , aeHealth        = fakeHealth fa
  , aeShutdown      = pure ()
  }
