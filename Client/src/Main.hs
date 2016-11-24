{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
-- import Control.Distributed.Process
-- import Control.Distributed.Process.Node
import Data.Binary
import Data.Typeable
import Data.ByteString.Char8
import GHC.Generics
import System.Environment
import Control.Monad 

import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable, runProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet

data StartProcess = StartProcess {procName :: String, procParams :: [String]}

handleStartProcess (StartProcess name args) = do
  forkIO


logMessage :: String -> Process ()
logMessage msg = say $ "handling " ++ msg

main = do
  [host, port, typ] <- getArgs
    
  backend <- initializeBackend host port initRemoteTable
  case typ of
    "server" -> do 
      liftIO $ Prelude.putStrLn "start server node"
      node <- newLocalNode backend
      liftIO $ Prelude.putStrLn "Starting master process"
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
    liftIO $ Prelude.putStrLn "Finding slaves"
    slaves <- findSlaves backend 
    liftIO $ Prelude.putStrLn "Redirecting logs"
    -- redirectLogsHere backend slaves
    liftIO $ Prelude.putStrLn $ "Found " ++ (show $ Prelude.length slaves) ++ " slaves"
    forM_ slaves $ \peer -> send peer "hi"
    liftIO $ Prelude.putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 10000000
    

slave = do
  pid <- getSelfPid
  register "slaveController" pid
  forever $ do
    liftIO $ Prelude.putStrLn $ "Waiting for message"
    receiveWait ([match logMessage])
    liftIO $ Prelude.putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 10000000


-- main :: IO ()
-- main = do
--   [host,port,serverAddr] <- getArgs
--   Right transport <- createTransport host port defaultTCPParameters
--   Right endpoint <- newEndPoint transport
--   
--   let addr = EndPointAddress (pack serverAddr)
--   c <- connect endpoint addr ReliableOrdered defaultConnectHints
--   case c of
--     Right conn -> do 
--       send conn [pack "Hello"]
-- 
--       let echo = do 
--                   msg :: Control <- receiveWait endpoint [match ctrlMsg]
--                   print msg
--                   echo
--       echo
-- 
--       close conn
--       closeTransport transport
--       -- msg <- receive endpoint
--       -- print msg
--     Left msg -> print msg >> print serverAddr


-- 
-- logMessage :: String -> Process ()
-- logMessage msg = say $ "handling " ++ msg
-- 
-- logJob :: Job -> Process ()
-- logJob job = say $ "handling " ++ show job 


-- Right t <- createTransport "127.0.0.1" "10501" defaultTCPParameters
-- node <- newLocalNode t initRemoteTable
-- _ <- runProcess node $ do
--   echoPid <- spawnLocal $ forever $ do
--     receiveWait [match logMessage, match replyBack, match logJob]
--   say "send some msgs"
--   send echoPid "hello echo"
--   self <- getSelfPid
--   send echoPid (self, "hello!")
--   send echoPid $ Job "MultiLayer" [] 0
--   
--   m <- expectTimeout 1000000
--   case m of
--     Nothing -> die "Nothin !"
--     Just s -> say $ "got " ++ s ++ " back"
-- liftIO $ threadDelay 20000000000000
-- Prelude.putStrLn "Run"
