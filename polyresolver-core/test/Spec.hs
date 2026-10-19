{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec

import Polyresolver.Core.Engine
import Polyresolver.Core.Cache (CacheOptions(..), defaultCacheOptions, newCache, lookupCache, insertCache)
import Polyresolver.Core.Routing
import Polyresolver.Core.Adapter
import Polyresolver.Types.Adapters (AdapterId (..), Priority)
import Polyresolver.Types.Request (ResolveRequest (..), newResolveRequest)
import Polyresolver.Types.Request (ClientContext (..))
import Polyresolver.Types.Cache (CacheKey (..))
import Polyresolver.Types.Result (ResolveResult (..))
import Polyresolver.Types.Errors (ResolveError (..))
import Polyresolver.Types.QType (QType (..))
import Polyresolver.Types.Graph (ResolutionGraph (..))
import Polyresolver.Types.Namespace (ZonePattern (..))
import Polyresolver.Types.Result (HealthStatus (..))
import Data.Time (getCurrentTime)

main :: IO ()
main = hspec $ do
  describe "Engine" $ do
    it "creates an engine with no adapters" $ do
      cache <- newCache defaultCacheOptions
      eng <- newEngine cache []
      case eng of
        Left err -> expectationFailure ("unexpected error: " ++ show err)
        Right e -> do
          adapters <- engineAdapters e
          adapters `shouldBe` []

    it "resolves NotFound for unknown zone" $ do
      cache <- newCache defaultCacheOptions
      eng <- newEngine cache []
      case eng of
        Left err -> expectationFailure ("unexpected error: " ++ show err)
        Right e -> do
          now <- getCurrentTime
          let req = newResolveRequest "example.com" QTA defaultClientCtx now
          result <- resolve e req
          result `shouldBe` (Right NotFound :: Either Polyresolver.Types.Errors.ResolveError ResolveResult)

  describe "Routing" $ do
    it "builds a table with explicit conflict policy" $ do
      let routes = [ Route (AdapterId "hsd") (SuffixMatch ".hns") 10
                   , Route (AdapterId "ncdns") (SuffixMatch ".bit") 10
                   ]
      case buildTable Explicit routes of
        Left err -> expectationFailure ("unexpected error: " ++ show err)
        Right table -> do
          lookupRoute "example.hns" table `shouldBe` RouteTo (AdapterId "hsd")
          lookupRoute "example.bit" table `shouldBe` RouteTo (AdapterId "ncdns")
          lookupRoute "example.com" table `shouldBe` NoRoute

  describe "Cache" $ do
    it "stores and retrieves a value" $ do
      cache <- newCache defaultCacheOptions
      let key = CacheKey "example.com" QTA (AdapterId "test")
      let val = NotFound
      insertCache cache key val
      cached <- lookupCache cache key
      cached `shouldBe` Just val

    it "returns Nothing for missing key" $ do
      cache <- newCache defaultCacheOptions
      let key = CacheKey "missing.com" QTA (AdapterId "test")
      cached <- lookupCache cache key
      cached `shouldBe` Nothing

defaultClientCtx :: ClientContext
defaultClientCtx = ClientContext
  { ctxPeerAddr = "127.0.0.1"
  , ctxView      = "default"
  , ctxRequestId = "test"
  }
