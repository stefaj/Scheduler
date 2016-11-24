{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveGeneric #-}

module Main where

import Control.Concurrent (threadDelay)
import Control.Monad (forever)
-- import Control.Distributed.Process
-- import Control.Distributed.Process.Node
import Network.Transport
import Network.Transport.TCP (createTransport, defaultTCPParameters)
import Data.Binary
import Data.Typeable
import Data.ByteString.Char8
import GHC.Generics
import System.Environment
import Control.Monad 
import Structure.Job

main :: IO ()
main = do
  [host,port,serverAddr] <- getArgs
  Right transport <- createTransport host port defaultTCPParameters
  Right endpoint <- newEndPoint transport
  
  let addr = EndPointAddress (pack serverAddr)
  c <- connect endpoint addr ReliableOrdered defaultConnectHints
  case c of
    Right conn -> do 
      send conn [pack "Hello"]

      let echo = do 
                  msg <- receive endpoint
                  print msg
                  echo
      echo

      close conn
      closeTransport transport
      -- msg <- receive endpoint
      -- print msg
    Left msg -> print msg >> print serverAddr


-- replyBack :: (ProcessId, String) -> Process ()
-- replyBack (sender,msg) = send sender msg
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
