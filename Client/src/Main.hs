{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}

module Main where

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

data StartProcess = StartProcess {procName :: String, procParams :: [String]}
  deriving (Show, Generic)

instance Binary StartProcess

startProcess :: String -> [String] -> IO String
startProcess name args = do
   (_,mOut,mErr,procHandle) <- P.createProcess $ 
        (P.proc name args) { P.std_out = P.CreatePipe
                                , P.std_err = P.CreatePipe 
                                }
   let (hOut,hErr) = maybe (error "bogus handles") 
                           id
                           ((,) <$> mOut <*> mErr)
   exitCode <- timeout 1000000 $ P.waitForProcess procHandle
   sOut <- hGetContents hOut
   P.terminateProcess procHandle
   return sOut

handleStartProcess backend (StartProcess name args) = do
  res <- liftIO $ startProcess name args
  sendMaster backend res

logSlaveMessage :: String -> Process ()
logSlaveMessage msg = say $ "Slave: handling " ++ msg

logMasterMessage :: String -> Process ()
logMasterMessage msg = say $ "Master: handling " ++ msg

main = do
  [host, port, typ] <- getArgs
  backend <- initializeBackend host port initRemoteTable
  case typ of
    "server" -> do 
      liftIO $ putStrLn "start server node"
      node <- newLocalNode backend
      liftIO $ putStrLn "Starting master process"
      runProcess node (master backend)
    "client" -> do   
      node <- newLocalNode backend
      runProcess node (slave backend)

sendMaster backend msg = do
  m <- findMaster backend 
  send m msg

findMaster :: Backend -> Process ProcessId
findMaster backend = do
  nodes <- liftIO $ findPeers backend 1000000
  bracket
   (mapM monitorNode nodes)
   (mapM unmonitor)
   $ \_ -> do
   forM_ nodes $ \nid -> whereisRemoteAsync nid "master"
   head <$> catMaybes <$> replicateM (length nodes) (
     receiveWait
       [ match (\(WhereIsReply "master" mPid) -> return mPid)
       , match (\(NodeMonitorNotification {}) -> return Nothing)
       ])

  
master backend = do
  pid <- getSelfPid
  register "master" pid
  forever $ do
    liftIO $ putStrLn "Finding slaves"
    slaves <- findSlaves backend 
    liftIO $ putStrLn "Input command to run"
    prog:args <- liftIO $ words <$> getLine
    -- redirectLogsHere backend slaves
    liftIO $ putStrLn $ "Found " ++ (show $ length slaves) ++ " slaves"
    forM_ slaves $ \peer -> send peer $ StartProcess prog args
    liftIO $ putStrLn $ "Reading msg"
    receiveWait ([match logMasterMessage])
    liftIO $ threadDelay 1000000
    

slave backend = do
  pid <- getSelfPid
  register "slaveController" pid
  forever $ do
    liftIO $ putStrLn $ "Waiting for message"
    receiveWait ([match logSlaveMessage, match (handleStartProcess backend) ])
    liftIO $ putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 100000
