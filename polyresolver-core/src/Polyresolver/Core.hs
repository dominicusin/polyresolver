-- | polyresolver-core: routing, cache, supervisor tree and engine.
module Polyresolver.Core
  ( -- * Routing
    module Polyresolver.Core.Routing
    -- * Cache
  , module Polyresolver.Core.Cache
    -- * Supervision
  , module Polyresolver.Core.Supervisor
    -- * Adapters
  , module Polyresolver.Core.Adapter
    -- * Engine
  , module Polyresolver.Core.Engine
  ) where

import Polyresolver.Core.Routing
import Polyresolver.Core.Cache
import Polyresolver.Core.Supervisor
import Polyresolver.Core.Adapter
import Polyresolver.Core.Engine
