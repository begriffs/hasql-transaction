module Hasql.Transaction.Private.Transaction
where

import Hasql.Transaction.Private.Prelude
import qualified Hasql.Query as A
import qualified Hasql.Session as B
import qualified Hasql.Transaction.Private.Queries as C


-- |
-- A composable abstraction over the retryable transactions.
-- 
-- Executes multiple queries under the specified mode and isolation level,
-- while automatically retrying the transaction in case of conflicts.
-- Thus this abstraction closely reproduces the behaviour of 'STM'.
newtype Transaction a =
  Transaction (B.Session a)
  deriving (Functor, Applicative, Monad)

-- |
-- 
data Mode =
  -- |
  -- Read-only. No writes possible.
  Read |
  -- |
  -- Write and commit.
  Write |
  -- |
  -- Write without committing.
  -- Useful for testing, 
  -- allowing you to modify your database, 
  -- producing some result based on your changes,
  -- and letting Hasql roll all the changes back on the exit from the transaction.
  WriteWithoutCommitting
  deriving (Show, Eq, Ord, Enum, Bounded)

-- |
-- For reference see
-- <http://www.postgresql.org/docs/current/static/transaction-iso.html the Postgres' documentation>.
-- 
data IsolationLevel =
  ReadCommitted |
  RepeatableRead |
  Serializable
  deriving (Show, Eq, Ord, Enum, Bounded)

-- |
-- Execute the transaction using the provided isolation level and mode.
{-# INLINABLE run #-}
run :: Transaction a -> IsolationLevel -> Mode -> B.Session a
run (Transaction session) isolation mode =
  fix $
  \ recur ->
    do
      resultEither <- do
        B.query () (C.beginTransaction mode')
        tryError $ do
          result <- session
          B.query () (bool C.abortTransaction C.commitTransaction commit)
          return result
      case resultEither of
        Left error -> do
          B.query () C.abortTransaction
          case error of
            B.ResultError (B.ServerError "40001" _ _ _) ->
              recur
            _ -> 
              throwError error
        Right result -> do
          pure result
  where
    mode' =
      (unsafeCoerce isolation, write)
    (write, commit) =
      case mode of
        Read -> (False, True)
        Write -> (True, True)
        WriteWithoutCommitting -> (True, False)

-- |
-- Possibly a multi-statement query,
-- which however cannot be parameterized or prepared,
-- nor can any results of it be collected.
{-# INLINE sql #-}
sql :: ByteString -> Transaction ()
sql sql =
  Transaction $ B.sql sql

-- |
-- Parameters and a specification of the parametric query to apply them to.
{-# INLINE query #-}
query :: a -> A.Query a b -> Transaction b
query params query =
  Transaction $ B.query params query
