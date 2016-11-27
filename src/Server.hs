{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Server (
    master
  )
  where

import Control.Concurrent.MVar
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
logResult (TimeRes d) = say $ "Master: Job has been running for " ++ show d ++ " seconds"
logResult (ProcessNameRes name) = say $ "Master: Process " ++ name ++ " is currently running"
logResult (CurJobRes jid) = say $ "Master: Job " ++ show jid ++ " is currently running"
logResult (JobStatRes jid stat) = say $ "Master: Job " ++ show jid ++ " has status " ++ show stat

master backend = do
  pid <- getSelfPid
  register "master" pid
  mJobCount <- liftIO $ newMVar (0 :: Int)
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
              jobId <- liftIO $ takeMVar mJobCount
              let jobId' = jobId + 1
              liftIO $ putMVar mJobCount jobId'
              prog:args <- liftIO $ words <$> getLine
              forM_ slaves $ \peer -> send peer $ StartProcess jobId' prog args
      "7" -> do 
              liftIO $ putStrLn "Enter filename to be read"
              jobId <- liftIO $ takeMVar mJobCount
              let jobId' = jobId + 1
              liftIO $ putMVar mJobCount jobId'
              filename <- liftIO getLine
              forM_ slaves $ \peer -> send peer $ StartProcess jobId' "cat" [filename]
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