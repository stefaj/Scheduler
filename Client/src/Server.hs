{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Server (
    master
  )
  where

import Control.Concurrent (threadDelay, forkIO)
import Control.Monad (forever)
-- import Control.Distributed.Process
-- import Control.Distributed.Process.Node
import Data.Binary
import Data.Monoid
import Data.Typeable
import qualified Data.ByteString.Char8 as BC8
import GHC.Generics
import System.Environment
import System.IO
import System.Timeout
import qualified System.Process as P
import Control.Monad 
import Data.Maybe(catMaybes)

import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable, runProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet

import Job

logMasterMessage :: String -> Process ()
logMasterMessage msg = say $ "Master: handling " ++ msg

logResult :: Result -> Process ()
logResult (StartRes jobId) = say $ "Master: Job succesfully started with id " <> show jobId
logResult (StdOutRes jobId cont) = say $ "Master: Retreiving stdout for job " <> show jobId <> "\n" <> cont

master backend = do
  pid <- getSelfPid
  register "master" pid
  forever $ do
    liftIO $ putStrLn "Finding slaves"
    slaves <- findSlaves backend 
    liftIO $ putStrLn $ "Found " ++ (show $ length slaves) ++ " slaves"
    liftIO $ putStrLn $ "Select an action:\n1 - Get current process name\n2 - Get current process time\n3 - Get current stdout"
                       ++"\n4 - Get current job id\n5 - View queue\n6 - Queue process\n7 - Read file\n8 - Query job status\n9 - Get stdout for job"
    mode <- liftIO getLine
    case mode of
      "1" -> forM_ slaves $ \peer -> send peer $ GetCurrentProcessName
      "2" -> forM_ slaves $ \peer -> send peer $ GetCurrentProcessTime
      "3" -> forM_ slaves $ \peer -> send peer $ GetCurrentStdout
      "4" -> forM_ slaves $ \peer -> send peer $ GetCurrentJobId
      "5" -> forM_ slaves $ \peer -> send peer $ GetQueue
      "6" -> do 
              liftIO $ putStrLn "Input command to run"
              prog:args <- liftIO $ words <$> getLine
              forM_ slaves $ \peer -> send peer $ StartProcess prog args
      "7" -> do 
              liftIO $ putStrLn "Enter filename to be read"
              filename <- liftIO getLine
              forM_ slaves $ \peer -> send peer $ StartProcess "cat" [filename]
      "8" -> do
              liftIO $ putStrLn "Enter job id"
              jid <- liftIO $ read <$> getLine
              forM_ slaves $ \peer -> send peer $ GetJobStatus jid
      "9" -> do
              liftIO $ putStrLn "Enter job id"
              jid <- liftIO $ read <$> getLine
              forM_ slaves $ \peer -> send peer $ GetStdOut jid

    liftIO $ putStrLn $ "Reading msg"
    receiveWait ([match logMasterMessage, match logResult])
    liftIO $ threadDelay 1000000
