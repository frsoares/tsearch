module Logger ( LogBuffer
              , Logger.log
              , fileProcessed
              , subIndexCompleted
              , queryPerformed
              , searchPerformed
              , listen
              , finish ) where

import System.IO
import Text.Printf
import Control.Monad ( forM_ )
import Control.Concurrent.STM ( atomically )
import Data.List ( sortBy )
import Data.Monoid ( mconcat )
import Data.Ord ( comparing )

import Query
import Buffer

data Event = FileProcessed Int FilePath Int Int
           | SubIndexCompleted Int Int
           | QueryPerformed Query Int
           | SearchPerformed [(FilePath, Int)]
           | Message String

type LogBuffer = Buffer Event

-- (kbytes, files, words)
type InfoState = (Double, Int, Int)

fileProcessed :: Buffer Event -> Int -> FilePath -> Int -> Int -> IO ()
fileProcessed buffer tId path ws iWs =  atomically $ writeBuffer buffer $ FileProcessed tId path ws iWs

subIndexCompleted :: Buffer Event -> Int -> Int -> IO ()
subIndexCompleted buffer iId nFiles= atomically $ writeBuffer buffer $ SubIndexCompleted iId nFiles

queryPerformed :: Buffer Event -> Query -> Int -> IO ()
queryPerformed buffer q iId = atomically $ writeBuffer buffer $ QueryPerformed q iId

searchPerformed :: Buffer Event -> [(FilePath, Int)] -> IO ()
searchPerformed buffer = atomically . (writeBuffer buffer) . SearchPerformed

log :: Buffer Event -> String -> IO ()
log buffer = atomically . (writeBuffer buffer) . Message

finish :: Buffer Event -> IO ()
finish = atomically . enableFlag

listen :: Buffer Event -> IO ()
listen buffer = listen' buffer (0.0, 0, 0)

listen' :: Buffer Event -> InfoState -> IO ()
listen' buffer state = do
    response <- atomically $ readBuffer buffer
    case response of
        Nothing -> return ()
        Just event -> do
            newState <- processEvent event state
            listen' buffer newState

printProgress :: Int -> FilePath -> InfoState -> Int -> IO ()
printProgress taskId path (bytes, totalFiles, totalWords) indexedWords' = do
    putStrLn "-----"
    putStrLn $ "[Thread " ++ (show taskId) ++ "]"
    putStrLn $ "New file processed: " ++ path
    putStrLn $ printf "Kbytes processed so far: %.3f" bytes
    putStrLn $ "Files processed so far: " ++ (show totalFiles)
    putStrLn $ "Words found so far: " ++ (show totalWords)
    putStrLn $ "Words in the index: " ++ (show indexedWords')

processEvent :: Event -> InfoState -> IO InfoState
processEvent (FileProcessed taskId path words' indexedWords') (bytes, totalFiles, totalWords) = do
    size <- withFile path ReadMode hFileSize
    let newSize = bytes + (fromIntegral size) / 1024
    let newState = (newSize, totalFiles + 1, totalWords + words')
    printProgress taskId path newState indexedWords'
    return newState

processEvent (SubIndexCompleted indexId nFiles) state = do
    putStrLn "-----"
    putStrLn $ "Sub-index " ++ (show indexId) ++ " completed. (" ++ (show nFiles) ++ " files)"
    return state

processEvent (QueryPerformed query indexId) state = do
    putStrLn "-----"
    putStrLn $ "Query \"" ++ (show query) ++ "\" performed on sub-index " ++ (show indexId)
    return state

processEvent (SearchPerformed result) state = do
    let orderedResult = sortBy (mconcat [flip $ comparing snd, comparing fst]) result
    putStrLn "-----"
    putStrLn "RESULT:"
    forM_ orderedResult $ \(filePath, total) ->
        putStrLn $ "File: " ++ filePath ++ ".   Occurrences: " ++ (show total)
    return state

processEvent (Message msg) state = do
    putStrLn "-----"
    putStrLn msg
    return state
