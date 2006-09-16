> module FileNameUtils          ( extension
>                               , filename
>                               , basename
>                               , dirname
>                               , expandPath
>                               , chaseFile
>                               , modifySearchPath
>                               , deep, absPath, relPath, env
>                               ) where
>
> import Prelude hiding         (  catch )
> import System.IO
> import System.Directory
> import System.Environment
> import Data.List
> import Control.Monad (filterM)
> import Control.Exception      (  try, catch )

> type FileName                 =  String

> directorySeparators           =  "/"
> directorySeparator            =  '/'
> environmentSeparators         =  ";:"

A searchpath can be added to the front or to the back of the current path
by pre- or postfixing it with a path separator. Otherwise the new search
path replaces the current one.

> modifySearchPath              :: [FileName] -> String -> [FileName]
> modifySearchPath p np
>   | any (\x -> x == head np) environmentSeparators = p ++ split
>   | any (\x -> x == last np) environmentSeparators = split ++ p
>   | otherwise                                      = split
>   where split = splitOn environmentSeparators np

> relPath                       :: [String] -> FileName
> relPath ps                    =  concat (intersperse [directorySeparator] ps)

> absPath                       :: [String] -> FileName
> absPath ps                    =  directorySeparator : relPath ps

> isAbsolute                    :: FileName -> Bool
> isAbsolute []                 =  False
> isAbsolute xs                 =  head xs `elem` directorySeparators

> isRelative                    :: FileName -> Bool
> isRelative                    =  not . isAbsolute

> deep                          :: FileName -> FileName
> deep                          =  (++(replicate 2 directorySeparator))

> env                           :: String -> FileName
> env x                         =  "{" ++ x ++ "}"

> extension                     :: FileName -> Maybe String
> extension fn                  =  f False [] fn 
>   where
>   f found acc [] | found      =  Just (reverse acc)
>                  | not found  =  Nothing 
>   f found acc ('.':cs)        =  f True  []      cs
>   f found acc (c  :cs)        =  f found (c:acc) cs

> dirname                       :: FileName -> String
> dirname fn                    =  f [] [] fn
>   where
>   f res acc []                =  reverse res
>   f res acc (c:cs) 
>     | c `elem` directorySeparators 
>                               =  f (c : acc ++ res) [] cs
>     | otherwise               =  f res       (c : acc) cs

> filename                      :: FileName -> String
> filename fn                   =  f [] fn 
>   where
>   f acc []                    =  reverse acc 
>   f acc (c:cs)
>     | c `elem` directorySeparators
>                               =  f []      cs
>     | otherwise               =  f (c:acc) cs

> basename                      :: FileName -> String
> basename fn                   =  takeWhile (/= '.') (filename fn)  

|expandPath| does two things: it replaces curly braced strings with
environment entries, if present; furthermore, if the path ends with
more than one directory separator, all subpaths are added ...

> expandPath                    :: [String] -> IO [String]
> expandPath s                  =  do let s' = concatMap (splitOn environmentSeparators) s
>                                     s'' <- mapM expandEnvironment s'
>                                     s''' <- mapM findSubPaths (concat s'')
>                                     return (nub $ concat s''')

> findSubPaths                  :: String -> IO [String]
> findSubPaths ""               =  return []
> findSubPaths s                =  let rs = reverse s
>                                      (sep,rs') = span (`elem` directorySeparators) rs
>                                      s'   = reverse rs'
>                                      sep' = reverse sep
>                                  in  if   null s' 
>                                      then return [[head sep']] {- we don't descend from root -}
>                                      else if   length sep < 2
>                                           then return [s]
>                                           else descendFrom s'

> descendFrom                   :: String -> IO [String]
> descendFrom s                 =  catch (do  d <- getDirectoryContents s
>                                             {- no hidden files, no parents -}
>                                             let d' = map (\x -> s ++ [directorySeparator] ++ x)
>                                                    . filter ((/='.') . head) . filter (not . null) $ d
>                                             d'' <- filterM doesDirectoryExist d'
>                                             d''' <- mapM descendFrom d''
>                                             return (s : concat d''')
>                                        )
>                                        (const $ return [s])

> expandEnvironment             :: String -> IO [String]
> expandEnvironment s           =  case break (=='{') s of
>                                    (s',"")    -> return [s]
>                                    (s','{':r) -> case break (=='}') r of
>                                                    (e,"") -> return [s]
>                                                    (e,'}':r') -> findEnvironment e s' r'
>   where findEnvironment       :: String -> String -> String -> IO [String]
>         findEnvironment e a o =  do er <- try (getEnv e)
>                                     return $ either (const [])
>                                                     (map (\x -> a ++ x ++ o) . splitOn environmentSeparators)
>                                                     er

> splitOn                       :: String -> String -> [String]
> splitOn b s                   =  case dropWhile (`elem` b) s of
>                                    "" -> []
>                                    s' -> w : splitOn b s''
>                                            where (w,s'') = break (`elem` b) s'

> chaseFile                     :: [String]    {- search path -}
>                               -> FileName -> IO (String,FileName)
> chaseFile p fn | isAbsolute fn=  t fn
>                | p == []      =  chaseFile ["."] fn
>                | otherwise    =  s $ map (\d -> t (md d ++ fn)) p
>   where
>   md cs | last cs `elem` directorySeparators
>                               =  cs
>         | otherwise           =  cs ++ [directorySeparator]
>   t f                         =  catch (readFile f >>= \x -> return (x,f))
>                                        (\_ -> ioError $ userError $ "File `" ++ fn ++ "' not found.\n")
>   s []                        =  ioError 
>                               $  userError $ "File `" ++ fn ++ "' not found in search path:\n" ++ showpath
>   s (x:xs)                    =  catch x (\_ -> s xs)
>   showpath                    =  concatMap (\x -> "   " ++ x ++ "\n") p
