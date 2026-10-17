{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

-- | Resolution request passed from the routing engine to an adapter.
module Polyresolver.Types.Request
  ( ResolveRequest(..)
  , ClientContext(..)
  , QType(..)
  , newResolveRequest
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Sequence (Seq)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import Polyresolver.Types.Graph (ResolutionNode)
import Polyresolver.Types.QType (QType (..))

-- | Per-client data used for view/ACL selection (ТРЕБ-005).
data ClientContext = ClientContext
  { ctxPeerAddr :: !Text
    -- ^ Peer address as reported by the edge layer (dnsdist) or API gateway.
  , ctxView      :: !Text
    -- ^ Selected view name; @default@ unless the edge layer overrides it.
  , ctxRequestId :: !Text
    -- ^ Correlation id propagated into logs, metrics and ResolutionGraph.
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | A single resolution request.
data ResolveRequest = ResolveRequest
  { reqName  :: !Text
    -- ^ Query name in presentation form, fully qualified, lowercased.
  , reqType  :: !QType
  , reqCtx   :: !ClientContext
  , reqGraph :: !(Seq ResolutionNode)
    -- ^ Delegation chain accumulated so far; inspected by 'detectCycle'.
  , reqAt    :: !UTCTime
  } deriving stock (Eq, Show, Generic)

-- | Build a request for the first hop of a query.
newResolveRequest
  :: Text        -- ^ name
  -> QType       -- ^ type
  -> ClientContext
  -> UTCTime
  -> ResolveRequest
newResolveRequest name qtype ctx now = ResolveRequest
  { reqName  = name
  , reqType  = qtype
  , reqCtx   = ctx
  , reqGraph = mempty
  , reqAt    = now
  }