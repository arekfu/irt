module SedRunner (
  useG4Types,
  disableAssertions
  ) where

import System.IO
import System.Process
import System.Exit
import Control.Exception(evaluate)

data SedCommand = SedIntToG4Int
                | SedFloatToG4Float
                | SedDoubleToG4Double
                | SedBoolToG4Bool
                | SedCommentAsserts
                | SedCommentIncludeCassert
                | SedFixG4G4
                | SedFixUnsignedG4Int
                deriving (Show, Eq)

--toG4TypeRegexp t = ["\\'s/\\b\\(" ++ t ++"\\)\\b/G4\\1/g\'"]
toG4TypeRegexp :: String -> [String]
toG4TypeRegexp t = ["s/\\(\\b\\)" ++ t ++ "\\(\\b\\)/\\1G4" ++ t ++ "\\2/g"]

--let substitute x y s = subRegex (mkRegex x) s y
-- substitute "int" "G4int"

sedCommandArgs :: SedCommand -> [String]
sedCommandArgs SedIntToG4Int = toG4TypeRegexp "int"
sedCommandArgs SedFloatToG4Float = toG4TypeRegexp "float"
sedCommandArgs SedDoubleToG4Double = toG4TypeRegexp "double"
sedCommandArgs SedBoolToG4Bool = toG4TypeRegexp "bool"
sedCommandArgs SedCommentAsserts = ["s,^\\s*assert,// assert,g"]
sedCommandArgs SedCommentIncludeCassert = ["s/#include \\+<cassert>/\\/\\/ #include <cassert>/g"]
sedCommandArgs SedFixG4G4 = ["s/G4G4/G4/g"]
sedCommandArgs SedFixUnsignedG4Int = ["s/unsigned\\ G4int/unsigned\\ int/g"]

useG4Int :: String -> IO String
useG4Int = runSed SedIntToG4Int

useG4Float :: String -> IO String
useG4Float = runSed SedFloatToG4Float

useG4Double :: String -> IO String
useG4Double = runSed SedDoubleToG4Double

useG4Bool :: String -> IO String
useG4Bool = runSed SedBoolToG4Bool

commentAsserts :: String -> IO String
commentAsserts = runSed SedCommentAsserts

commentIncludeCassert :: String -> IO String
commentIncludeCassert = runSed SedCommentIncludeCassert

disableAssertions :: String -> IO String
disableAssertions code = (commentAsserts code) >>= commentIncludeCassert

fixG4G4 :: String -> IO String
fixG4G4 = runSed SedFixG4G4

fixUnsignedG4int :: String -> IO String
fixUnsignedG4int = runSed SedFixUnsignedG4Int

-- Chain the useG4<type> functions together.
useG4Types :: String -> IO String
--useG4Types code = (useG4Int code)
useG4Types code = (useG4Int code) >>= useG4Float >>= useG4Double >>= useG4Bool >>= fixG4G4 >>= fixUnsignedG4int

runSed :: SedCommand -> String -> IO String
runSed command inputData = do
  let sedArgs = sedCommandArgs command
      inPipe = CreatePipe
      outPipe = CreatePipe
      --commandName = show command
      --sedArgsString = show sedArgs
--  putStr $ "Running " ++ commandName ++ ": " ++ sedArgsString ++ "..."
  hFlush stdout
  (Just hInput, Just hOutput, _, procHandle) <- createProcess (proc "sed" sedArgs) {std_in = inPipe, std_out = outPipe}
  hPutStr hInput inputData
  hClose hInput
  outputStr <- hGetContents hOutput
  -- Must force evaluation of the output before evaluating the exitCode. Read
  -- it here:
  -- http://book.realworldhaskell.org/read/systems-programming-in-haskell.html
  _ <- evaluate (length outputStr)
  exitCode <- waitForProcess procHandle
  if exitCode /= ExitSuccess
    then do hClose hOutput
            error "sed reported an error"
    else do --putStrLn " completed"
            return outputStr

