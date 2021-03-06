module Query ( parse
             , perform ) where

import qualified Data.Map as Map
import Types
import Lexer as Lexer
import Index as Index

type Prefix = String

data Query = Passage [Word]
           | Wildcard Prefix
           | And [Word]
           | Exclusion Query [Word]

type QueryMap = Map.Map FilePath [(Word, Positions)]


parse :: String -> Query
parse str = Passage $ Lexer.tokenize str


perform :: Query -> IndexMap -> [(FilePath, Int)]
perform (Passage words) index = case result of
    Just map -> filter (\x -> snd x > 0) $ Map.toList map
    Nothing  -> []
    where
        allOccurrences = map (\w -> (w, Index.find w index)) words
        queryMap = foldr insert Map.empty allOccurrences
        filteredMap = Map.filter (\wordList -> length words == length wordList) queryMap
        result = Map.traverseWithKey countOccurrences filteredMap

insert :: (Word, [(FilePath, Positions)]) -> QueryMap -> QueryMap
insert (word, occurrences) map = foldr insert' map occurrences
    where
        insert' :: (FilePath, Positions) -> QueryMap -> QueryMap
        insert' (path, positions) map = Map.insertWith (++) path [(word, positions)] map

countOccurrences :: FilePath -> [(Word, Positions)] -> Maybe Int
countOccurrences _ wordsPos = Just $ count' $ map snd wordsPos

count' :: [[Int]] -> Int
count' [] = 0
count' (l:[]) = length l
count' (l1:l2:ls) = count' $ (filterSuccessors l1 l2):ls

filterSuccessors :: [Int] -> [Int] -> [Int]
filterSuccessors l1 l2 = filter (\x -> any (pred x ==) l1) l2
