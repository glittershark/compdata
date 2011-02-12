{-# LANGUAGE TypeOperators, MultiParamTypeClasses, IncoherentInstances,
             FlexibleInstances, FlexibleContexts, GADTs, TypeSynonymInstances,
             ScopedTypeVariables #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  Data.Comp.Sum
-- Copyright   :  3gERP, 2010
-- License     :  AllRightsReserved
-- Maintainer  :  Tom Hvitved, Patrick Bahr, and Morten Ib Nielsen
-- Stability   :  unknown
-- Portability :  unknown
--
-- This module provides the infrastructure to extend signatures.
--
--------------------------------------------------------------------------------

module Data.Comp.Sum (
  (:<:)(..),
  (:+:)(..),
  project,
  proj2,
  proj3,
  deepProject,
  deepProject',
  deepProject2,
  deepProject3,
  inject,
  inject2,
  inject3,
  injectConst,
  injectConst2,
  injectConst3,
  projectConst,
  injectCxt,
  liftCxt,
  inj2,
  inj3,
  deepInject,
  deepInject2,
  deepInject3,
  substHoles,
  substHoles'
   ) where

import Data.Comp.Term
import Data.Comp.Algebra
import Data.Comp.Ops

import Control.Monad hiding (sequence)
import Prelude hiding (sequence)


import Data.Maybe
import Data.Traversable
import Data.Map (Map)
import qualified Data.Map as Map

-- |Project a sub term from a compound term.
project :: (g :<: f) => Cxt h f a -> Maybe (g (Cxt h f a))
project (Hole _) = Nothing
project (Term t) = proj t

-- |Project a sub term recursively from a term.
deepProject :: (Traversable f, Functor g, g :<: f) => Cxt h f a -> Maybe (Cxt h g a)
deepProject = appSigFunM proj

-- |Project a sub term recursively from a term, but where the subterm
-- signature is required to be traversable.
deepProject' :: forall g f h a. (Traversable g, g :<: f) => Cxt h f a
             -> Maybe (Cxt h g a)
deepProject' val = do
  v <- project val
  v' <- sequence $ (fmap deepProject' v :: g (Maybe (Cxt h g a)))
  return $ inject v'

-- |Project a binary term from a term.
proj2 :: forall f g1 g2 a. (g1 :<: f, g2 :<: f) => f a -> Maybe ((g1 :+: g2) a)
proj2 x = case proj x of
            Just (y :: g1 a) -> Just $ inj y
            _ -> liftM inj (proj x :: Maybe (g2 a))

-- |Project a binary sub term recursively from a term.
deepProject2 :: (Traversable f, Functor g1, Functor g2, g1 :<: f, g2 :<: f) => Cxt h f a -> Maybe (Cxt h (g1 :+: g2) a)
deepProject2 = appSigFunM proj2

-- |Project a ternary term from a term.
proj3 :: forall f g1 g2 g3 a. (g1 :<: f, g2 :<: f, g3 :<: f) => f a
      -> Maybe ((g1 :+: g2 :+: g3) a)
proj3 x = case proj x of
            Just (y :: g1 a) -> Just $ inj y
            _ -> case proj x of
                   Just (y :: g2 a) -> Just $ inj y
                   _ -> liftM inj (proj x :: Maybe (g3 a))

-- |Project a ternary sub term recursively from a term.
deepProject3 :: (Traversable f, Functor g1, Functor g2, Functor g3,
                 g1 :<: f, g2 :<: f, g3 :<: f) => Cxt h f a
             -> Maybe (Cxt h (g1 :+: g2 :+: g3) a)
deepProject3 = appSigFunM proj3

-- |Inject a term into a compound term.
inject :: (g :<: f) => g (Cxt h f a) -> Cxt h f a
inject = Term . inj


injectConst :: (Functor g, g :<: f) => Const g -> Cxt h f a
injectConst = inject . fmap (const undefined)


