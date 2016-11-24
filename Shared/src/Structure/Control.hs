{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}

module Structure.Control (
    Control(..)
  )
  where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
import Control.Distributed.Process
import Control.Distributed.Process.Node
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Data.Binary
import Data.Typeable
import GHC.Generics

data Control = Idle
             | Msg String
  deriving (Show, Generic, Typeable)

instance Binary Control

-- replyBack :: (ProcessId, String) -> Process ()
-- replyBack (sender,msg) = send sender msg
-- 
-- logMessage :: String -> Process ()
-- logMessage msg = say $ "handling " ++ msg
-- 
-- logJob :: Job -> Process ()
-- logJob job = say $ "handling " ++ show job 
-- 
-- main :: IO ()
-- main = do
--   Right t <- createTransport "127.0.0.1" "10501" defaultTCPParameters
--   node <- newLocalNode t initRemoteTable
--   _ <- runProcess node $ do
--     echoPid <- spawnLocal $ forever $ do
--       receiveWait [match logMessage, match replyBack, match logJob]
--     say "send some msgs"
--     send echoPid "hello echo"
--     self <- getSelfPid
--     send echoPid (self, "hello!")
--     send echoPid $ Job "MultiLayer" [] 0
--     
--     m <- expectTimeout 1000000
--     case m of
--       Nothing -> die "Nothin !"
--       Just s -> say $ "got " ++ s ++ " back"
--   liftIO $ threadDelay 20000000000000
--   putStrLn "Run"
