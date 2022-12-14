module Eval where

import Control.Monad ( liftM )
import Control.Monad.Except ( MonadError(throwError), MonadIO(liftIO) )
import Data.Maybe ( isNothing )

import LispVal
import LispError ( ThrowsError, LispError(BadSpecialForm, NotFunction, NumArgs) )
import LispPrimitive ( primitives )
import Env ( bindVars, liftThrows, Env, IOThrowsError, defineVar )
import IOPrimitive ( load )

eval :: Env -> LispVal -> IOThrowsError LispVal
eval _ val@(String _)                             = return val
eval _ val@(Atom _)                               = return val
eval _ val@(Number _)                             = return val
eval _ val@(Bool _)                               = return val
eval _ val@(Character _)                          = return val
eval _ (List [Atom "quote", val])                 = return val
eval env (List [Atom "backquote", List vals])     = List <$> mapM (evalBackquote env) vals
     where evalBackquote env (List [Atom "unquote", val]) = eval env val
           evalBackquote env val                          = eval env $ List [Atom "quote", val]

{- (DONE)
Instead of treating any non-false value as true, change the definition 
of if so that the predicate accepts only Bool values and throws an error 
on any others.
-}
eval env (List [Atom "if", pred, conseq, alt]) =
     do result <- eval env pred
        case result of
             Bool True  -> eval env conseq
             Bool False -> eval env alt
             badForm    -> throwError $ BadSpecialForm "Unrecognized special form" badForm

eval env (List (Atom "cond" : clauses)) = evalCond env clauses
     where evalCond env [List [pred@(Bool _), action]]         = eval env action
           evalCond env [List [Atom "else", action]]           = eval env action
           evalCond env (List [pred, Atom "=>", action] : cs)  = evalCond env (List [pred, action] : cs)
           evalCond env (List [pred, action] : cs)             = do result <- eval env pred
                                                                    case result of Bool True -> eval env action
                                                                                   Bool False -> evalCond env cs
                                                                                   badForm    -> throwError $ BadSpecialForm "Unrecognized special form" badForm 
           evalCond env [badForm]                              = throwError $ BadSpecialForm "Unrecognized special form" badForm 

eval env (List (Atom "define" : List (Atom var : params) : body)) =
     makeNormalFunc env params body >>= defineVar env var

eval env (List (Atom "define" : DottedList (Atom var : params) varargs : body)) =
     makeVarArgs varargs env params body >>= defineVar env var

eval env (List (Atom "lambda" : List params : body)) =
     makeNormalFunc env params body

eval env (List (Atom "lambda" : DottedList params varargs : body)) =
     makeVarArgs varargs env params body
     
eval env (List (Atom "lambda" : varargs@(Atom _) : body)) =
     makeVarArgs varargs env [] body

eval env (List (function : args)) = do
     func <- eval env function
     argVals <- mapM (eval env) args
     apply func argVals

eval env (List [Atom "load", String filename]) =
     load filename >>= (last . mapM <$> eval env)

eval _ badForm                               = throwError $ BadSpecialForm "Unrecognized special form" badForm

apply :: LispVal -> [LispVal] -> IOThrowsError LispVal
apply (PrimitiveFunc func) args = liftThrows $ func args
apply (Func params varargs body closure) args =
      if num params /= num args && isNothing varargs
         then throwError $ NumArgs (num params) args
         else liftIO (bindVars closure $ zip params args) >>= bindVarArgs varargs >>= evalBody
      where remainingArgs = drop (length params) args
            num = toInteger . length
            evalBody env = last <$> mapM (eval env) body
            bindVarArgs arg env = case arg of
                Just argName -> liftIO $ bindVars env [(argName, List remainingArgs)]
                Nothing -> return env

apply (IOFunc func) args = func args