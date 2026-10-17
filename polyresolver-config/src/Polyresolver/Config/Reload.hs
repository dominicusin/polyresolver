{-# LANGUAGE OverloadedStrings #-}

module Polyresolver.Config.Reload
  ( watchConfig
  , reloadConfig
  , ConfigWatcher
  , startConfigWatcher
  , stopConfigWatcher
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (TVar, atomically, readTVar, writeTVar)
import Control.Exception (try, SomeException)
import Control.Monad (forever, when)
import Data.Text (Text)
import System.Directory (getModificationTime)

import Polyresolver.Config.Loader
import Polyresolver.Config.Schema

data ConfigWatcher = ConfigWatcher
  { cwPath    :: FilePath
  , cwConfig  :: TVar (Either String Config)
  , cwRunning :: TVar Bool
  }

watchConfig :: FilePath -> Int -> (Either String Config -> IO ()) -> IO ()
watchConfig path interval callback = do
  result <- loadConfig path
  callback result
  forever $ do
    threadDelay (interval * 1000000)
    result' <- loadConfig path
    callback result'

reloadConfig :: FilePath -> IO (Either String Config)
reloadConfig = loadConfig

startConfigWatcher :: FilePath -> Int -> IO ConfigWatcher
startConfigWatcher path interval = do
  result <- loadConfig path
  configVar <- newTVarIO result
  runningVar <- newTVarIO True
  let watcher = ConfigWatcher path configVar runningVar
  _ <- forkIO $ watchConfig path interval (\result -> atomically $ writeTVar configVar result)
  pure watcher

stopConfigWatcher :: ConfigWatcher -> IO ()
stopConfigWatcher watcher = atomically $ writeTVar (cwRunning watcher) False

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (newTVarIO)
