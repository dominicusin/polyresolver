{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Test suite for polyresolver-types.
--
-- Property tests cover the invariants named in the specification: the
-- 'detectCycle' termination bound (раздел 20.2) and longest-suffix routing
-- behaviour (ТРЕБ-001/002).
module Main (main) where

import Data.Aeson (fromJSON, toJSON)
import qualified Data.Aeson as Aeson
import Data.List (nub)
import Data.Text (Text, intercalate)
import Hedgehog (Gen, forAll, failure, (===))
import Hedgehog.Internal.Property (PropertyT)
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import Test.Hspec (Spec, describe, hspec, it, shouldBe, shouldSatisfy)
import Test.Hspec.Hedgehog (hedgehog)

import Polyresolver.Types.Graph
import Polyresolver.Types.Namespace
import Polyresolver.Types.QType

main :: IO ()
main = hspec spec

spec :: Spec
spec = do
  describe "ZonePattern" $ do
    it "matches names by suffix, case-insensitively" $ do
      matchesZone (SuffixMatch "hns") "example.hns" `shouldBe` True
      matchesZone (SuffixMatch "hns") "EXAMPLE.HNS" `shouldBe` True
      matchesZone (SuffixMatch "hns") "example.bit" `shouldBe` False
      -- a bare "hns" label is not a ".hns" suffix
      matchesZone (SuffixMatch "hns") "hns" `shouldBe` False

    it "requires a label boundary for suffix matches" $
      matchesZone (SuffixMatch "ns") "example.hns" `shouldBe` False

    it "matches exact names" $ do
      matchesZone (ExactMatch "internal.example") "internal.example" `shouldBe` True
      matchesZone (ExactMatch "internal.example") "x.internal.example" `shouldBe` False

    it "parses wildcard and dotted forms into suffix matches" $ do
      parseZonePattern "*.hns" `shouldBe` SuffixMatch "hns"
      parseZonePattern ".hns"  `shouldBe` SuffixMatch "hns"
      -- a bare label is not a suffix pattern; it claims exactly that name
      parseZonePattern "hns"   `shouldBe` ExactMatch "hns"

    it "gives predicate patterns a stable, opaque rendering" $ do
      show (PredicateMatch (const True)) `shouldBe` "predicate:<opaque>"
      show (SuffixMatch "bit") `shouldBe` "suffix:bit"

    it "never treats two predicate patterns as equal" $
      PredicateMatch (const True) == PredicateMatch (const True) `shouldBe` False

  describe "ResolutionGraph.detectCycle" $ do
    it "rejects a repeated (adapter, name, type) triple" $ do
      let node = ResolutionNode "ens" "example.eth" QTA
      detectCycle emptyGraph node `shouldBe` Right (appendNode node emptyGraph)
      detectCycle (appendNode node emptyGraph) node
        `shouldSatisfy` \case
            Left (CycleError repeated len) -> repeated == node && len == 1
            Right _                        -> False

    it "records distinct hops without complaint" $ do
      let g1 = appendNode (ResolutionNode "ens"  "example.eth" QTA) emptyGraph
          g2 = appendNode (ResolutionNode "ipfs" "example.eth" QTA) g1
      graphDepth g2 `shouldBe` 2
      graphNodes g2 `shouldBe`
        [ ResolutionNode "ens"  "example.eth" QTA
        , ResolutionNode "ipfs" "example.eth" QTA
        ]

    it "distinguishes hops that differ only in query type" $
      detectCycle (appendNode (ResolutionNode "ens" "example.eth" QTA) emptyGraph)
                  (ResolutionNode "ens" "example.eth" QTAAAA)
        `shouldBe` Right
                     (appendNode (ResolutionNode "ens" "example.eth" QTAAAA)
                                 (appendNode (ResolutionNode "ens" "example.eth" QTA) emptyGraph))

  describe "properties" $ do
    it "any delegation chain built by repeated appends is finite" $
      hedgehog prop_chainIsFinite
    it "detectCycle terminates within the number of distinct nodes" $
      hedgehog prop_detectCycleTerminates
    it "a parsed suffix pattern matches a generated name" $
      hedgehog prop_parseMatches
    it "JSON round-trips for ZonePattern" $
      hedgehog prop_zonePatternJson

-- * Properties -------------------------------------------------------------

-- | Building a graph by appends keeps depth equal to the number of appends.
prop_chainIsFinite :: PropertyT IO ()
prop_chainIsFinite = do
  nodes <- forAll $ Gen.list (Range.linear 0 40) genNode
  graphDepth (foldr appendNode emptyGraph nodes) === length nodes

-- | The cycle guard stops at the first repeated node, so a chain over @n@
-- distinct nodes always terminates within @n@ steps (раздел 20.2).
prop_detectCycleTerminates :: PropertyT IO ()
prop_detectCycleTerminates = do
  nodes <- forAll $ Gen.list (Range.linear 1 60) genNode
  let distinct = nub nodes
      chain = take (length nodes) (cycle distinct)
  acceptedSteps emptyGraph chain === length distinct

-- | Count hops 'detectCycle' accepts before rejecting the first repeat.
acceptedSteps :: ResolutionGraph -> [ResolutionNode] -> Int
acceptedSteps _   []     = 0
acceptedSteps g (n : ns) = case detectCycle g n of
  Left _   -> 0
  Right g' -> 1 + acceptedSteps g' ns

prop_parseMatches :: PropertyT IO ()
prop_parseMatches = do
  suffix <- forAll $ Gen.text (Range.linear 1 12) Gen.alphaNum
  name <- forAll $ Gen.text (Range.linear 1 12) Gen.alphaNum
  let full = name <> "." <> suffix
  matchesZone (parseZonePattern ("." <> suffix)) full === True
  matchesZone (parseZonePattern ("." <> suffix)) name === False

prop_zonePatternJson :: PropertyT IO ()
prop_zonePatternJson = do
  suffix <- forAll $ Gen.text (Range.linear 1 12) Gen.alphaNum
  let pat = parseZonePattern ("." <> suffix)
  case fromJSON (toJSON pat) of
    Aeson.Error _   -> failure
    Aeson.Success p -> p === pat

-- * Generators -------------------------------------------------------------

genNode :: Gen ResolutionNode
genNode = ResolutionNode <$> genAdapter <*> genName <*> genQType

genAdapter :: Gen Text
genAdapter = Gen.element ["ens", "ipfs", "hsd", "ncdns", "unbound", "tor"]

genName :: Gen Text
genName = intercalate "." <$> Gen.list (Range.linear 1 4) genLabel
  where
    genLabel = Gen.text (Range.linear 1 8) Gen.lower

genQType :: Gen QType
genQType = Gen.element [QTA, QTAAAA, QTTXT, QTCNAME]
