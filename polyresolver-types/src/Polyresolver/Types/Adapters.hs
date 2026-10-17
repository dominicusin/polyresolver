{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

-- | Adapter identity and naming-model taxonomy (девятикатегорийная, раздел 3).
module Polyresolver.Types.Adapters
  ( AdapterId(..)
  , unAdapterId
  , NamingModel(..)
  , AdapterMeta(..)
  , Priority
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Hashable (Hashable)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Unique identifier of an adapter instance.
--
-- The 'Ord' instance is what lets routing tables be built deterministically,
-- independent of adapter registration order (ТРЕБ-002).
newtype AdapterId = AdapterId { unAdapterId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, ToJSON, FromJSON)

-- | Nine-category taxonomy of naming models (раздел 3 ТЗ).
--
-- Carried on every adapter purely for diagnostics and metrics labelling;
-- it does not alter routing behaviour.
data NamingModel
  = ModelHierarchicalRegistry      -- ^ A: Handshake, Namecoin, EmerDNS, ENS
  | ModelSelfCertifyingAddress     -- ^ B: Tor, I2P, Yggdrasil, cjdns, Reticulum
  | ModelContentAddressed          -- ^ C: IPFS/IPNS, ZeroNet, Hyphanet
  | ModelPetnameLocalRoot          -- ^ D: GNUnet/GNS
  | ModelMeshFlood                 -- ^ E: OLSR, Meshtastic, Serval, Babel
  | ModelDarknetRegistry           -- ^ F: dn42, anoNet
  | ModelReputationFilter          -- ^ G: DNSBL, DRBL
  | ModelTransportOnly             -- ^ H: Lantern (not a resolver)
  | ModelUnidentified              -- ^ I: Calypso (referent unresolved)
  deriving stock (Eq, Ord, Show, Generic, Enum, Bounded)
  deriving anyclass (ToJSON, FromJSON)

-- | Static metadata reported by an adapter.
data AdapterMeta = AdapterMeta
  { adapterId       :: !AdapterId
  , adapterName     :: !Text
  , adapterModel    :: !NamingModel
  , adapterAuthoritative :: !Bool
    -- ^ True for authoritative backends; False for convenience/proxy adapters.
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Explicit routing priority. Lower number wins on a suffix conflict.
type Priority = Int