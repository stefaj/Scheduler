{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

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

import Client
import Server
import Job

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
