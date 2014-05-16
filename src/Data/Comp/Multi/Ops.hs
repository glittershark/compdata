{-# LANGUAGE TypeOperators, MultiParamTypeClasses, OverlappingInstances,
             FlexibleInstances, FlexibleContexts, GADTs, TypeSynonymInstances,
             ScopedTypeVariables, FunctionalDependencies, UndecidableInstances, 
             KindSignatures, RankNTypes, TypeFamilies, DataKinds, ConstraintKinds,
             PolyKinds #-}

--------------------------------------------------------------------------------
-- |
-- Module      :  Data.Comp.Ops
-- Copyright   :  (c) 2011 Patrick Bahr
-- License     :  BSD3
-- Maintainer  :  Patrick Bahr <paba@diku.dk>
-- Stability   :  experimental
-- Portability :  non-portable (GHC Extensions)
--
-- This module provides operators on higher-order functors. All definitions are
-- generalised versions of those in "Data.Comp.Ops".
--
--------------------------------------------------------------------------------

module Data.Comp.Multi.Ops where

import Data.Comp.Multi.HFunctor
import Data.Comp.Multi.HFoldable
import Data.Comp.Multi.HTraversable
import qualified Data.Comp.Ops as O
import Control.Monad
import Control.Applicative


infixr 6 :+:


-- |Data type defining coproducts.
data (f :+: g) (h :: * -> *) e = Inl (f h e)
                    | Inr (g h e)

{-| Utility function to case on a higher-order functor sum, without exposing the
  internal representation of sums. -}
caseH :: (f a b -> c) -> (g a b -> c) -> (f :+: g) a b -> c
caseH f g x = case x of
                Inl x -> f x
                Inr x -> g x

instance (HFunctor f, HFunctor g) => HFunctor (f :+: g) where
    hfmap f (Inl v) = Inl $ hfmap f v
    hfmap f (Inr v) = Inr $ hfmap f v

instance (HFoldable f, HFoldable g) => HFoldable (f :+: g) where
    hfold (Inl e) = hfold e
    hfold (Inr e) = hfold e
    hfoldMap f (Inl e) = hfoldMap f e
    hfoldMap f (Inr e) = hfoldMap f e
    hfoldr f b (Inl e) = hfoldr f b e
    hfoldr f b (Inr e) = hfoldr f b e
    hfoldl f b (Inl e) = hfoldl f b e
    hfoldl f b (Inr e) = hfoldl f b e

    hfoldr1 f (Inl e) = hfoldr1 f e
    hfoldr1 f (Inr e) = hfoldr1 f e
    hfoldl1 f (Inl e) = hfoldl1 f e
    hfoldl1 f (Inr e) = hfoldl1 f e

instance (HTraversable f, HTraversable g) => HTraversable (f :+: g) where
    htraverse f (Inl e) = Inl <$> htraverse f e
    htraverse f (Inr e) = Inr <$> htraverse f e
    hmapM f (Inl e) = Inl `liftM` hmapM f e
    hmapM f (Inr e) = Inr `liftM` hmapM f e

-- The subsumption relation.

infixl 5 :<:
infixl 5 :=:

data Pos = Here | Le Pos | Ri Pos | Sum Pos Pos
data Emb = Found Pos | NotFound | Ambiguous


type family Elem (f :: (* -> *) -> * -> *)
                 (g :: (* -> *) -> * -> *) :: Emb where
    Elem f f = Found Here
    Elem f (g1 :+: g2) = Choose f (g1 :+: g2) (Elem f g1) (Elem f g2)
    Elem f g = NotFound


type family Choose f g (e1 :: Emb) (r :: Emb) :: Emb where
    Choose f g (Found x) (Found y) = Ambiguous
    Choose f g Ambiguous y = Ambiguous
    Choose f g x Ambiguous = Ambiguous
    Choose f g (Found x) y = Found (Le x)
    Choose f g x (Found y) = Found (Ri y)
    Choose (f1 :+: f2) g x y =  Sum' (Elem f1 g) (Elem f2 g) 
    Choose f g x y = NotFound


type family Sum' (e1 :: Emb) (r :: Emb) :: Emb where
    Sum' (Found x) (Found y) = Found (Sum x y)
    Sum' Ambiguous y = Ambiguous
    Sum' x Ambiguous = Ambiguous
    Sum' NotFound y = NotFound
    Sum' x NotFound = NotFound

data Proxy a = P

class Subsume (e :: Emb) (f :: (* -> *) -> * -> *)
                         (g :: (* -> *) -> * -> *) where
  inj'  :: Proxy e -> f a :-> g a
  prj'  :: Proxy e -> NatM Maybe (g a) (f a)

instance Subsume (Found Here) f f where
    inj' _ = id

    prj' _ = Just

instance Subsume (Found p) f g => Subsume (Found (Le p)) f (g :+: g') where
    inj' _ = Inl . inj' (P :: Proxy (Found p))
    
    prj' _ (Inl x) = prj' (P :: Proxy (Found p)) x
    prj' _ _       = Nothing

instance Subsume (Found p) f g => Subsume (Found (Ri p)) f (g' :+: g) where
    inj' _ = Inr . inj' (P :: Proxy (Found p))

    prj' _ (Inr x) = prj' (P :: Proxy (Found p)) x
    prj' _ _       = Nothing
              
instance (Subsume (Found p1) f1 g, Subsume (Found p2) f2 g) 
    => Subsume (Found (Sum p1 p2)) (f1 :+: f2) g where
    inj' _ (Inl x) = inj' (P :: Proxy (Found p1)) x
    inj' _ (Inr x) = inj' (P :: Proxy (Found p2)) x

    prj' _ x = case prj' (P :: Proxy (Found p1)) x of
                 Just y -> Just (Inl y)
                 _      -> case prj' (P :: Proxy (Found p2)) x of
                             Just y -> Just (Inr y)
                             _      -> Nothing


type family Or (a :: Bool) (b :: Bool) :: Bool where
    Or  False  False  = False
    Or  a      b      = True


type family AnyDupl f g where
    AnyDupl f f = False -- ignore check for duplication if subsumption is reflexive
    AnyDupl f g = Or (Dupl f '[]) (Dupl g '[])

type family Dupl (f :: (* -> *) -> * -> *) (l :: [(* -> *) -> * -> *]) :: Bool where
    Dupl (f :+: g) l = Dupl f (g ': l)
    Dupl f l         = Or (Find f l) (Dupl' l)

type family Dupl' (l :: [(* -> *) -> * -> *]) :: Bool where
    Dupl' (f ': l) = Or (Dupl f l) (Dupl' l)
    Dupl' '[]      = False

type family Find (f :: (* -> *) -> * -> *) (l :: [(* -> *) -> * -> *]) :: Bool where
    Find f (g ': l) = Or (Find' f g) (Find f l)
    Find f '[]       = False

type family Find' (f :: (* -> *) -> * -> *) (g :: (* -> *) -> * -> *) :: Bool where
    Find' f (g1 :+: g2) = Or (Find' f g1) (Find' f g2)
    Find' f f = True
    Find' f g = False


class NoDupl f g s
instance NoDupl f g False

-- | The :<: constraint is a conjunction of two constraints. The first
-- one is used to construct the evidence that is used to implement the
-- injection and projection functions. The first constraint alone
-- would allow instances such as @F :+: F :<: F@ or @F :+: (F :+: G)
-- :<: F :+: G@ which have multiple occurrences of the same
-- sub-signature on the left-hand side. Such instances are usually
-- unintended and yield injection functions that are not
-- injective. The second constraint excludes such instances.
type f :<: g = (Subsume (Elem f g) f g , 
                NoDupl f g (AnyDupl f g))


inj :: forall f g a . (f :<: g) => f a :-> g a
inj = inj' (P :: Proxy (Elem f g))

proj :: forall f g a . (f :<: g) => NatM Maybe (g a) (f a)
proj = prj' (P :: Proxy (Elem f g))

type f :=: g = (f :<: g, g :<: f) 



spl :: (f :=: f1 :+: f2) => (f1 a :-> b) -> (f2 a :-> b) -> f a :-> b
spl f1 f2 x = case inj x of 
            Inl y -> f1 y
            Inr y -> f2 y

-- Products

infixr 8 :*:

data (f :*: g) a = f a :*: g a


fst :: (f :*: g) a -> f a
fst (x :*: _) = x

snd :: (f :*: g) a -> g a
snd (_ :*: x) = x

-- Constant Products

infixr 7 :&:

-- | This data type adds a constant product to a
-- signature. Alternatively, this could have also been defined as
-- 
-- @data (f :&: a) (g ::  * -> *) e = f g e :&: a e@
-- 
-- This is too general, however, for example for 'productHHom'.

data (f :&: a) (g ::  * -> *) e = f g e :&: a


instance (HFunctor f) => HFunctor (f :&: a) where
    hfmap f (v :&: c) = hfmap f v :&: c

instance (HFoldable f) => HFoldable (f :&: a) where
    hfold (v :&: _) = hfold v
    hfoldMap f (v :&: _) = hfoldMap f v
    hfoldr f e (v :&: _) = hfoldr f e v
    hfoldl f e (v :&: _) = hfoldl f e v
    hfoldr1 f (v :&: _) = hfoldr1 f v
    hfoldl1 f (v :&: _) = hfoldl1 f v


instance (HTraversable f) => HTraversable (f :&: a) where
    htraverse f (v :&: c) =  (:&: c) <$> (htraverse f v)
    hmapM f (v :&: c) = liftM (:&: c) (hmapM f v)

-- | This class defines how to distribute an annotation over a sum of
-- signatures.
class DistAnn (s :: (* -> *) -> * -> *) p s' | s' -> s, s' -> p where
    -- | This function injects an annotation over a signature.
    injectA :: p -> s a :-> s' a
    projectA :: s' a :-> (s a O.:&: p)


class RemA (s :: (* -> *) -> * -> *) s' | s -> s'  where
    remA :: s a :-> s' a


instance (RemA s s') => RemA (f :&: p :+: s) (f :+: s') where
    remA (Inl (v :&: _)) = Inl v
    remA (Inr v) = Inr $ remA v


instance RemA (f :&: p) f where
    remA (v :&: _) = v


instance DistAnn f p (f :&: p) where

    injectA p v = v :&: p

    projectA (v :&: p) = v O.:&: p


instance (DistAnn s p s') => DistAnn (f :+: s) p ((f :&: p) :+: s') where
    injectA p (Inl v) = Inl (v :&: p)
    injectA p (Inr v) = Inr $ injectA p v

    projectA (Inl (v :&: p)) = (Inl v O.:&: p)
    projectA (Inr v) = let (v' O.:&: p) = projectA v
                        in  (Inr v' O.:&: p)
