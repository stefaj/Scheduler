{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE ViewPatterns #-}

module Job where

import Data.Binary
import Data.Typeable
import qualified Data.ByteString.Char8 as BC8
import GHC.Generics
import Control.Monad 
import Control.Distributed.Process

type JobId = Int

data Job = ProcessJob {pjJobId :: JobId, pjProcName :: String, pjProcParams :: [String]}
  deriving (Show, Typeable, Generic)

data Msg = StartProcess {mjobId :: JobId, mProcName :: String, mProcParams :: [String]} 
         | GetCurrentProcessTime
         | GetCurrentProcessName
         | GetCurrentStdout
         | GetCurrentJobId
         | GetStdOut JobId
         | GetQueue
         | GetFile String
         | GetJobStatus JobId
  deriving (Show, Typeable, Generic)

data Ping = PingRequest
          | PingReply NodeId
  deriving (Show, Typeable, Generic)

data Result = StartRes JobId
            | TimeRes Double
            | ProcessNameRes String
            | CancelJob JobId
            | StdOutRes JobId String
            | CurJobRes JobId
            | JobStatRes JobId JobStatus
            | ProgRes String
            | QueueRes [(JobId, String)]
  deriving (Show, Typeable, Generic)

data JobStatus = Running
               | Queued
               | Completed
  deriving (Show, Typeable, Generic, Eq)

instance Binary Msg
instance Binary Result
instance Binary JobStatus
instance Binary Ping

