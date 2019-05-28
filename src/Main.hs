module Main where

import "rio" RIO hiding (log)

import qualified "purty" Args
import qualified "componentm" Control.Monad.Component
import qualified "purty" Error
import qualified "purty" Log
import qualified "optparse-applicative" Options.Applicative
import qualified "purty" Purty

main :: IO ()
main = do
  args <- Options.Applicative.execParser Args.info
  let config =
        Log.Config
          { Log.name = "Log"
          , Log.verbose = Args.debug args
          }
  code <- run args (Log.handle config) $ \log -> do
    result <- Purty.run log args
    case result of
      Just err -> do
        Log.debug log (Error.format err)
        Log.info log (Error.message err)
        pure (ExitFailure 1)
      Nothing -> pure ExitSuccess
  exitWith code

run ::
  Args.Args ->
  Control.Monad.Component.ComponentM a ->
  (a -> IO ExitCode) ->
  IO ExitCode
run args component f
  | Args.debug args =
    Control.Monad.Component.runComponentM1
      (runSimpleApp . logInfo . display)
      "purty"
      component
      f
  | otherwise = Control.Monad.Component.runComponentM "purty" component f
