{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Namespace routing (раздел 5.4, шаг 3).
--
-- The routing table maps a query name to exactly one adapter. Two rules make
-- this total and predictable:
--
-- * longest-suffix-match over the configured 'ZonePattern's;
-- * ties and overlaps are settled by explicit policy (ТРЕБ-002), never by
--   adapter registration order.
--
-- A name that matches nothing yields 'NoRoute', which the engine maps to
-- NXDOMAIN — there is no heuristic guessing (ТРЕБ-003).
module Polyresolver.Core.Routing
  ( Route(..)
  , RouteDecision(..)
  , ConflictPolicy(..)
  , RoutingTable(..)
  , buildTable
  , lookupRoute
  , routeSpecificity
  , tableRoutes
  , duplicateRoutes
  ) where

import Data.List (maximumBy, minimumBy, sortOn)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

import Polyresolver.Types.Adapters (AdapterId (..), Priority)
import Polyresolver.Types.Namespace (ZonePattern (..))

-- | One authoritative namespace claim.
data Route = Route
  { routeAdapter  :: !AdapterId
    -- ^ Adapter that owns this namespace (ТРЕБ-001: exactly one).
  , routePattern  :: !ZonePattern
  , routePriority :: !Priority
    -- ^ Lower wins. The catch-all Unbound route is explicitly the lowest
    --   priority (раздел 7.1).
  } deriving stock (Eq, Show)

-- | Outcome of routing a single query name.
data RouteDecision
  = RouteTo !AdapterId
    -- ^ Exactly one adapter owns this namespace.
  | NoRoute
    -- ^ Nothing claims this namespace (ТРЕБ-003 → NXDOMAIN).
  | RouteConflict ![(AdapterId, Priority)]
    -- ^ Several adapters claim this namespace at the same specificity. The
    --   caller must apply 'ConflictPolicy' or fail.
  deriving stock (Eq, Show)

-- | How overlapping namespaces are settled (раздел 15.3).
data ConflictPolicy
  = Explicit
    -- ^ Any overlapping claim is a configuration error. This is the default:
    --   it is the policy that actually implements ТРЕБ-002.
  | LowestPriorityWins
    -- ^ Deterministic convenience fallback: the numerically lowest priority
    --   wins. Still explicit — never registration order.
  deriving stock (Eq, Show)

-- | An immutable routing table.
data RoutingTable = RoutingTable
  { rtRoutes   :: ![Route]
  , rtConflict :: !ConflictPolicy
  } deriving stock (Eq, Show)

-- | How specific a pattern is: longer suffixes win. An exact match beats a
-- suffix match of the same length; an opaque predicate is least specific.
routeSpecificity :: ZonePattern -> Int
routeSpecificity (SuffixMatch s)    = T.length s
routeSpecificity (ExactMatch s)     = T.length s + 1
routeSpecificity (PredicateMatch _) = 0

-- | Build a routing table, rejecting configurations that violate ТРЕБ-001.
--
-- A namespace claimed by two adapters is rejected regardless of policy: the
-- whole point of ТРЕБ-001 is that there is no second authoritative owner.
-- Rejecting at construction time is what makes the invariant a property of
-- the type rather than a convention the engine has to remember.
buildTable
  :: ConflictPolicy
  -> [Route]
  -> Either Text RoutingTable
buildTable policy routes
  | not (null dups) = Left ("duplicate namespace claim(s): " <> T.intercalate ", " dups)
  | otherwise       = Right (RoutingTable routes policy)
  where
    dups = [ unAdapterId (routeAdapter r1)
           | r1 <- routes
           , r2 <- routes
           , routeAdapter r1 /= routeAdapter r2
           , routePattern r1 == routePattern r2
           ]

-- | Routes whose patterns overlap at equal specificity.
--
-- Under 'Explicit' these are the configurations 'buildTable' refuses; under
-- 'LowestPriorityWins' they are resolved by priority.
duplicateRoutes :: RoutingTable -> [(Route, Route)]
duplicateRoutes table =
  [ (r1, r2)
  | r1 <- rs
  , r2 <- rs
  , routeAdapter r1 < routeAdapter r2
  , routePattern r1 == routePattern r2
  ]
  where
    rs = rtRoutes table

-- | List the configured routes.
tableRoutes :: RoutingTable -> [Route]
tableRoutes = rtRoutes

-- | Route a query name.
lookupRoute :: Text -> RoutingTable -> RouteDecision
lookupRoute name table
  | null matching = NoRoute
  | otherwise     = case best of
      [r] -> RouteTo (routeAdapter r)
      rs  -> case rtConflict table of
        LowestPriorityWins ->
          RouteTo (routeAdapter (minByPrio rs))
        Explicit ->
          RouteConflict (map (\r -> (routeAdapter r, routePriority r)) rs)
  where
    matching = [ r | r <- rtRoutes table, matchesPattern (routePattern r) name ]
    maxSpec = case sortOn (Down . spec) matching of
      []      -> -1
      (r : _) -> spec r
    spec = routeSpecificity . routePattern
    best = filter ((== maxSpec) . spec) matching
    minByPrio = minimumBy (\a b -> compare (routePriority a) (routePriority b))

-- | Match a pattern against a query name (case-insensitive, DNS semantics).
matchesPattern :: ZonePattern -> Text -> Bool
matchesPattern (SuffixMatch s)    n = T.isSuffixOf (T.toLower s) (T.toLower n)
matchesPattern (ExactMatch s)     n = T.toLower n == T.toLower s
matchesPattern (PredicateMatch f)  n = f n
