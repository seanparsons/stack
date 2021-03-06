{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Reading from external processes.

module System.Process.Run
    (runIn
    ,callProcess)
    where

import           Control.Exception
import           Control.Monad.IO.Class (MonadIO, liftIO)
import           Control.Monad.Logger (MonadLogger, logError)
import           Data.Conduit.Process hiding (callProcess)
import           Data.Foldable (forM_)
import           Data.Text (Text)
import qualified Data.Text as T
import           Path (Path, Abs, Dir, toFilePath)
import           Prelude -- Fix AMP warning
import           System.Exit (exitWith, ExitCode (..))
import qualified System.Process
import           System.Process.Read

-- | Run the given command in the given directory, inheriting stdout
-- and stderr. If it exits with anything but success, prints an error
-- and then calls 'exitWith' to exit the program.
runIn :: forall (m :: * -> *).
         (MonadLogger m,MonadIO m)
      => Path Abs Dir -- ^ directory to run in
      -> FilePath -- ^ command to run
      -> EnvOverride
      -> [String] -- ^ command line arguments
      -> Maybe Text
      -> m ()
runIn wd cmd menv args errMsg = do
    result <- liftIO (try (callProcess (Just wd) menv cmd args))
    case result of
        Left (ProcessExitedUnsuccessfully _ ec) -> do
            $logError $
                T.pack $
                concat
                    [ "Exit code "
                    , show ec
                    , " while running "
                    , show (cmd : args)
                    , " in "
                    , toFilePath wd]
            forM_ errMsg $logError
            liftIO (exitWith ec)
        Right () -> return ()

-- | Like as @System.Process.callProcess@, but takes an optional working directory and
-- environment override, and throws ProcessExitedUnsuccessfully if the
-- process exits unsuccessfully. Inherits stdout and stderr.
callProcess :: (MonadIO m)
             => Maybe (Path Abs Dir)
             -> EnvOverride
             -> String
             -> [String]
             -> m ()
callProcess wd menv cmd0 args = do
    cmd <- preProcess wd menv cmd0
    let c = (proc cmd args) { delegate_ctlc = True
                             , cwd = fmap toFilePath wd
                             , env = envHelper menv }
        action (_, _, _, p) = do
            exit_code <- waitForProcess p
            case exit_code of
              ExitSuccess   -> return ()
              ExitFailure _ -> throwIO (ProcessExitedUnsuccessfully c exit_code)
    liftIO (System.Process.createProcess c >>= action)
