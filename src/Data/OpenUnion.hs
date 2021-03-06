{-# OPTIONS_HADDOCK show-extensions #-}

{-# LANGUAGE CPP #-}

{-# LANGUAGE TypeFamilies, TypeOperators #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds, PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, FlexibleContexts #-}
{-# LANGUAGE Trustworthy #-}
{-# OPTIONS_GHC -Wwarn #-}

#if __GLASGOW_HASKELL__ >= 800
{-# OPTIONS_GHC -Wwarn -Wno-redundant-constraints #-}
#endif

#if __GLASGOW_HASKELL__ < 710 || FORCE_OU51
{-# OPTIONS_GHC -fno-warn-warnings-deprecations #-}
{-# LANGUAGE OverlappingInstances #-}
#else
#endif

-- Only for SetMember below, when emulating Monad Transformers
{-# LANGUAGE FunctionalDependencies, UndecidableInstances #-}

-- | Open unions (type-indexed co-products) for extensible effects
-- All operations are constant-time, and there is no Typeable constraint
--
-- This is a variation of OpenUion5.hs, which relies on overlapping
-- instances instead of closed type families. Closed type families
-- have their problems: overlapping instances can resolve even
-- for unground types, but closed type families are subject to a
-- strict apartness condition.
--
-- This implementation is very similar to OpenUnion1.hs, but without
-- the annoying Typeable constraint. We sort of emulate it:
--
-- Our list r of open union components is a small Universe.
-- Therefore, we can use the Typeable-like evidence in that
-- universe. We hence can define
--
-- @
-- data Union r v where
--   Union :: t v -> TRep t r -> Union r v -- t is existential
-- @
-- where
--
-- @
-- data TRep t r where
--   T0 :: TRep t (t ': r)
--   TS :: TRep t r -> TRep (any ': r)
-- @
-- Then Member is a type class that produces TRep
-- Taken literally it doesn't seem much better than
-- OpenUinion41.hs. However, we can cheat and use the index of the
-- type t in the list r as the TRep. (We will need UnsafeCoerce then).
--
-- The interface is the same as of other OpenUnion*.hs
module Data.OpenUnion (Union, inj, prj, decomp,
                   Member, SetMember, weaken, extract
                  ) where

import Unsafe.Coerce(unsafeCoerce)

-- | The data constructors of Union are not exported
--
-- Strong Sum (Existential with the evidence) is an open union
-- t is can be a GADT and hence not necessarily a Functor.
-- Int is the index of t in the list r; that is, the index of t in the
-- universe r
data Union (r :: [ * -> * ]) v where
  Union :: {-# UNPACK #-} !Int -> t v -> Union r v

{-# INLINE prj' #-}
{-# INLINE inj' #-}
inj' :: Int -> t v -> Union r v
inj' = Union

prj' :: Int -> Union r v -> Maybe (t v)
prj' n (Union n' x) | n == n'   = Just (unsafeCoerce x)
                    | otherwise = Nothing

newtype P t r = P{unP :: Int}

class (FindElem t r) => Member (t :: * -> *) r where
  inj :: t v -> Union r v
  prj :: Union r v -> Maybe (t v)

#if __GLASGOW_HASKELL__ < 710 || FORCE_OU51
{-
-- Optimized specialized instance
instance Member t '[t] where
  {-# INLINE inj #-}
  {-# INLINE prj #-}
  inj x           = Union 0 x
  prj (Union _ x) = Just (unsafeCoerce x)
-}
instance (FindElem t r) => Member t r where
  {-# INLINE inj #-}
  {-# INLINE prj #-}
  inj = inj' (unP $ (elemNo :: P t r))
  prj = prj' (unP $ (elemNo :: P t r))
#else
-- | Explicit type-level equality condition is a dirty
-- hack to eliminate the type annotation in the trivial case,
-- such as @run (runReader get ())@.
--
-- There is no ambiguity when finding instances for
-- @Member t (a ': b ': r)@, which the second instance is selected.
--
-- The only case we have to concerned about is  @Member t '[s]@.
-- But, in this case, values of definition is the same (if present),
-- and the first one is chosen according to GHC User Manual, since
-- the latter one is incoherent. This is the optimal choice.
instance {-# OVERLAPPING #-} t ~ s => Member t '[s] where
   {-# INLINE inj #-}
   {-# INLINE prj #-}
   inj x           = Union 0 x
   prj (Union _ x) = Just (unsafeCoerce x)

instance {-# INCOHERENT #-}  (FindElem t r) => Member t r where
  {-# INLINE inj #-}
  {-# INLINE prj #-}
  inj = inj' (unP $ (elemNo :: P t r))
  prj = prj' (unP $ (elemNo :: P t r))
#endif



{-# INLINE [2] decomp #-}
decomp :: Union (t ': r) v -> Either (Union r v) (t v)
decomp (Union 0 v) = Right $ unsafeCoerce v
decomp (Union n v) = Left  $ Union (n-1) v


-- Specialized version
{-# RULES "decomp/singleton"  decomp = decomp0 #-}
{-# INLINE decomp0 #-}
decomp0 :: Union '[t] v -> Either (Union '[] v) (t v)
decomp0 (Union _ v) = Right $ unsafeCoerce v
-- No other case is possible

-- copied (and edited) from
-- https://gitlab.com/queertypes/freer/blob/develop/src/Data/Open/Union/Internal.hs
extract :: Union '[t] v -> t v
extract (Union 0 x)  = unsafeCoerce x

weaken :: Union r w -> Union (any ': r) w
weaken (Union n v) = Union (n+1) v

-- | Find an index of an element in a `list'
-- The element must exist
-- This is essentially a compile-time computation.
-- Using overlapping instances here is OK since this class is private to this
-- module
class FindElem (t :: * -> *) r where
  elemNo :: P t r

#if !(__GLASGOW_HASKELL__ < 710 || FORCE_OU51)
-- Stopped Using Obsolete -XOverlappingInstances
-- and explicitly specify to choose the topmost
-- one for multiple occurence, which is the same
-- behaviour as OpenUnion51 with GHC 7.10.
instance {-# INCOHERENT #-} t ~ s => FindElem t '[s] where
  elemNo = P 0
#endif
instance FindElem t (t ': r) where
  elemNo = P 0

#if __GLASGOW_HASKELL__ < 710 || FORCE_OU51
instance FindElem t r => FindElem t (t' ': r) where
#else
instance {-# OVERLAPPABLE #-} FindElem t r => FindElem t (t' ': r) where
#endif
  elemNo = P $ 1 + (unP $ (elemNo :: P t r))


-- | Using overlapping instances here is OK since this class is private to this
-- module
class EQU (a :: k) (b :: k) p | a b -> p
instance EQU a a 'True
#if __GLASGOW_HASKELL__ < 710 || FORCE_OU51
instance (p ~ 'False) => EQU a b p
#else
instance {-# OVERLAPPABLE #-} (p ~ 'False) => EQU a b p
#endif

-- | This class is used for emulating monad transformers
class Member t r => SetMember (tag :: k -> * -> *) (t :: * -> *) r | tag r -> t
instance (EQU t1 t2 p, MemberU' p tag t1 (t2 ': r)) => SetMember tag t1 (t2 ': r)

class Member t r =>
      MemberU' (f::Bool) (tag :: k -> * -> *) (t :: * -> *) r | tag r -> t
instance MemberU' 'True tag (tag e) (tag e ': r)
instance (Member t (t' ': r), SetMember tag t r) =>
           MemberU' 'False tag t (t' ': r)
