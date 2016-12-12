{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Scheduler.Server (
    master
    ,updateSlaves
    ,sendSlaves
    ,startServer
    ,logResult
    ,getPeers
    ,createEmptyEnv
    ,Env
    ,Environment
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
import qualified Data.Set as S
import GHC.Generics
import System.Environment
import System.IO
import System.Timeout
import qualified System.Process as P
import Control.Monad 
import Data.Maybe(catMaybes)

import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable, runProcess, forkProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet

import Scheduler.Job

data Env = Env {peers :: S.Set NodeId, requestedStdOut :: String}
type Environment = MVar Env

logMasterMessage :: String -> Process ()
logMasterMessage msg = say $ "Master: handling " ++ msg

logResult :: Result -> Process ()
logResult (StartRes jobId) = say $ "Master: Job succesfully started with id " <> show jobId
logResult (StdOutRes jobId cont) = say $ "Master: Retreiving stdout for job " <> show jobId <> "\n" <> cont
logResult (TimeRes d) = say $ "Master: Job has been running for " ++ show d ++ " seconds"
logResult (ProcessNameRes name) = say $ "Master: Process " ++ name ++ " is currently running"
logResult (CurJobRes jid) = say $ "Master: Job " ++ show jid ++ " is currently running"
logResult (JobStatRes jid stat) = say $ "Master: Job " ++ show jid ++ " has status " ++ show stat

createEmptyEnv :: IO Environment
createEmptyEnv = liftIO $ newMVar $ Env {peers = S.empty, requestedStdOut = ""}

getPeers :: Environment -> IO (S.Set NodeId)
getPeers env = do
  e <- takeMVar env
  putMVar env e
  return $ peers e

addPeer :: Environment -> NodeId -> IO ()
addPeer env nodeId = do
  e <- takeMVar env
  putMVar env $ e {peers = S.insert nodeId (peers e)}

pingResult env (PingReply nodeId) = do
  say $ "Peer connected: " ++ show nodeId
  liftIO $ addPeer env nodeId

sendSlaves env msg = do 
  slaves <- liftIO $ getPeers env
  forM_ slaves $ \slaveNode -> nsendRemote slaveNode "slaveController" msg

updateSlaves env receiveResult = do 
  pid <- getSelfPid
  register "master" pid
  forever $ do
    liftIO $ putStrLn $ "Reading msg"
    receiveWait ([match logMasterMessage, match receiveResult , match $ pingResult env])

master backend env = do
  mJobCount <- liftIO $ newMVar (0 :: Int)
  node <- getSelfNode
  forever $ do
    liftIO $ putStrLn "Finding slaves"
    slaves <- liftIO $ getPeers env
    liftIO $ putStrLn $ "Found " ++ (show $ length slaves) ++ " slaves"
    liftIO $ putStrLn $ "Select an action:\n1 - Get current process name\n2 - Get current process time\n3 - Get current stdout"
                       ++"\n4 - Get current job id\n5 - View queue\n6 - Queue process\n7 - Read file\n8 - Query job status\n9 - Get stdout for job\n10 - Refresh"
    mode <- liftIO getLine
    case mode of
      "1" -> sendSlaves env $ GetCurrentProcessName
      "2" -> sendSlaves env $ GetCurrentProcessTime
      "3" -> sendSlaves env $ GetCurrentStdout
      "4" -> sendSlaves env $ GetCurrentJobId
      "5" -> sendSlaves env $ GetQueue
      "6" -> do 
              liftIO $ putStrLn "Input command to run"
              jobId <- liftIO $ takeMVar mJobCount
              let jobId' = jobId + 1
              liftIO $ putMVar mJobCount jobId'
              prog:args <- liftIO $ words <$> getLine
              sendSlaves env $ StartProcess jobId' prog args
      "7" -> do 
              liftIO $ putStrLn "Enter filename to be read"
              jobId <- liftIO $ takeMVar mJobCount
              let jobId' = jobId + 1
              liftIO $ putMVar mJobCount jobId'
              filename <- liftIO getLine
              sendSlaves env $ StartProcess jobId' "cat" [filename]
      "8" -> do
              liftIO $ putStrLn "Enter job id"
              jid <- liftIO $ read <$> getLine
              sendSlaves env $ GetJobStatus jid
      "9" -> do
              liftIO $ putStrLn "Enter job id"
              jid <- liftIO $ read <$> getLine
              sendSlaves env $ GetStdOut jid
      "10" -> return ()

    liftIO $ threadDelay 1000000


startServer localHost localPort receiveResult = do
  backend <- initializeBackend localHost localPort initRemoteTable
  putStrLn "start server node"
  node <- newLocalNode backend
  putStrLn "Starting master process"
  env <- createEmptyEnv 
  -- _ <- forkProcess node $ updateSlaves mPeers receiveResult
  --runProcess node (master backend mPeers)
  runProcess node (updateSlaves env logResult)