injectConst2 :: (Functor f1, Functor f2, Functor g, f1 :<: g, f2 :<: g)
             => Const (f1 :+: f2) -> Cxt h g a
injectConst2 = inject2 . fmap (const undefined)

injectConst3 :: (Functor f1, Functor f2, Functor f3, Functor g, f1 :<: g, f2 :<: g, f3 :<: g)
             => Const (f1 :+: f2 :+: f3) -> Cxt h g a
injectConst3 = inject3 . fmap (const undefined)



projectConst :: (Functor g, g :<: f) => Cxt h f a -> Maybe (Const g)
projectConst = fmap (fmap (const ())) . project

{-| This function injects a whole context into another context. -}

injectCxt :: (Functor g, g :<: f) => Cxt h' g (Cxt h f a) -> Cxt h f a
injectCxt = cata' inject

{-| This function lifts the given functor to a context. -}
liftCxt :: (Functor f, g :<: f) => g a -> Context f a
liftCxt g = simpCxt $ inj g


{-| Deep injection function.  -}

deepInject  :: (Functor g, Functor f, g :<: f) => Cxt h g a -> Cxt h f a
deepInject = appSigFun inj

{-| This is a variant of 'inj' for binary sum signatures.  -}

inj2 :: (f1 :<: g, f2 :<: g) => (f1 :+: f2) a -> g a
inj2 (Inl x) = inj x
inj2 (Inr y) = inj y


-- |Inject a term into a compound term.
inject2 :: (f1 :<: g, f2 :<: g) => (f1 :+: f2) (Cxt h g a) -> Cxt h g a
inject2 = Term . inj2

-- |A recursive version of 'inj2'.
deepInject2 :: (Functor f1, Functor f2, Functor g, f1 :<: g, f2 :<: g)
            => Cxt h (f1 :+: f2) a -> Cxt h g a
deepInject2 = appSigFun inj2

{-| This is a variant of 'inj' for ternary sum signatures.  -}

inj3 :: (f1 :<: g, f2 :<: g, f3 :<: g) => (f1 :+: f2 :+: f3) a -> g a
inj3 (Inl x) = inj x
inj3 (Inr y) = inj2 y


-- |Inject a term into a compound term.
inject3 :: (f1 :<: g, f2 :<: g, f3 :<: g) => (f1 :+: f2 :+: f3) (Cxt h g a) -> Cxt h g a
inject3 = Term . inj3

-- |A recursive version of 'inj3'.
deepInject3 :: (Functor f1, Functor f2, Functor f3, Functor g, f1 :<: g, f2 :<: g, f3 :<: g)
            => Cxt h (f1 :+: f2 :+: f3) a -> Cxt h g a
deepInject3 =  appSigFun inj3


{-| This function applies the given context with hole type @a@ to a
family @f@ of contexts (possibly terms) indexed by @a@. That is, each
hole @h@ is replaced by the context @f h@. -}

substHoles :: (Functor f, Functor g, f :<: g) => Cxt h' f v -> (v -> Cxt h g a) -> Cxt h g a
substHoles c f = injectCxt $ fmap f c

substHoles' :: (Functor f, Functor g, f :<: g, Ord v) => Cxt h' f v -> Map v (Cxt h g a) -> Cxt h g a
substHoles' c m = substHoles c (fromJust . (`Map.lookup`  m))

instance (Functor f) => Monad (Context f) where
    return = Hole
    (>>=) = substHoles


instance (Show (f a), Show (g a)) => Show ((f :+: g) a) where
    show (Inl v) = show v
    show (Inr v) = show v


instance (Ord (f a), Ord (g a)) => Ord ((f :+: g) a) where
    compare (Inl _) (Inr _) = LT
    compare (Inr _) (Inl _) = GT
    compare (Inl x) (Inl y) = compare x y
    compare (Inr x) (Inr y) = compare x y


instance (Eq (f a), Eq (g a)) => Eq ((f :+: g) a) where
    (Inl x) == (Inl y) = x == y
    (Inr x) == (Inr y) = x == y                   
    _ == _ = False