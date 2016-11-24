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

handleStartProcess (StartProcess name args) = do
  liftIO $ forkIO $ do
    return ()


logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

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
      runProcess node slave

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
    liftIO $ putStrLn "Redirecting logs"
    -- redirectLogsHere backend slaves
    liftIO $ putStrLn $ "Found " ++ (show $ length slaves) ++ " slaves"
    forM_ slaves $ \peer -> send peer "hi"
    liftIO $ putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 10000000
    

slave = do
  pid <- getSelfPid
  register "slaveController" pid
  forever $ do
    liftIO $ putStrLn $ "Waiting for message"
    receiveWait ([match logMessage])
    liftIO $ putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 10000000
