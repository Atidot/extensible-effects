{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE Safe #-}
{-# LANGUAGE CPP #-}
-- The following is needed to define MonadPlus instance. It is decidable
-- (there is no recursion!), but GHC cannot see that.
{-# LANGUAGE UndecidableInstances #-}

-- | Nondeterministic choice effect
module Control.Eff.Choose ( Choose (..)
                          , choose
                          , makeChoice
                          , mzero'
                          , mplus'
                          ) where

import Control.Eff
#if __GLASGOW_HASKELL__ > 708
import Control.Applicative
import Control.Monad
#endif

-- ------------------------------------------------------------------------
-- | Non-determinism (choice)
--
-- choose lst non-deterministically chooses one value from the lst
-- choose [] thus corresponds to failure
-- Unlike Reader, Choose is not a GADT because the type of values
-- returned in response to a (Choose a) request is just a, without
-- any constraints.
newtype Choose a = Choose [a]

-- | choose lst non-deterministically chooses one value from the lst
-- choose [] thus corresponds to failure
choose :: Member Choose r => [a] -> Eff r a
choose lst = send $ Choose lst

-- | MonadPlus-like operators are expressible via choose
mzero' :: Member Choose r => Eff r a
mzero' = choose []

-- | MonadPlus-like operators are expressible via choose
mplus' :: Member Choose r => Eff r a -> Eff r a -> Eff r a
mplus' m1 m2 = choose [m1,m2] >>= id

#if __GLASGOW_HASKELL__ > 708
-- | MonadPlus-like operators are expressible via choose
instance Member Choose r => Alternative (Eff r) where
  empty = mzero'
  (<|>) = mplus'

instance Member Choose r => MonadPlus (Eff r) where
  mzero = empty
  mplus = (<|>)
#endif

-- | Run a nondeterministic effect, returning all values.
makeChoice :: forall a r. Eff (Choose ': r) a -> Eff r [a]
makeChoice = handle_relay
  (return . (:[]))
  (\(Choose lst) k -> handle lst k)
  where
    handle :: [t] -> (t -> Eff r [a]) -> Eff r [a]
    handle []  _ = return []
    handle [x] k = k x
    handle lst k = fmap concat $ mapM k lst
