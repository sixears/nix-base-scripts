-- cannot do this
-- #!/home/martyn/.nix-profile/bin/runghc -Wall
-- because runghc pollutes the path

-- we deliberately eschew the processing of relative paths, that's a cause of
-- mayhem.  we definitely want to document that.

-- known issues:
--   -) doesn't print out paths with, e.g., spaces in them such that bash can
--      read them back
--   -) gives a warning of an empty MANPATH as in InvalidAbsDir; but maybe
--      we shouldn't (we do the same for PATH, but I think that's right;
--      empty PATH means '.', which is relative and so evil
--   -) code is a bit of a mess
--   -) we need documentation for all the types, and all the functions, and
--      user help
--   -) we need property tests for all the interesting modes (but I don't
--      really want to test `nub`, that seems a bit redundant)

{-# OPTIONS_GHC -Wall #-}

{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE OverloadedStrings      #-}
{-# LANGUAGE QuasiQuotes            #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE ViewPatterns           #-}
{-# LANGUAGE UnicodeSyntax          #-}

import Prelude ( )

-- base --------------------------------

import qualified  System.Environment

import Control.Applicative  ( (<*>), (<**>), (<|>), pure, some )
import Control.Monad        ( (>>), filterM, forM, forM_, return, when )
import Data.Bifunctor       ( bimap, first, second )
import Data.Bool            ( Bool( False, True ), (||), not )
import Data.Either          ( Either( Left, Right ) )
import Data.Eq              ( Eq, (==), (/=) )
import Data.Foldable        ( Foldable, all, concatMap, foldl, foldl1 )
import Data.Function        ( (.), ($) )
import Data.Functor         ( (<$>), fmap )
import Data.List            ( drop, filter, intercalate, length, lookup, notElem
                            , nub, null, repeat, reverse, takeWhile, zip
                            , zipWith3
                            )
import Data.Maybe           ( Maybe( Just, Nothing ), fromMaybe, isJust )
import Data.Monoid          ( (<>), mconcat, mempty )
import Data.Ord             ( (>) )
import Data.String          ( String )
import Data.Tuple           ( fst, snd, uncurry )
import GHC.Exts             ( IsList( Item, fromList, toList ) )
import Numeric.Natural      ( Natural )
import System.Exit          ( die, exitSuccess )
import System.IO            ( IO, hPutStrLn, putStrLn, stderr )
import Text.Show            ( Show( show ) )

-- base-unicode-symbols ----------------

-- import Data.Function.Unicode ( (∘) )

-- directory ---------------------------

import System.Directory  ( doesDirectoryExist )

-- optparse-applicative ----------------

import Options.Applicative.Builder            ( ArgumentFields, Mod
                                              , argument, command, completer
                                              , failureCode, flag, fullDesc
                                              , help, info, long, maybeReader
                                              , metavar, prefs, progDesc, short
                                              , showHelpOnEmpty, showHelpOnError
                                              , subparser
                                              )
import Options.Applicative.Builder.Completer  ( bashCompleter )
import Options.Applicative.Extra              ( customExecParser, helper )
import Options.Applicative.Types              ( Parser, ParserInfo )

-- path --------------------------------

import Path  ( Abs, Dir, Path, (</>)
             , absdir, isProperPrefixOf, parseAbsDir, reldir, toFilePath )

-- process -----------------------------

import System.Process.Internals   ( translate )

-- QuickCheck --------------------------

import Test.QuickCheck.Gen  ( elements, listOf )

-- split -------------------------------

import Data.List.Split  ( splitOn )

-- tasty -------------------------------

import Test.Tasty              ( TestTree, defaultIngredients, testGroup )
import Test.Tasty.Ingredients  ( tryIngredients )

-- tasty-hunit -------------------------

import Test.Tasty.HUnit  ( (@?=)
                         , assertBool, assertEqual, assertFailure, testCase )

-- tasty-quickcheck --------------------

import Test.Tasty.QuickCheck  ( Arbitrary( arbitrary, shrink ), testProperty )

--------------------------------------------------------------------------------

------------------------------------------------------------
--                      general types                     --
------------------------------------------------------------

type AbsDir = Path Abs Dir

type EnvKey              = String

newtype Environment      = Environment { unEnv :: [(EnvKey, String)] }
  deriving Show

instance IsList Environment where
  type Item Environment = (EnvKey, String)
  fromList = Environment
  toList = unEnv

type PathElem            = AbsDir
type PathList            = [PathElem]
type Err                 = String
type Errs                = [Err]

lookupEnv :: EnvKey -> Environment -> Maybe String
lookupEnv k = lookup k . toList

lookupEnv' :: EnvKey -> Environment -> String
lookupEnv' k = fromMaybe "" . lookupEnv k

------------------------------------------------------------
--                     options types                      --
------------------------------------------------------------

data Clean = Clean | NoClean
  deriving (Eq, Show)

class UnArb α ψ | α -> ψ where
  unArb :: ψ -> α

data Quiet = Quiet | NoQuiet
  deriving (Eq, Show)

data Transformation = ModeAppendPaths       [AbsDir]
                    | ModePrependPaths      [AbsDir]
                    | ModeRemovePaths       [AbsDir]
                    | ModeRemovePrefixDirs  [AbsDir]
                    | ModeIdentity
  deriving Show

data OpMode = ModeTransform Transformation
            | ModeTest
  deriving Show

data Options = Options { mode  :: OpMode
                       , clean :: Clean
                       , quiet :: Quiet
                       }
  deriving Show

------------------------------------------------------------
--                       utilities                        --
------------------------------------------------------------

warn :: String -> IO ()
warn = hPutStrLn stderr

------------------------------------------------------------
--                    options handling                    --
------------------------------------------------------------

bashDirCompleter :: Mod ArgumentFields α
bashDirCompleter = completer (bashCompleter "directory")

type CommandName = String
type CommandDesc = String
type CommandHelp = String

modeHandlers :: [(CommandName, [AbsDir] -> Transformation, CommandDesc, CommandHelp)]
modeHandlers =
  [ ("append"             , ModeAppendPaths     , "append paths"              ,
     "append subdir bin to PATH, etc."                                        )
  , ("prepend"            , ModePrependPaths    , "prepend paths"             ,
     "prepend subdir bin to PATH, etc."                                       )
  , ("remove"             , ModeRemovePaths     , "remove paths"              ,
     "remove subdir bin from PATH, etc."                                      )
  , ("remove-prefix-dirs" , ModeRemovePrefixDirs, "remove prefix directories" ,
     "remove all dirs with given prefix dir from PATH, etc."                  )
  ]

commandmv :: String -> ParserInfo α -> Parser α
commandmv name pinfo = subparser $ command name pinfo <> metavar name

transformationParser :: Parser Transformation
transformationParser =
  let absdirsParser d =
        let mod = metavar "PATHDIR" <> help d <> bashDirCompleter
         in some $ argument (maybeReader parseAbsDir) mod
      mkCmd (n,m,d,h) =
        commandmv n (info (m <$> absdirsParser h) (progDesc d))
   in     foldl1 (<|>) (fmap mkCmd modeHandlers)
      <|> commandmv "identity" (info (pure ModeIdentity)(progDesc "do nothing"))

opModeParser :: Parser OpMode
opModeParser =  commandmv "test" (info (pure ModeTest) (progDesc "run tests"))
            <|> (ModeTransform <$> transformationParser)

parseOpts :: Parser Options
parseOpts = let cleanHelp = help "remove duplicate & non-existing dirs"
                quietHelp = help "don't warn of ignored bad dirs in extant paths"
                cleanParser = flag NoClean Clean
                                   (short 'C' <> long "clean" <> cleanHelp)
                quietParser = flag NoQuiet Quiet
                                   (short 'q' <> long "quiet" <> quietHelp)
             in Options <$> opModeParser <*> cleanParser <*> quietParser

------------------------------------------------------------

cleanPath :: Options -> PathList -> IO PathList
-- we use doesDirectoryExist here, files are no use in the PATH
cleanPath (clean -> Clean) = filterM (doesDirectoryExist . toFilePath) . nub
cleanPath _                = return

printPath :: Options -> EnvKey -> PathList -> IO ()
printPath o k p = do p' <- cleanPath o p
                     putStrLn $ k <> "=" <> intercalate ":" (translate . toFilePath <$> p')

bindirs :: Foldable φ => φ PathElem -> PathList
bindirs = concatMap (\d -> [ d </> [reldir|bin|] ])

manpaths :: Foldable φ => φ PathElem -> PathList
manpaths = concatMap (\d -> [ d </> [reldir|man|]
                            , d </> [reldir|share/man|] ])

----------------------------------------

transformationHandler :: Transformation -> PathEnv -> PathEnv

transformationHandler ModeIdentity pe = pe

transformationHandler (ModeAppendPaths ds) pe =
  PathEnv { _PATH    = first (<> bindirs  ds) (_PATH    pe)
          , _MANPATH = first (<> manpaths ds) (_MANPATH pe) }

transformationHandler (ModePrependPaths ds) pe =
  PathEnv { _PATH    = first (bindirs  ds <>) (_PATH    pe)
          , _MANPATH = first (manpaths ds <>) (_MANPATH pe) }

transformationHandler (ModeRemovePaths ds) pe =
  PathEnv { _PATH    = first (filter (`notElem` bindirs  ds)) (_PATH    pe)
          , _MANPATH = first (filter (`notElem` manpaths ds)) (_MANPATH pe) }

transformationHandler (ModeRemovePrefixDirs ds) pe =
  let filterPrefixDirs = filter (\ x -> all (not . (`isProperPrefixOf` x)) ds)
   in PathEnv { _PATH    = first filterPrefixDirs (_PATH    pe)
              , _MANPATH = first filterPrefixDirs (_MANPATH pe) }

----------------------------------------

readPathAccum :: (PathList, Errs) -> String -> (PathList, Errs)
readPathAccum (ps,es) p = case readPathElem p of
                            Left  e -> (ps, e : es)
                            Right d -> (d : ps, es)

----------------------------------------

readPathElem :: String -> Either Err AbsDir
readPathElem = first show . parseAbsDir

----------------------------------------

readPathList :: String -> (PathList, Errs)
readPathList = first reverse <$> foldl readPathAccum ([],[]) . splitOn ":"

----------------------------------------

class Compare α where
  compare :: α -> α -> [String]

cmpeq :: (Show α, Eq α) => α -> α -> [String]
cmpeq got exp = if got == exp
                then []
                else [ "got " <> show got <> "; expected " <> show exp ]

instance Compare (Path Abs Dir) where
  compare = cmpeq

instance (Compare α, Show α) => Compare [α] where
  -- extend with nulls, trim the all nulls
  compare got exp = let notBothNothing :: (Maybe β,Maybe γ) -> Bool
                        notBothNothing (x,y) = isJust x || isJust y
                        extend :: [β] -> [Maybe β]
                        extend zs = (Just <$> zs) <> repeat Nothing
                        -- zip two lists, but instead of zipping to the min
                        -- of the two lengths; zip to the max of the two
                        -- lengths, filling out with Nothings
                        zipPlus :: [β] -> [γ] -> [(Maybe β, Maybe γ)]
                        zipPlus xs ys = takeWhile notBothNothing $
                                            zip (extend xs) (extend ys)
                        cmp :: (Compare β, Show β) =>
                               (Maybe β, Maybe β) -> [String]
                        cmp (Just g , Just e)  = compare g e
                        cmp (Just g , Nothing) = ["got '" <> show g <> "'"]
                        cmp (Nothing, Just e)  = ["expected '" <> show e <> "'"]
                        cmp (Nothing,Nothing)  = ["OOPS"]
                     in mconcat $ cmp <$> zipPlus got exp

-- | the paths that we're actually interested in, along with any cleanup errors
data PathEnv = PathEnv { _PATH    :: (PathList, Errs)
                       , _MANPATH :: (PathList, Errs)
                       }
  deriving (Eq, Show)

instance Compare PathEnv where
  compare a b = mconcat [ compare (fst $ _PATH a) (fst $ _PATH b) ]

instance IsList PathEnv where
  type Item PathEnv = (EnvKey, (PathList, Errs))
  fromList l = PathEnv { _PATH    = fromMaybe ([],[]) $ lookup "PATH" l
                       , _MANPATH = fromMaybe ([],[]) $ lookup "MANPATH" l
                       }


  toList pe  = [ ("PATH", _PATH pe) , ("MANPATH", _MANPATH pe) ]

----------------------------------------

initPaths :: Environment -> PathEnv
initPaths env = PathEnv { _PATH    = readPathList (lookupEnv' "PATH"    env)
                        , _MANPATH = readPathList (lookupEnv' "MANPATH" env)
                        }

mkPaths :: Transformation -> Environment -> PathEnv
mkPaths trans env = transformationHandler trans (initPaths env)

----------------------------------------

warnPathError :: EnvKey -> Errs -> IO ()
warnPathError k es = when (not $ null es) $
                   warn (k <> ":") >> forM_ es (warn . ("  " <>))

------------------------------------------------------------

getEnvironment :: IO Environment
getEnvironment = Environment <$> System.Environment.getEnvironment

main :: IO()
main = do
  let execParser p d =
        customExecParser (prefs $ showHelpOnError <> showHelpOnEmpty)
                         (info (p <**> helper)
                               (fullDesc <> failureCode 2 <> progDesc d))

  opts <- let desc = "manipulate PATH, MANPATH, etc."
           in execParser parseOpts desc
  env <- getEnvironment

  case mode opts of
    ModeTest        -> test
    ModeTransform t -> do let newPaths' = mkPaths t env
                          when (quiet opts /= Quiet)
                               (forM_ (second snd <$> toList newPaths')
                                      (uncurry warnPathError))
                          forM_ (second fst <$> toList newPaths')
                                (uncurry (printPath opts))

------------------------------------------------------------
--                       unit tests                       --
------------------------------------------------------------

-- | compare two lists for equality, with itemized testing
assertListEq :: (Eq a, Show a) => String -> [a] -> [a] -> [TestTree]
assertListEq name got expect =
  let lCheck g e = let msg = name <> " length (exp " <> show e <> ", got "
                                  <> show g <> ")"
                    in assertBool msg (e == g)
      lengthCheck g e = lCheck (length g) (length e)
      assertItem gt exp i = let nm = name <> ": " <> show i
                             in testCase nm $ assertEqual (show i) gt exp
      showExtra n d xs =
        let showItem (v,i) = testCase (n<>" "<>show i) $ assertFailure (show v)
         in fmap showItem (drop d (zip xs [(0 :: Natural)..]))
   in    testCase (name <> ": count") (lengthCheck got expect)
       : zipWith3 assertItem got expect [(0 :: Natural)..]
      <> if length got > length expect
         then showExtra "got" (length expect) got
         else showExtra "expect" (length got) expect


unitTests :: TestTree
unitTests = testGroup "unit tests" [ mkPathsUnitTests, readPathListTests ]

readPathListTests :: TestTree
readPathListTests = testGroup "readPathList"
  [ testCase "empty list" $ readPathList "" @?= ([],["InvalidAbsDir \"\""])
  , testCase "/foo" $ readPathList "/foo" @?= ([[absdir|/foo/|]],[])
  , testCase "bar" $ readPathList "bar" @?= ([],["InvalidAbsDir \"bar\""])
  ]

mkPathsUnitTests :: TestTree
mkPathsUnitTests = testGroup "mkPaths" $
  let nix_profile     =  [absdir|/home/user/.nix-profile|]
      nix_profile_bin =  [absdir|/home/user/.nix-profile/bin|]
      nix_profile_man =  [absdir|/home/user/.nix-profile/man|]
      nix_profile_share_man =  [absdir|/home/user/.nix-profile/share/man|]

      usr_bin = [absdir|/usr/bin/|]
      usr_man = [absdir|/usr/man/|]

      hyper_local           = [absdir|/opt/hyper local/|]
      hyper_local_bin       = [absdir|/opt/hyper local/bin/|]
      hyper_local_man       = [absdir|/opt/hyper local/man/|]
      hyper_local_share_man = [absdir|/opt/hyper local/share/man/|]

      opt             = [absdir|/opt/|]
      hyper           = [absdir|/opt/hyper/|]

      env :: Environment
      env = Environment [ ("PATH",    "/usr/bin:/opt/hyper local/bin")
                        , ("MANPATH", "/usr/man:/opt/hyper local/share/man:"
                                   <> "/opt/hyper local/man")
                        ]

      cmp' :: String -> PathEnv -> PathEnv -> TestTree
      cmp' n got expected = testGroup n $
        let (pathGot   , pathGotEs)    = _PATH    got
            (pathExp   , pathExpEs)    = _PATH    expected
            (manpathGot, manpathGotEs) = _MANPATH got
            (manpathExp, manpathExpEs) = _MANPATH expected
         in mconcat [ assertListEq "PATH"           pathGot      pathExp
                    , assertListEq "PATH Errors"    pathGotEs    pathExpEs
                    , assertListEq "MANPATH"        manpathGot   manpathExp
                    , assertListEq "MANPATH Errors" manpathGotEs manpathExpEs
                    ]

   in [ cmp' "identity"
             (mkPaths ModeIdentity env)
             (PathEnv ([ usr_bin, hyper_local_bin ], [])
                      ([ usr_man, hyper_local_share_man, hyper_local_man ], []))

      , cmp' "append"
             (mkPaths (ModeAppendPaths [nix_profile]) env)
             (PathEnv ([ usr_bin, hyper_local_bin, nix_profile_bin ], [])
                      ([ usr_man, hyper_local_share_man,hyper_local_man
                       , nix_profile_man, nix_profile_share_man ], []))

      , cmp' "prepend"
             (mkPaths (ModePrependPaths [nix_profile]) env)
             (PathEnv ([ nix_profile_bin, usr_bin, hyper_local_bin ], [])
                      ([ nix_profile_man, nix_profile_share_man
                       , usr_man, hyper_local_share_man,hyper_local_man], []))

      , cmp' "remove"
             (mkPaths (ModeRemovePaths [hyper_local]) env)
             (PathEnv ([ usr_bin ], []) ([ usr_man ], []))

      , cmp' "remove unused prefix (/opt/hyper/)"
             (mkPaths (ModeRemovePrefixDirs [hyper]) env)
             (PathEnv ([ usr_bin, hyper_local_bin ], [])
                      ([ usr_man, hyper_local_share_man, hyper_local_man ], []))

      , cmp' "remove used prefix (/opt/)"
             (mkPaths (ModeRemovePrefixDirs [opt]) env)
             (PathEnv ([ usr_bin ], []) ([ usr_man ], []))
      ]

newtype ArbClean = ArbClean { unArbClean :: Clean }
  deriving Show

instance UnArb Clean ArbClean where
  unArb = unArbClean

instance Arbitrary ArbClean where
  arbitrary = elements [ ArbClean Clean, ArbClean NoClean ]

newtype ArbQuiet = ArbQuiet { unArbQuiet :: Quiet }
  deriving Show

instance UnArb Quiet ArbQuiet where
  unArb = unArbQuiet

instance Arbitrary ArbQuiet where
  arbitrary = elements [ ArbQuiet Quiet, ArbQuiet NoQuiet ]

data ArbPathElem = ArbPathElemValid PathElem | ArbPathElemInvalid String
  deriving Show

instance Arbitrary ArbPathElem where
  arbitrary = let -- probably one xor the other of the two below exist
                  usrBin      = ArbPathElemValid [absdir|/usr/bin|]
                  wrappersBin = ArbPathElemValid [absdir|/run/wrappers/bin|]
                  nullPath    = ArbPathElemInvalid ""
                  fooPath     = ArbPathElemInvalid "foo"
               in elements [ usrBin, nullPath, wrappersBin, fooPath]

newtype ArbPathList = ArbPathList { unArbPathList :: [ArbPathElem] }
  deriving Show

instance IsList ArbPathList where
  type Item ArbPathList = ArbPathElem
  fromList = ArbPathList
  toList   = unArbPathList

instance UnArb [ArbPathElem] ArbPathList where
  unArb = unArbPathList

-- | where Show is for debugging / diagnostic (and should be invertible with
--   Read), ToString is for real program use, e.g., printing of a path list
class ToString α where
  toString :: α -> String

instance Arbitrary ArbPathList where
  arbitrary = ArbPathList <$> listOf arbitrary
  shrink = shrinkList

instance ToString ArbPathElem where
  toString (ArbPathElemValid   d) = toFilePath d
  toString (ArbPathElemInvalid s) = s

instance ToString ArbPathList where
  toString = intercalate ":" . fmap toString . toList

newtype ArbEnv = ArbEnv { unArbE :: [(ArbEnvKey, ArbPathList)] }
  deriving Show

instance IsList ArbEnv where
  type Item ArbEnv = (ArbEnvKey, ArbPathList)
  fromList = ArbEnv . fromList
  toList = toList . unArbE

shrinkList :: (IsList ζ, Arbitrary (Item ζ)) => ζ -> [ζ]
shrinkList = fmap fromList . shrink . toList

instance Arbitrary ArbEnv where
  arbitrary = do let mkEnvElem :: ArbEnvKey -> ArbPathList -> (ArbEnvKey,ArbPathList)
                     mkEnvElem k pl = (k, pl)
                 envKeys <- nub <$> listOf arbitrary
                 fromList <$> forM envKeys ( \ s -> mkEnvElem s <$> arbitrary )
  shrink = shrinkList

instance ToString ArbEnv where
  toString ae = intercalate "\n" $ fmap ( \(aek, apl) -> unArb aek <> "=" <> toString apl) (toList ae)

instance UnArb Environment ArbEnv where
  unArb = fromList . fmap (bimap unArb toString) . toList

newtype ArbEnvKey = ArbEnvKey { unArbEnvKey :: EnvKey }
  deriving (Eq, Show)

instance UnArb EnvKey ArbEnvKey where
  unArb = unArbEnvKey

instance Arbitrary ArbEnvKey where
  arbitrary = ArbEnvKey <$> elements [ "PATH", "MANPATH", "LIBPATH"
                                     , "has space", "==" ]

propIdentityCmp :: ArbEnv -> [String]
propIdentityCmp env = let env' = unArb env
                       in compare (mkPaths ModeIdentity env') (initPaths env')

-- | test that ModeIdentity leaves paths untouched
propIdentity :: ArbEnv -> Bool
propIdentity = ([] ==) . propIdentityCmp

propertyTests :: TestTree
propertyTests = testGroup "property tests"
                  [ testProperty "identity" propIdentity
                  ]

tests :: TestTree
tests = testGroup "path-edit" [ unitTests, propertyTests ]

test :: IO ()
test = do
  ok ← fromMaybe (return False) (tryIngredients defaultIngredients mempty tests)
  case ok of
    True  → exitSuccess
    False → die "tests failed"

-- that's all, folks! ----------------------------------------------------------
