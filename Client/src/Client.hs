{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Client (
    slave
  )
  where

import Control.Concurrent (threadDelay, forkIO)
import Control.Concurrent.MVar
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
import qualified Data.Sequence as S
import Criterion.Measurement

import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable, runProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet

import Job

data CurrentState = CurrentState {csStartTime :: Double
                                 ,csCurProcHand :: Maybe P.ProcessHandle
                                 ,csStdoutHand :: Maybe Handle
                                 ,csJobId :: JobId
                                 ,csJobState :: JobStatus
                                 ,csJobCounter :: JobId
                                 ,csQueue :: S.Seq Job} 

startProcess :: MVar CurrentState -> String -> [String] -> IO JobId
startProcess mState name args = do
   state <- takeMVar mState
   let newJobId = 1 + (csJobCounter state)
   let queue' = (csQueue state) S.|> (ProcessJob newJobId name args)
   putMVar mState $ state {csQueue = queue', csJobCounter = newJobId}
   return newJobId

handleStartProcess mState backend (StartProcess name args) = do
  newId <- liftIO $ startProcess mState name args
  sendMaster backend $ StartRes newId

logSlaveMessage :: String -> Process ()
logSlaveMessage msg = say $ "Slave: handling " ++ msg

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

slave backend = do
  liftIO $ initializeTime
  pid <- getSelfPid
  register "slaveController" pid
  mState <- liftIO $ newMVar $ CurrentState 0 Nothing Nothing 0 Completed 0 S.empty

  -- Handle queue
  liftIO $ forkIO $ forever $ do
    threadDelay 1000000
    state <- takeMVar mState
    putMVar mState state
    case S.viewl (csQueue state) of
      S.EmptyL -> return ()
      (ProcessJob pid pname pargs) S.:< seq -> do
        initializeTime
        t <- getTime
        (_,mOut,mErr,procHandle) <- P.createProcess $ 
             (P.proc pname pargs) { P.std_out = P.CreatePipe
                                     , P.std_err = P.CreatePipe 
                                     }
        let (hOut,hErr) = maybe (error "bogus handles") 
                                id
                                ((,) <$> mOut <*> mErr)
        _ <- takeMVar mState
        putMVar mState $ state {csStartTime = t, csCurProcHand = Just procHandle
                               ,csStdoutHand = Just hOut, csJobId = pid
                               ,csJobState = Running, csQueue = seq}
        exitCode <- P.waitForProcess procHandle
        state' <- takeMVar mState
        putMVar mState $ state' {csJobState = Completed}
    
  forever $ do
    liftIO $ putStrLn $ "Waiting for message"
    receiveWait ([match logSlaveMessage, match (handleStartProcess mState backend) ])
    liftIO $ putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 100000

getAvailableStdOut :: CurrentState -> IO String
getAvailableStdOut state = do
  case csStdoutHand state of
    Just hand -> hGetAvailableContents hand
    Nothing -> return "" 

hGetAvailableContents :: Handle -> IO String
hGetAvailableContents = flip hGetAvailableContents' []
hGetAvailableContents' :: Handle -> String -> IO String
hGetAvailableContents' h buff = do
  r <- hReady h
  if r then do
    c <- hGetChar h
    hGetAvailableContents' h (c:buff)
  else
    return $ reverse buff
