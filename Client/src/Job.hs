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

data StartProcess = StartProcess {procName :: String, procParams :: [String]}
  deriving (Show, Generic, Typeable)

instance Binary StartProcess

