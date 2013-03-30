module Index ( empty
             , insert
             , buildQueryIndex
             , find ) where

import qualified Data.Map as Map
import qualified Data.IntMap as IMap
import qualified Data.Array as Array
import Data.Char ( ord )
import Types

empty :: Index
empty = Index 0 IMap.empty

insert :: (FilePath, Occurrences) -> Index -> Index
insert (file, o) (Index n map') = Index (n + 1) $ Map.foldrWithKey (mergeIndices file) map' o

mergeIndices :: FilePath -> Word -> Positions -> IMap.IntMap Vocabulary -> IMap.IntMap Vocabulary
mergeIndices _ [] _ _ = IMap.empty
mergeIndices file word@(c:_) ps indexMap = IMap.insertWith mergeVocabularies (ord c) vocabulary indexMap
    where
        vocabulary = Map.singleton word [(file, ps)]

mergeVocabularies :: Vocabulary -> Vocabulary -> Vocabulary
mergeVocabularies old new = Map.unionWith (++) old new

buildQueryIndex :: Index -> QueryIndex
buildQueryIndex (Index n map') = QueryIndex n $ Array.accumArray mergeVocabularies Map.empty (ord '0', ord 'z') (IMap.assocs map')

find :: Word -> QueryIndex -> [(FilePath, Positions)]
find [] _ = []
find word@(c:_) (QueryIndex _ array') = Map.findWithDefault [] word vocabulary
    where
        vocabulary =  array' Array.! (ord c)
