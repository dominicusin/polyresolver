{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Polyresolver.Types.Health
  ( HealthStatus(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

data HealthStatus
  = Healthy
  | Degraded Text
  | Unhealthy Text
  deriving stock (Eq, Show, Generic)
