{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Polyresolver.Types.Zone
  ( ZonePattern(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

data ZonePattern
  = SuffixMatch Text
  | ExactMatch  Text
  | PredicateMatch (Text -> Bool)
  deriving stock (Generic)

instance Eq ZonePattern where
  SuffixMatch a == SuffixMatch b = a == b
  ExactMatch  a == ExactMatch  b = a == b
  PredicateMatch _ == PredicateMatch _ = True
  _ == _ = False

instance Show ZonePattern where
  show (SuffixMatch s) = "SuffixMatch " ++ show s
  show (ExactMatch s)  = "ExactMatch " ++ show s
  show (PredicateMatch _) = "PredicateMatch <func>"
