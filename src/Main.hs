{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Main where

import Control.Concurrent.MVar
import Control.Concurrent (threadDelay, forkIO)
import Control.Monad (forever)
-- import Control.Distributed.Process
-- import Control.Distributed.Process.Node
import Data.Binary
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

import Client
import Server
import Job

main = do
  args <- getArgs
  case head args of
    "server" -> do 
      let [_, localHost, localPort] = args
      backend <- initializeBackend localHost localPort initRemoteTable
      putStrLn "start server node"
      node <- newLocalNode backend
      putStrLn "Starting master process"
      mPeers <- liftIO $ newMVar S.empty
      _ <- forkProcess node $ updateSlaves mPeers
      runProcess node (master backend mPeers)
    "client" -> do   
      let [_, localHost, localPort, remoteHost, remotePort] = args
      backend <- initializeBackend localHost localPort initRemoteTable
      node <- newLocalNode backend
      runProcess node (slave backend remoteHost remotePort)
