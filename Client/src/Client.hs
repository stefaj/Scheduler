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

import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable, runProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet

import Job

data CurrentState = CurrentState {csStartTime :: Double
                                 ,csCurProcHand :: P.ProcessHandle
                                 ,csStdoutHand :: Maybe Handle
                                 ,csJobId :: JobId
                                 ,csJobState :: JobStatus
                                 ,csQueue :: S.Seq Job} 

startProcess :: String -> [String] -> IO JobId
startProcess mState name args = do
   state <- takeMVar mState
   let newJobId = 1 + (csJobId state)
   (_,mOut,mErr,procHandle) <- P.createProcess $ 
        (P.proc name args) { P.std_out = P.CreatePipe
                                , P.std_err = P.CreatePipe 
                                }
   let (hOut,hErr) = maybe (error "bogus handles") 
                           id
                           ((,) <$> mOut <*> mErr)
   t <- getTime
   let queue' = csQueue S.|> (ProcessJob newJobId name args)
   putMVar $ state {csStartTime = t, csCurProcHand = procHandle, 
                   ,csStdoutHand = hOut, csJobId = newJobId,
                   ,csQueue = queue'}
   return newJobId

handleStartProcess mState backend (StartProcess name args) = do
  newId <- liftIO $ startProcess name args
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
  mState <- liftIO $ newMVar $ CurrentState 0 0 Nothing 0 S.empty
  forever $ do
    liftIO $ putStrLn $ "Waiting for message"
    receiveWait ([match logSlaveMessage, match (handleStartProcess mState backend) ])
    liftIO $ putStrLn $ "Waiting for next cycle"
    liftIO $ threadDelay 100000

getAvailableStdOut :: Process -> IO T.Text
getAvailableStdOut (Process _ _ _ _ (Just (ProcessData o _ _ _))) = do
  contents <- hGetAvailableContents o
  return $ T.pack contents
getAvailableStdOut Process{} = return $ T.pack ""

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
