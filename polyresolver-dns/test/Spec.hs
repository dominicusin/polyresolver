{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, DerivingStrategies, StandaloneDeriving, TypeApplications, QuasiQuotes, TemplateHaskellQuotes #-}

module Main (main) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Word (Word8, Word16)
import Data.List.NonEmpty (NonEmpty(..))
import Data.Bits ((.&.), shiftR)

import Control.Exception (evaluate)
import Test.Hspec
import Polyresolver.DNS.Codec
import qualified Data.List.NonEmpty as NE

main :: IO ()
main = hspec $ do
  describe "DNS Header" $ do
    it "encodes a basic header" $ do
      let hdr = DNSHeader 0x1234 0x0100 1 0 0 0
      encodeHeader hdr `shouldBe` BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]

    it "decodes a basic header" $ do
      let bs = BS.pack [0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
      decodeHeader bs `shouldBe` Right (DNSHeader 0x1234 0x0100 1 0 0 0)

    it "round-trips header" $ do
      let hdr = DNSHeader 0xABCD 0x8180 1 2 3 4
      decodeHeader (encodeHeader hdr) `shouldBe` Right hdr

  describe "DNS Name" $ do
    it "encodes a simple name" $ do
      encodeName "example.com" `shouldBe` BS.pack [7] <> "example" <> BS.pack [3] <> "com" <> BS.pack [0]

    it "decodes a simple name" $ do
      let bs = BS.pack [7] <> "example" <> BS.pack [3] <> "com" <> BS.pack [0]
      decodeName bs 0 `shouldBe` Right ("example.com", 13)

    it "round-trips a name" $ do
      let name = "test.example.org"
      let enc = encodeName name
      fst <$> decodeName enc 0 `shouldBe` Right name

  describe "DNS Question" $ do
    it "encodes a question" $ do
      let q = DNSQuestion "example.com" 1 1  -- A, IN
      encodeQuestion q `shouldBe` encodeName "example.com" <> BS.pack [0x00, 0x01, 0x00, 0x01]

    it "decodes a question" $ do
      let bs = encodeName "example.com" <> BS.pack [0x00, 0x01, 0x00, 0x01]
      decodeQuestion bs 0 `shouldBe` Right (DNSQuestion "example.com" 1 1, BS.length bs)

  describe "DNS Message" $ do
    it "round-trips a complete message" $ do
      let msg = DNSMessage
            { msgHeader = DNSHeader 0x1234 0x8180 1 1 0 0
            , msgQuestions = (DNSQuestion "example.com" 1 1 :| [])
            , msgAnswers = [ DNSResourceRecord "example.com" 1 1 300 (BS.pack [192,0,2,1]) ]
            , msgAuthority = []
            , msgAdditional = []
            }
      decodeMessage (encodeMessage msg) `shouldBe` Right msg

    it "round-trips a message with multiple questions" $ do
      let msg = DNSMessage
            { msgHeader = DNSHeader 0x5678 0x0100 2 0 0 0
            , msgQuestions = ( DNSQuestion "a.com" 1 1 :| [DNSQuestion "b.org" 28 1] )
            , msgAnswers = []
            , msgAuthority = []
            , msgAdditional = []
            }
      decodeMessage (encodeMessage msg) `shouldBe` Right msg

  describe "Name decoding" $ do
    it "handles names with compression pointers" $ do
      -- Manually crafted message with compression:
      -- First name: www.example.com (full)
      -- Second name: mail.example.com (pointer to "example.com" at offset 12)
      let bs = BS.pack
            [ 0x00, 0x01, 0x01, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00  -- header
            , 0x03, 0x77, 0x77, 0x77, 0x07, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x03, 0x63, 0x6F, 0x6D, 0x00  -- www.example.com
            , 0x00, 0x01, 0x00, 0x01  -- type A, class IN
            , 0x04, 0x6D, 0x61, 0x69, 0x6C, 0xC0, 0x10  -- mail + pointer to offset 16 (example.com)
            , 0x00, 0x01, 0x00, 0x01  -- type A, class IN
            ]
      decoded <- evaluate $ decodeMessage bs
      case decoded of
        Left err -> expectationFailure (T.unpack err)
        Right msg' -> map qName (NE.toList (msgQuestions msg')) `shouldBe` ["www.example.com", "mail.example.com"]
