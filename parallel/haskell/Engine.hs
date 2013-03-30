module Engine ( processFiles
              , search) where

import Control.Monad ( forM_ )
import Control.Concurrent ( forkIO )
import Control.Concurrent.STM
import Control.Concurrent.STM.SSem as Sem
import Control.DeepSeq

import Lexer
import Index
import Query
import Types
import Buffer
import Logger

-- (max files per index, TChan (remaing slots, index))
type IndexBuffer = (Int, TChan (Int, Index))

createQueryIndex :: Index -> Buffer QueryIndex -> LogBuffer -> IO ()
createQueryIndex index buffer logBuffer = do
    queryIndex <- return $!! Index.buildQueryIndex index
    atomically $ writeBuffer buffer queryIndex
    Logger.subIndexCompleted logBuffer


processRemaingIndices :: TChan (Int, Index) -> Buffer QueryIndex -> LogBuffer -> IO ()
processRemaingIndices indexBuffer queryIndexBuffer logBuffer = do
    response <- atomically $ tryReadTChan indexBuffer
    case response of
        Nothing -> atomically $ enableFlag queryIndexBuffer
        Just (_, index) -> do
            createQueryIndex index queryIndexBuffer logBuffer
            processRemaingIndices indexBuffer queryIndexBuffer logBuffer


waiter :: SSem -> TChan (Int, Index) -> Buffer QueryIndex -> LogBuffer -> IO ()
waiter finishProcessing indexBuffer queryIndexBuffer logBuffer = do
    atomically $ Sem.wait finishProcessing
    processRemaingIndices indexBuffer queryIndexBuffer logBuffer


processFile' :: Int -> FilePath -> IndexBuffer -> Buffer QueryIndex -> LogBuffer -> IO ()
processFile' taskId filePath (maxFiles, indexBuffer) queryIndexBuffer logBuffer = do
    content <- readFile filePath
    (words', occurrences) <- return $!! Lexer.processContent content

    (fileCounter, index) <- atomically $ readTChan indexBuffer
    let newIndex = Index.insert (filePath, occurrences) index

    Logger.fileProcessed logBuffer taskId filePath words'

    if (fileCounter - 1 > 0)
        then atomically $ writeTChan indexBuffer (fileCounter - 1, newIndex)
        else do
            _ <- forkIO $ createQueryIndex newIndex queryIndexBuffer logBuffer
            atomically $ writeTChan indexBuffer (maxFiles, Index.empty)


processFile :: Int -> Buffer FilePath -> IndexBuffer -> Buffer QueryIndex -> LogBuffer -> SSem -> IO ()
processFile taskId fileBuffer (maxFiles, indexBuffer) queryIndexBuffer logBuffer finishProcessing = do
    next <- atomically $ readBuffer fileBuffer
    case next of
        Nothing -> atomically $ Sem.signal finishProcessing
        Just filePath -> do
            processFile' taskId filePath (maxFiles, indexBuffer) queryIndexBuffer logBuffer
            processFile taskId fileBuffer (maxFiles, indexBuffer) queryIndexBuffer logBuffer finishProcessing


processFiles :: Int -> Int -> Int -> Buffer FilePath -> Buffer QueryIndex -> LogBuffer -> IO ()
processFiles initialSubIndices maxFiles nWorkers fileBuffer queryIndexBuffer logBuffer = do
    indexBuffer <- atomically newTChan
    forM_ [1..initialSubIndices] $ \_ ->
        atomically (writeTChan indexBuffer (maxFiles, Index.empty))

    finishProcessing <- atomically $ Sem.new (1 - nWorkers)
    forM_ [1..nWorkers] $ \taskId ->
        forkIO $ processFile taskId fileBuffer (maxFiles, indexBuffer) queryIndexBuffer logBuffer finishProcessing

    _ <- forkIO $ waiter finishProcessing indexBuffer queryIndexBuffer logBuffer
    return ()


search' :: Query -> QueryIndex -> QueryResult -> QueryResult
search' query index allResults = allResults ++ (Query.perform query index)

search :: Query -> Buffer QueryIndex -> QueryResult -> LogBuffer -> IO ()
search query indexBuffer result logBuffer = do
    response <- atomically $ readBuffer indexBuffer
    case response of
        Nothing -> Logger.searchPerformed logBuffer result
        Just index -> do
            newResult <- return $!! search' query index result
            Logger.queryPerformed logBuffer query
            search query indexBuffer newResult logBuffer
