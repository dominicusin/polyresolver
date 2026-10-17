{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Polyresolver.Types.ClientContext
  ( ClientContext(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

data ClientContext = ClientContext
  { clientView :: !Text
  , clientAddr :: !Text
  } deriving stock (Eq, Show, Generic)
