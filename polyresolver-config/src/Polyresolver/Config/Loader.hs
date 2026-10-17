{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Config.Loader
  ( loadConfig
  , loadConfigWithEnv
  , applyEnvOverrides
  , resolveIncludes
  ) where

import Control.Exception (try, SomeException)
import Control.Monad (when)
import Data.Aeson (FromJSON, eitherDecode)
import qualified Data.Aeson as Aeson
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Yaml (decodeFileEither, encode, object, (.=))
import System.Directory (doesFileExist, listDirectory)
import System.FilePath ((</>), takeExtension)

import Polyresolver.Config.Schema

loadConfig :: FilePath -> IO (Either String Config)
loadConfig path = do
  result <- decodeFileEither path
  case result of
    Left err -> pure (Left (show err))
    Right cfg -> pure (Right cfg)

loadConfigWithEnv :: FilePath -> IO (Either String Config)
loadConfigWithEnv path = do
  result <- loadConfig path
  case result of
    Left err -> pure (Left err)
    Right cfg -> pure (Right (applyEnvOverrides cfg))

applyEnvOverrides :: Config -> Config
applyEnvOverrides cfg = cfg
  { cfgAPI = (cfgAPI cfg) { apiPort = fromMaybe (apiPort (cfgAPI cfg)) (lookupEnvInt "POLYRESOLVER_API_PORT") }
  , cfgMetrics = (cfgMetrics cfg) { mcPort = fromMaybe (mcPort (cfgMetrics cfg)) (lookupEnvInt "POLYRESOLVER_METRICS_PORT") }
  }

lookupEnvInt :: String -> Maybe Int
lookupEnvInt name = do
  val <- lookupEnv name
  readMaybe val

lookupEnv :: String -> Maybe String
lookupEnv name = do
  val <- lookupEnv name
  pure val

readMaybe :: String -> Maybe Int
readMaybe s = case reads s of
  [(n, "")] -> Just n
  _         -> Nothing

resolveIncludes :: FilePath -> IO (Either String Config)
resolveIncludes path = do
  result <- loadConfig path
  case result of
    Left err -> pure (Left err)
    Right cfg -> pure (Right cfg)
