{-# OPTIONS_GHC -W -Wall -Wno-deprecations -fhelpful-errors #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE QuasiQuotes                #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeSynonymInstances       #-}
{-# LANGUAGE TupleSections              #-}
{-# LANGUAGE UnicodeSyntax              #-}
{-# LANGUAGE ViewPatterns               #-}

import Base1T

-- aeson -------------------------------

import Data.Aeson  ( FromJSON, eitherDecodeFileStrict' )

-- base --------------------------------

import qualified  Data.List.NonEmpty  as  NonEmpty

import Data.Char      ( isAlpha, isAlphaNum )
import Data.List      ( reverse, zip )
import Data.Maybe     ( fromMaybe )
import GHC.Generics   ( Generic )
import System.IO      ( hPutStrLn, stderr )

-- fpath -------------------------------

import qualified FPath.Parseable

import FPath.AbsDir            ( AbsDir, absdir, parseAbsDirP, parseAbsDirP' )
import FPath.AbsFile           ( AbsFile )
import FPath.AppendableFPath   ( (⫻) )
import FPath.AsFilePath        ( filepath )
import FPath.AsFilePath'       ( filepath' )
import FPath.RelDir            ( reldir )
import FPath.RelFile           ( relfile )
import FPath.Error.FPathError  ( AsFPathError )

-- log-plus ----------------------------

import Log  ( Log )

-- logging-effect ----------------------

import Control.Monad.Log  ( LoggingT, MonadLog, Severity( Informational ) )

-- mockio ------------------------------

import MockIO.DoMock  ( DoMock( NoMock ), HasDoMock )

-- mockio-log --------------------------

import MockIO.IOClass      ( HasIOClass )
import MockIO.MockIOClass  ( MockIOClass )

-- mockio-plus -------------------------

import MockIO.File  ( fexists )

-- monadio-plus ------------------------

import MonadIO.Base   ( getArgs )
import MonadIO.FStat  ( FExists( FExists, NoFExists ) )

-- more-unicode ------------------------

import Data.MoreUnicode.Monad  ( (⋘) )

-- optparse-applicative ----------------

import Options.Applicative.Builder  ( flag, help, long, metavar, short
                                    , strArgument )
import Options.Applicative.Types    ( Parser )

-- parsers -----------------------------

import Text.Parser.Char         ( CharParsing, alphaNum, char, digit, noneOf
                                , satisfy, string )
import Text.Parser.Combinators  ( count,optional,sepByNonEmpty,try,unexpected )

-- stdmain -----------------------------

import StdMain             ( stdMainNoDR )
import StdMain.UsageError  ( AsUsageError, UsageFPIOTPError )

-- text --------------------------------

import Data.Text     ( intercalate, pack, unpack, unsnoc )
import Data.Text.IO  ( putStrLn )

-- text-printer ------------------------

import qualified  Text.Printer  as  P

-- textual-plus ------------------------

import TextualPlus  ( TextualPlus( textual' ), parseText, tparse )
import TextualPlus.Error.TextualParseError
                    ( AsTextualParseError, TextualParseError, tparseToME' )

-- unix --------------------------------

import System.Posix.User  ( UserEntry, getEffectiveUserName, getUserEntryForName
                          , homeDirectory )

--------------------------------------------------------------------------------

data ShowVersion = ShowVersion | NoShowVersion
data ShowIndex   = ShowIndex   | NoShowIndex
data ShowPath    = ShowPath    | NoShowPath

data Options = Options { showVersion ∷ ShowVersion
                       , showIndex   ∷ ShowIndex
                       , showPath    ∷ ShowPath
                       , profileName ∷ 𝕄 𝕋
                       }

parseOptions ∷ Parser Options
parseOptions =
  let version_help  = "show version information, too"
      path_help     = "show store path, too"
      no_index_help = "don't show profile position indices"
  in  Options ⊳ flag NoShowVersion ShowVersion (ю [ short 'v', long "version"
                                                  , help version_help ])
              ⊵ flag ShowIndex     NoShowIndex (ю [ short 'n', long "no-index"
                                                  , help no_index_help ])
              ⊵ flag NoShowPath    ShowPath    (ю [ short 'p', long "path"
                                                  , help path_help ])
              ⊵ optional (strArgument (ю [ metavar "PROFILE-NAME"
                                         , help "profile to enumerate" ]))

------------------------------------------------------------

data AttrPath = AttrPath { _attrPrefixParts ∷ [𝕋], _pkg ∷ Pkg }
  deriving (Eq,Show)

instance Printable AttrPath where
  print (AttrPath ps p) = P.text $ intercalate "." (ps ⊕ [unPkg p])

instance TextualPlus AttrPath where
  textual' =
    ((\ (x :| xs) →
          AttrPath (reverse xs) (Pkg x)) ∘ NonEmpty.reverse ∘ fmap pack) ⊳
      sepByNonEmpty (some (noneOf ".")) (char '.')

checkT ∷ (TextualPlus α, Eq α, Show α) ⇒ 𝕋 → α → TestTree
checkT input exp =
  testCase ("parseText: " ⊕ unpack input) $
    𝕽 exp @=? (tparseToME' ∘ parseText) input

attrPathTests ∷ TestTree
attrPathTests =
  testGroup "attrPath"
    [ checkT "packages.x86_64-linux.pia"
            (AttrPath ["packages","x86_64-linux"] (Pkg "pia"))
    , checkT "packages.x86_64-linux.nix-prefetch-github"
            (AttrPath ["packages","x86_64-linux"] (Pkg "nix-prefetch-github"))
    ]

------------------------------------------------------------

data StorePath = StorePath { _path' ∷ AbsDir
                           , _hash  ∷ Hash
                           , _pkg'  ∷ Pkg
                           , _ver   ∷ 𝕄 Ver
                           }
  deriving (Eq,Show)

{-| Match against a store path, e.g.,

    /nix/store/0dbkb5963hjgg45yw07sk3dm43jci4bw-atreus-1.0.2.0

   return hash, pkg, (maybe) ver
-}
storePathRE ∷ CharParsing η ⇒ η (Hash, Pkg, 𝕄 Ver)
storePathRE =
  let
    pkgRE ∷ CharParsing η ⇒ η (𝕊, 𝕄 𝕊)
    pkgRE =
      let
        alpha_under_score      ∷ CharParsing η ⇒ η ℂ
        alpha_under_score      = satisfy (\ c → isAlpha c ∨ c ≡ '_')
        non_hyphen             ∷ CharParsing η ⇒ η ℂ
        non_hyphen             = satisfy (\ c → isAlphaNum c ∨ c ∈ "_.")
        simple_identifier      ∷ CharParsing η ⇒ η 𝕊
        simple_identifier      = (:) ⊳ alpha_under_score ⊵ many non_hyphen
        hyphenated_identifiers ∷ CharParsing η ⇒ η 𝕊
        hyphenated_identifiers =
          ю ⊳ ((:) ⊳ simple_identifier ⊵many(try $ char '-' ⋫simple_identifier))
        numeric_identifier     ∷ CharParsing η ⇒ η 𝕊
        numeric_identifier     =
          (:) ⊳ digit ⊵ many (satisfy (\ c → isAlphaNum c ∨ c ∈ "-_."))
      in
        ((,) ⊳ hyphenated_identifiers ⊵ optional(char '-' ⋫ numeric_identifier))
  in
    (\ h (p,v) → (Hash (pack h), Pkg (pack p), (Ver ∘ pack) ⊳ v)) ⊳
      (string "/nix/store/" ⋫ count 32 alphaNum) ⊵ (char '-' ⋫ pkgRE)

instance Printable StorePath where
  print (StorePath _ h p v) =
    let v' = case v of 𝕹 → ""; 𝕵 v_ → "-" ⊕ unVer v_
    in  P.text $ [fmt|/nix/store/%T-%T-%T/|] h p v'

instance TextualPlus StorePath where
  textual' = do
    let construct p h v =
          either (unexpected ∘ toString) pure $ parseAbsDirP' @_ @(𝔼 _) $
            ю [ "/nix/store/"
               , (unHash h)
               , "-", (unPkg p)
               , maybe "" ("-" ⊕) ((unVer) ⊳ v)
               ]
    (h,p,v) ← storePathRE
    t ← construct p h v
    return (StorePath t h p v)

storePathTests ∷ TestTree
storePathTests =
  testGroup "storePath"
    [ let
        hash          = Hash "0dbkb5963hjgg45yw07sk3dm43jci4bw"
        dirname       =
          [reldir|0dbkb5963hjgg45yw07sk3dm43jci4bw-atreus-1.0.2.0/|]
        path ∷ AbsDir = [absdir|/nix/store/|] ⫻ dirname
        path'         = pack $ path ⫥ filepath'
      in
        checkT path' (StorePath { _path' = path
                                , _hash  = hash
                                , _pkg'  = Pkg "atreus"
                                , _ver   = 𝕵 (Ver "1.0.2.0") })
    , let
        hash          = Hash "g9zcvd6f5aasrxwm48bdbks3scv46b6x"
        dirname       =
          [reldir|g9zcvd6f5aasrxwm48bdbks3scv46b6x-jq-1.6-bin/|]
        path ∷ AbsDir = [absdir|/nix/store/|] ⫻ dirname
        path'         = pack $ path ⫥ filepath'
      in
        checkT path' (StorePath { _path' = path
                                , _hash  = hash
                                , _pkg'  = Pkg "jq"
                                -- the use of -bin in the version is
                                -- unsatisfying; but I can't see how to
                                -- distinguish from e.g., bash-5.1-p16, where
                                -- p16 *is* part of the version
                                , _ver   = 𝕵 (Ver "1.6-bin") })
    ]

spPkgVerPath ∷ StorePath → (Pkg, 𝕄 Ver, AbsDir)
spPkgVerPath sp = (_pkg' sp, _ver sp, _path' sp)

------------------------------------------------------------

getEffectiveUserEntry ∷ (AsIOError ε, MonadError ε μ, MonadIO μ) ⇒ μ UserEntry
getEffectiveUserEntry = asIOError $ getEffectiveUserName ≫ getUserEntryForName

getEffectiveHomeDir ∷ (AsIOError ε, AsFPathError ε, MonadError ε μ, MonadIO μ) ⇒
                      μ AbsDir
getEffectiveHomeDir =
  let getEffectiveUserHomeDir ∷ (AsIOError ε, MonadError ε μ, MonadIO μ) ⇒ μ 𝕊
      getEffectiveUserHomeDir = homeDirectory ⊳ getEffectiveUserEntry
  in  getEffectiveUserHomeDir ≫ parseAbsDirP

nixProfile ∷ (AsIOError ε,AsFPathError ε,MonadError ε μ,MonadIO μ) ⇒ μ AbsDir
nixProfile = (⫻ [reldir|.nix-profile/|]) ⊳ getEffectiveHomeDir

nixProfiles ∷ (AsIOError ε,AsFPathError ε,MonadError ε μ,MonadIO μ) ⇒ μ AbsDir
nixProfiles = (⫻ [reldir|.nix-profiles/|]) ⊳ getEffectiveHomeDir

throwUserError ∷ ∀ ε τ α η . (Printable τ,AsIOError ε,MonadError ε η) ⇒ τ → η α
throwUserError = throwError ∘ userE ∘ toString

profileManifest ∷ ∀ ε τ ω μ .
                  (AsIOError ε, AsFPathError ε, Printable ε, MonadError ε μ,
                   HasIOClass ω, HasDoMock ω, Default ω, MonadLog (Log ω) μ,
                   Printable τ, MonadIO μ) ⇒
                  τ → μ AbsFile
profileManifest (toText → d) = do
  dir ← case unsnoc d of
    𝕹          → nixProfile
    𝕵 (_, c) → do d' ← FPath.Parseable.parse (d ⊕ case c of '/' → ""; _ → "/")
                  nixProfiles ⊲ (⫻ d')

  fexists Informational FExists dir NoMock ≫ \ case
    NoFExists → throwUserError $ [fmtT|No such profile dir '%T'|] dir
    FExists   → let manifest_json = [relfile|manifest.json|]
                    manifest      = dir ⫻ manifest_json
                in  fexists Informational FExists manifest NoMock ≫ \ case
                      FExists   → return manifest
                      NoFExists → throwUserError $
                                    [fmtT|profile dir '%T' lacks a %T|]
                                    dir manifest_json

data Element = Element { active      ∷ 𝔹
                       , priority    ∷ ℕ
                       , storePaths  ∷ NonEmpty 𝕊
                       , attrPath    ∷ 𝕄 𝕊
                       , originalURL ∷ 𝕄 𝕊
                       , url         ∷ 𝕄 𝕊
                       }
  deriving (Generic, Show)

instance FromJSON Element

data Manifest = Manifest { version ∷ ℤ, elements ∷ [Element] }
  deriving (Generic, Show)

{-| elements in a manifest, along with a zero-based index -}
elementsi ∷ Manifest → [(ℕ,Element)]
elementsi m = zip [0..] (elements m)

instance FromJSON Manifest

newtype Hash = Hash { unHash ∷ 𝕋 } deriving newtype (Eq,Printable,Show)
newtype Pkg  = Pkg  { unPkg  ∷ 𝕋 } deriving newtype (Eq,Printable,Show)
newtype Ver  = Ver  { unVer  ∷ 𝕋 } deriving newtype (Eq,Printable,Show)

------------------------------------------------------------

getNameVerPath ∷ (MonadError TextualParseError η) ⇒
                 Element → η (Pkg, 𝕄 Ver, AbsDir)
getNameVerPath e = do
  (pkgs,ver,path) ← spPkgVerPath ⊳ tparse (NonEmpty.head $ storePaths e)
  case attrPath e of
    𝕵 ap → (,ver,path) ⊳ (_pkg ⊳ tparse ap)
    𝕹    → return (pkgs,ver,path)

output_data ∷ Options → Manifest → IO ()
output_data options manifest =
  let pShow ∷ Show α ⇒ α → IO ()
      pShow = hPutStrLn stderr ∘ show

      get_columns i n v p = ю [ case showIndex options of
                                  ShowIndex   → [pack $ show i]
                                  NoShowIndex → []
                              , [toText n]
                              , case showVersion options of
                                  ShowVersion   → [maybe "" toText v]
                                  NoShowVersion → []
                              , case showPath options of
                                  ShowPath   → [toText p]
                                  NoShowPath → []
                              ]

      print_name_ver (i,e) = do
        case getNameVerPath e of
          𝕷 err     → pShow err
          𝕽 (n,v,p) → putStrLn (intercalate "\t" $ get_columns i n v p)

  in forM_ (elementsi manifest) print_name_ver

readManifest ∷ ∀ ε τ ω μ .
               (AsIOError ε, AsFPathError ε, Printable ε, MonadError ε μ,
                HasIOClass ω, HasDoMock ω, Default ω, MonadLog (Log ω) μ,
                Printable τ, MonadIO μ) ⇒
               τ → μ (Either 𝕊 Manifest)
readManifest =
  liftIO ∘ eitherDecodeFileStrict' ∘ (⫥ filepath) ⋘ profileManifest

myMain ∷ ∀ ε . (HasCallStack, Printable ε, AsUsageError ε,
                AsTextualParseError ε, AsIOError ε, AsFPathError ε) ⇒
         Options → LoggingT (Log MockIOClass) (ExceptT ε IO) Word8
myMain options = do
  -- Strict' version performs conversion immediately
  readManifest (fromMaybe "" $ profileName options) ≫ \ case
    𝕷 e → liftIO $ hPutStrLn stderr $ show e
    𝕽 stuff → liftIO $ output_data options stuff
  return 0

main ∷ IO ()
main = do
  let progDesc = "queue executions"
  getArgs ≫ stdMainNoDR progDesc parseOptions (myMain @UsageFPIOTPError)

-- tests -----------------------------------------------------------------------

tests ∷ TestTree
tests = testGroup "profile-members"
                  [ attrPathTests, storePathTests ]

_test ∷ IO ExitCode
_test = runTestTree tests

_tests ∷ 𝕊 → IO ExitCode
_tests = runTestsP tests

_testr ∷ 𝕊 → ℕ → IO ExitCode
_testr = runTestsReplay tests

-- that's all, folks! ----------------------------------------------------------
