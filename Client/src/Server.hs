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
logResult (StartRes jobId) = say $ "Master: Job succesfully started with id " ++ show jobId

master backend = do
  pid <- getSelfPid
  register "master" pid
  forever $ do
    liftIO $ putStrLn "Finding slaves"
    slaves <- findSlaves backend 
    liftIO $ putStrLn $ "Found " ++ (show $ length slaves) ++ " slaves"
    liftIO $ putStrLn $ "Select an action:\n1 - Get current process name\n2 - Get current process time\n3 - Get current stdout\n4 - View queue\n5 - Queue process\n6 - Read file\n7 - Query job status"
    mode <- liftIO getLine
    case mode of
      "5" -> do 
              liftIO $ putStrLn "Input command to run"
              prog:args <- liftIO $ words <$> getLine
              forM_ slaves $ \peer -> send peer $ StartProcess prog args
    liftIO $ putStrLn $ "Reading msg"
    receiveWait ([match logMasterMessage, match logResult])
    liftIO $ threadDelay 1000000
