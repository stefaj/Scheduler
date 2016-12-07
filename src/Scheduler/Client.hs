{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Scheduler.Client (
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
import Data.Monoid
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

import Network.Transport (EndPointAddress(..))
import Control.Distributed.Process
import Control.Distributed.Process.Closure
import Control.Distributed.Process.Node (initRemoteTable, runProcess)
import Control.Distributed.Process.Backend.SimpleLocalnet

import Scheduler.Job

data CurrentState = CurrentState {csStartTime :: Double
                                 ,csCurProcHand :: Maybe P.ProcessHandle
                                 ,csStdoutHand :: Maybe Handle
                                 ,csJobId :: JobId
                                 ,csJobState :: JobStatus
                                 ,csJobCounter :: JobId
                                 ,csProcName :: String
                                 ,csQueue :: S.Seq Job} 

startProcess :: MVar CurrentState -> JobId -> String -> [String] -> IO JobId
startProcess mState jobid name args = do
   state <- takeMVar mState
   let queue' = (csQueue state) S.|> (ProcessJob jobid name args)
   putMVar mState $ state {csQueue = queue', csJobCounter = jobid}
   return jobid

handleMsgs mState backend remoteHost remotePort (StartProcess jobid name args) = do
  newId <- liftIO $ startProcess mState jobid name args
  sendMaster backend remoteHost remotePort $ StartRes newId

handleMsgs mState backend remoteHost remotePort GetCurrentProcessTime = do
  state <- liftIO $ takeMVar mState
  liftIO $ putMVar mState state
  let t = csStartTime state 
  t' <- liftIO getTime
  sendMaster backend remoteHost remotePort $ TimeRes (t' - t)

handleMsgs mState backend remoteHost remotePort GetCurrentProcessName = do
  state <- liftIO $ takeMVar mState
  liftIO $ putMVar mState state
  sendMaster backend remoteHost remotePort$ ProcessNameRes (csProcName state)

handleMsgs mState backend remoteHost remotePort GetCurrentJobId = do
  state <- liftIO $ takeMVar mState
  liftIO $ putMVar mState state
  sendMaster backend remoteHost remotePort $ CurJobRes (csJobId state)

handleMsgs mState backend remoteHost remotePort (GetJobStatus jobid) = do
  state <- liftIO $ takeMVar mState
  liftIO $ putMVar mState state
  let curjid = csJobId state
  let ans = case () of _
                        | jobid < curjid -> Completed
                        | jobid > curjid -> Queued
                        | jobid == curjid -> csJobState state
  sendMaster backend remoteHost remotePort $ JobStatRes jobid ans

handleMsgs mState backend remoteHost remotePort (GetStdOut jobid) = do
  state <- liftIO $ takeMVar mState
  liftIO $ putMVar mState state
  let curJobId = csJobId state
  case () of _
              | jobid == curJobId && csJobState state == Completed -> do
                  cont <- liftIO $ readFile $ "data" <> "/" <> (show jobid)
                  sendMaster backend remoteHost remotePort $ StdOutRes jobid cont
              | jobid < curJobId -> do
                  cont <- liftIO $ readFile $ "data" <> "/" <> (show jobid)
                  sendMaster backend remoteHost remotePort $ StdOutRes jobid cont
              | otherwise -> sendMaster backend remoteHost remotePort $ StdOutRes jobid ""

logSlaveMessage :: String -> Process ()
logSlaveMessage msg = say $ "Slave: handling " ++ msg

sendMaster backend remoteHost remotePort msg = do
  let addr = remoteHost <> ":" <> remotePort
  let remoteNode = NodeId . EndPointAddress . BC8.concat $ [BC8.pack addr, ":0"]
  nsendRemote remoteNode "master" msg
  -- send m msg

slave backend remoteHost remotePort = do
  liftIO $ initializeTime
  pid <- getSelfPid
  node <- getSelfNode
  register "slaveController" pid
  mState <- liftIO $ newMVar $ CurrentState 0 Nothing Nothing 0 Completed 0 "" S.empty

  liftIO $ putStrLn "Sending ping"
  liftIO $ threadDelay 1000000
  sendMaster backend remoteHost remotePort (PingReply node)
  liftIO $ threadDelay 1000000
  liftIO $ putStrLn "Sent ping"

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
        putStrLn $ "Running process " ++ pname ++ " for job " ++ show pid
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
                               ,csJobState = Running, csQueue = seq, csProcName = pname}
        putStrLn $ "Saving stdout to file"
        let filepath = "data" <> "/" <> (show pid) 
        writeFile filepath ""
        exitCode <- P.waitForProcess procHandle
        hGetContents hOut >>= appendFile filepath 
        state' <- takeMVar mState
        putMVar mState $ state' {csJobState = Completed}
    
  forever $ do
    liftIO $ putStrLn $ "Waiting for message"
    receiveWait ([match logSlaveMessage, match (handleMsgs mState backend remoteHost remotePort) ])
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
