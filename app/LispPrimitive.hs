{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use head" #-}
module LispPrimitive where

import Control.Monad ( liftM )
import Control.Monad.Except ( MonadError(throwError) )

import LispVal
import LispError ( ThrowsError, LispError(NumArgs, NotFunction, TypeMismatch) )
import Unpacker
import Env

-- Helper functions
makeFunc :: Maybe String -> Env -> [LispVal] -> [LispVal] -> IOThrowsError LispVal
makeFunc varargs env params body = return $ Func (map showVal params) varargs body env

makeNormalFunc :: Env -> [LispVal] -> [LispVal] -> IOThrowsError LispVal
makeNormalFunc = makeFunc Nothing

makeVarArgs :: LispVal -> Env -> [LispVal] -> [LispVal] -> IOThrowsError LispVal
makeVarArgs = makeFunc . Just . showVal

primitiveBindings :: IO Env
primitiveBindings = nullEnv >>= flip bindVars ( map makePrimitiveFunc primitives)
     where makePrimitiveFunc (var, func) = (var, PrimitiveFunc func)


-- Primitives
primitives :: [(String, [LispVal] -> ThrowsError LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("=", numBoolBinop (==)),
              ("<", numBoolBinop (<)),
              (">", numBoolBinop (>)),
              (">=", numBoolBinop (>=)),
              ("<=", numBoolBinop (<=)),
              ("&&", boolBoolBinop (&&)),
              ("||", boolBoolBinop (||)),
              ("string=?", strBoolBinop (==)),
              ("string<?", strBoolBinop (<)),
              ("string>?", strBoolBinop (>)),
              ("string<=?", strBoolBinop (<=)),
              ("string>=?", strBoolBinop (>=)),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("remainder", numericBinop rem),
              ("symbol?", isSymbol),
              ("string?", isString),
              ("number?", isNumber),
              ("char?", isChar),
              ("boolean?", isBool),
              ("symbol->string", symbolToString),
              ("string->symbol", stringToSymbol),
              ("car", car),
              ("cdr", cdr),
              ("cons", cons),
              ("eq?", eqv),
              ("eqv?", eqv),
              ("equal?", equal)]

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> ThrowsError LispVal
numericBinop op           []  = throwError $ NumArgs 2 []
numericBinop op singleVal@[_] = throwError $ NumArgs 2 singleVal
numericBinop op params        = Number . foldl1 op <$> mapM unpackNum params

boolBinop :: (LispVal -> ThrowsError a) -> (a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBinop unpacker op args = if length args /= 2
                                then throwError $ NumArgs 2 args
                                else do left   <- unpacker $ args !! 0
                                        right  <- unpacker $ args !! 1
                                        return $ Bool $ left `op` right

numBoolBinop :: (Integer -> Integer -> Bool) -> [LispVal] -> ThrowsError LispVal
numBoolBinop  = boolBinop unpackNum
strBoolBinop :: (String -> String -> Bool) -> [LispVal] -> ThrowsError LispVal
strBoolBinop  = boolBinop unpackStr
boolBoolBinop :: (Bool -> Bool -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBoolBinop = boolBinop unpackBool

{-
Excercise 3.1.1 (IN CONSTRUCTION)
Add primitives to perform the various type-testing
functions of R5RS: symbol?, string?, number?, etc.
-}

isType :: Unpacker -> [LispVal] -> ThrowsError LispVal
isType (AnyUnpacker unpacker) args = if length args /= 1
                                     then throwError $ NumArgs 1 args
                                     else do return $ case unpacker $ head args of 
                                                           Right _ -> Bool True
                                                           Left  _ -> Bool False

isSymbol, isString, isNumber, isChar, isBool ::  [LispVal] -> ThrowsError LispVal
isSymbol = isType (AnyUnpacker unpackAtom)
isString = isType (AnyUnpacker unpackStr) 
isNumber = isType (AnyUnpacker unpackNum)
isBool   = isType (AnyUnpacker unpackBool) 
isChar   = isType (AnyUnpacker unpackAtom) 

{-
Excercise 3.1.3 (DONE)
Add the symbol-handling functions from R5RS. A symbol is what
we've been calling an Atom in our data constructors
-}

symbolToString, stringToSymbol :: [LispVal] -> ThrowsError LispVal
symbolToString [Atom content]   = return $ String content
stringToSymbol [String content] = return $ Atom content

-- List primitives

car :: [LispVal] -> ThrowsError LispVal
car [List (x : xs)]         = return x
car [DottedList (x : xs) _] = return x
car [badArg]                = throwError $ TypeMismatch "pair" badArg
car badArgList              = throwError $ NumArgs 1 badArgList

cdr :: [LispVal] -> ThrowsError LispVal
cdr [List (x : xs)]         = return $ List xs
cdr [DottedList [_] x]      = return x
cdr [DottedList (_ : xs) x] = return $ DottedList xs x
cdr [badArg]                = throwError $ TypeMismatch "pair" badArg
cdr badArgList              = throwError $ NumArgs 1 badArgList

cons :: [LispVal] -> ThrowsError LispVal
cons [x1, List []]            = return $ List [x1]
cons [x, List xs]             = return $ List $ x : xs
cons [x, DottedList xs xlast] = return $ DottedList (x : xs) xlast 
cons [x1, x2]                 = return $ DottedList [x1] x2 
cons badArgList               = throwError $ NumArgs 2 badArgList

eqv :: [LispVal] -> ThrowsError LispVal
eqv [Bool arg1, Bool arg2]             = return $ Bool $ arg1 == arg2
eqv [Number arg1, Number arg2]         = return $ Bool $ arg1 == arg2
eqv [String arg1, String arg2]         = return $ Bool $ arg1 == arg2
eqv [Atom arg1, Atom arg2]             = return $ Bool $ arg1 == arg2
eqv [DottedList xs x, DottedList ys y] = eqv [List $ xs ++ [x], List $ ys ++ [y]]
eqv [List arg1, List arg2]             = return $ Bool $ (length arg1 == length arg2) && all eqvPair (zip arg1 arg2)
     where eqvPair (x1, x2) = case eqv [x1, x2] of
                                Left err         -> False
                                Right (Bool val) -> val
eqv [_, _]                                 = return $ Bool False
eqv badArgList                             = throwError $ NumArgs 2 badArgList

equal :: [LispVal] -> ThrowsError LispVal
equal [arg1, arg2] = do
      primitiveEquals <- or <$> mapM (unpackEquals arg1 arg2) 
                         [AnyUnpacker unpackNum, AnyUnpacker unpackStr, AnyUnpacker unpackBool]
      eqvEquals <- eqv [arg1, arg2]
      return $ Bool (primitiveEquals || let (Bool x) = eqvEquals in x)
equal badArgList = throwError $ NumArgs 2 badArgList