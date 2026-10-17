{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

-- | ResolutionGraph: linear delegation chain (IR) for diagnostics and
-- cycle detection (ТРЕБ-018, раздел 6.4).
module Polyresolver.Types.Graph
  ( ResolutionNode(..)
  , ResolutionGraph(..)
  , CycleError(..)
  , detectCycle
  , graphDepth
  , graphNodes
  , emptyGraph
  , appendNode
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import GHC.Generics (Generic)

import Polyresolver.Types.QType (QType (..))

-- | One hop of a delegation chain.
data ResolutionNode = ResolutionNode
  { rnAdapter :: !Text
  , rnName    :: !Text
  , rnType    :: !QType
  } deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Delegation chain for one client query.
--
-- Deliberately linear, not a general graph: no known adapter branches its
-- delegation, and a linear sequence is exactly what the cycle invariant needs
-- (section 6.4). The type is a @newtype@ so it can be generalised to a
-- 'Data.Graph' structure later without touching the 'Resolver' interface.
newtype ResolutionGraph = ResolutionGraph { unGraph :: Seq ResolutionNode }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | A delegation cycle was detected and resolution was aborted.
data CycleError = CycleError
  { ceRepeatedNode :: !ResolutionNode
  , ceChainLength  :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Empty graph: the first hop of a query.
emptyGraph :: ResolutionGraph
emptyGraph = ResolutionGraph Seq.empty

-- | Number of delegation hops recorded so far.
graphDepth :: ResolutionGraph -> Int
graphDepth = Seq.length . unGraph

-- | All recorded hops, oldest first.
graphNodes :: ResolutionGraph -> [ResolutionNode]
graphNodes = toList . unGraph
  where toList = foldr (:) []

-- | Record a hop without checking for cycles.
appendNode :: ResolutionNode -> ResolutionGraph -> ResolutionGraph
appendNode n graph = ResolutionGraph (unGraph graph Seq.|> n)

-- | Check whether @node@ is already present in @graph@, and if not, append it.
--
-- Property under test (раздел 20.2): for any finite adapter configuration and
-- any generated sequence of 'Delegate' answers, resolution terminates in at
-- most @|adapters|@ steps, because 'detectCycle' rejects the first repeated
-- @(adapter, name, type)@ triple.
detectCycle
  :: ResolutionGraph
  -> ResolutionNode
  -> Either CycleError ResolutionGraph
detectCycle graph node
  | any (== node) (unGraph graph) =
      Left CycleError
        { ceRepeatedNode = node
        , ceChainLength  = graphDepth graph
        }
  | otherwise = Right (appendNode node graph)