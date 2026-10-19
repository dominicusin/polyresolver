{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeApplications #-}

module Polyresolver.API
  ( APIConfig(..)
  , runAPI
  , PolyresolverAPI
  ) where

import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)
import qualified Data.Text as T
import Network.Wai.Handler.Warp (run)
import Network.Wai (responseLBS)
import Network.HTTP.Types (status200)
import Servant
import Polyresolver.Core.Engine (Engine, resolve, engineAdapters, engineStats, EngineStats(..))
import Polyresolver.Types.Request (ResolveRequest(..), newResolveRequest, ClientContext(..))
import Polyresolver.Types.QType (QType(..))
import Polyresolver.Types.Graph (ResolutionGraph(..))
import Polyresolver.Types.Result (ResolveResult(..))
import Polyresolver.Types.Errors (ResolveError(..))
import Polyresolver.Types.Result (HealthStatus(..))
import Data.Time (getCurrentTime)
import Data.Aeson (ToJSON(..), FromJSON(..), Value(..), object, (.=), withText)
import GHC.Generics (Generic)

-- HealthStatus JSON instances are in Polyresolver.Types.Result

data APIConfig = APIConfig
  { acAddress :: !Text
  , acPort    :: !Int
  } deriving stock (Eq, Show)

type PolyresolverAPI =
       "v1" :> "resolve" :> Capture "name" Text :> QueryParam "type" Text :> Get '[JSON] ResolveResponse
  :<|> "v1" :> "resolve" :> Capture "name" Text :> "graph" :> Get '[JSON] ResolutionGraph
  :<|> "v1" :> "cache" :> Get '[JSON] CacheStats
  :<|> "v1" :> "cache" :> Capture "name" Text :> DeleteNoContent
  :<|> "v1" :> "adapters" :> Get '[JSON] [AdapterStatus]
  :<|> "v1" :> "adapters" :> Capture "name" Text :> "health" :> Get '[JSON] HealthStatus
  :<|> "v1" :> "adapters" :> Capture "name" Text :> "reload" :> PostNoContent
  :<|> "healthz" :> Get '[JSON] NoContent
  :<|> "metrics" :> Raw

data ResolveResponse = ResolveResponse
  { rrStatus  :: !Text
  , rrData    :: !(Maybe Text)
  , rrGraph   :: !(Maybe ResolutionGraph)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data CacheStats = CacheStats
  { csSize    :: !Int
  , csHits    :: !Int
  , csMisses  :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data AdapterStatus = AdapterStatus
  { asName    :: !Text
  , asHealth  :: !HealthStatus
  , asZones   :: ![Text]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

runAPI :: Engine -> APIConfig -> IO ()
runAPI engine config = do
  let port = acPort config
  run port (serve (Proxy @PolyresolverAPI) (server engine))

server :: Engine -> Server PolyresolverAPI
server engine =
  resolveHandler engine :<|>
  graphHandler engine :<|>
  cacheHandler engine :<|>
  invalidateCacheHandler :<|>
  adaptersHandler engine :<|>
  adapterHealthHandler engine :<|>
  adapterReloadHandler :<|>
  healthzHandler :<|>
  metricsHandler

resolveHandler :: Engine -> Text -> Maybe Text -> Handler ResolveResponse
resolveHandler engine name mtype = do
  let qtype = maybe QTA parseQType mtype
  now <- liftIO getCurrentTime
  let req = newResolveRequest name qtype (Polyresolver.Types.Request.ClientContext "default" "127.0.0.1" "api") now
  result <- liftIO (resolve engine req)
  case result of
    Right (Classic rrs) -> pure $ ResolveResponse "classic" (Just (T.pack (show rrs))) Nothing
    Right (Structured sr) -> pure $ ResolveResponse "structured" (Just (T.pack (show sr))) Nothing
    Right (Delegate dt) -> pure $ ResolveResponse "delegate" (Just (T.pack (show dt))) Nothing
    Right NotFound -> pure $ ResolveResponse "notfound" Nothing Nothing
    Left err -> pure $ ResolveResponse "error" (Just (T.pack (show err))) Nothing

graphHandler :: Engine -> Text -> Handler ResolutionGraph
graphHandler engine name = do
  now <- liftIO getCurrentTime
  let req = newResolveRequest name QTA (Polyresolver.Types.Request.ClientContext "default" "127.0.0.1" "api") now
  result <- liftIO (resolve engine req)
  case result of
    Right _ -> pure (ResolutionGraph mempty)
    Left _ -> pure (ResolutionGraph mempty)

cacheHandler :: Engine -> Handler CacheStats
cacheHandler engine = do
  stats <- liftIO (engineStats engine)
  pure $ CacheStats 0 (statsCacheHits stats) 0

invalidateCacheHandler :: Text -> Handler NoContent
invalidateCacheHandler name = pure NoContent

adaptersHandler :: Engine -> Handler [AdapterStatus]
adaptersHandler engine = do
  names <- liftIO (engineAdapters engine)
  mapM (\n -> pure $ AdapterStatus n Healthy []) names

adapterHealthHandler :: Engine -> Text -> Handler HealthStatus
adapterHealthHandler engine name = pure Healthy

adapterReloadHandler :: Text -> Handler NoContent
adapterReloadHandler name = pure NoContent

healthzHandler :: Handler NoContent
healthzHandler = pure NoContent

metricsHandler :: Server Raw
metricsHandler = Tagged metricsApp

metricsApp :: Application
metricsApp = \req send -> send $ responseLBS status200 [] "Prometheus metrics"

parseQType :: Text -> QType
parseQType "A" = QTA
parseQType "AAAA" = QTAAAA
parseQType "TXT" = QTTXT
parseQType "CNAME" = QTCNAME
parseQType "MX" = QTMX
parseQType "SRV" = QTSRV
parseQType _ = QTRaw 0
