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

type JobId = Int

data Job = ProcessJob {pjJobId :: JobId, pjProcName :: String, pjProcParams :: [String]}
  deriving (Show, Typeable, Generic)

data Msg = StartProcess {mProcName :: String, mProcParams :: [String]} 
         | GetCurrentProcessTime
         | GetCurrentProcessName
         | GetCurrentStdout
         | GetCurrentJobId
         | GetStdOut JobId
         | GetQueue
         | GetFile String
         | GetJobStatus JobId
  deriving (Show, Typeable, Generic)

data Result = StartRes JobId
            | TimeRes Int
            | ProcessNameRes String
            | CancelJob JobId
            | StdOutRes JobId String
            | JobIdRes JobStatus
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

