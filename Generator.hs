import Data.Char
import Data.List
import qualified Data.Lambda as L
import qualified Data.Lambda.Random.MixedSystem as M
import Data.Lambda.Model 
import Data.Lambda.Random

plainNatSampler = M.rejectionSampler natural 100 (1.0e-9 :: Double)

sampler :: IO L.Lambda
sampler = filterClosedIO (\t -> case t of 
                            (L.App _ _) -> True
                            _           -> False) 
                         plainNatSampler 10 100

data LambdaVar = Var String
               | Abs String LambdaVar
               | App LambdaVar LambdaVar


instance Show LambdaVar where
    show (Var x) = x
    show (Abs x t) = "λ" ++ x ++ ".(" ++ show t ++ ")"
    show (App lt rt) = "(" ++ show lt ++ ") (" ++ show rt ++ ")"

next :: String -> String
next [] = "a"
next s = let l = last s
          in case l of
            'z' -> next (init s) ++ "a"
            c   -> init s ++ [chr (ord c + 1)]

toLambdaVar :: L.Lambda -> LambdaVar
toLambdaVar t = helper t (iterate next "a") []
  where
    helper :: L.Lambda -> [String] -> [String] -> LambdaVar
    helper (L.Var L.Z)     _         varStack = Var $ head varStack
    helper (L.Var (L.S i)) freeNames varStack = helper (L.Var i) freeNames $ tail varStack
    helper (L.Abs t)       freeNames varStack = 
        let v = head freeNames
         in Abs v (helper t (tail freeNames) (v:varStack))
    helper (L.App t1 t2)   freeNames varStack = 
        App (helper t1 freeNames varStack) (helper t2 freeNames varStack)

lambdaToJSON :: L.Lambda -> String
lambdaToJSON (L.Var i) = "{\"i\": " ++ show (L.toInt i) ++ "}"
lambdaToJSON (L.Abs t) = "{\"lam\": " ++ lambdaToJSON t ++ "}"
lambdaToJSON (L.App t1 t2) = "{\"app\": {\"fun\": " ++ lambdaToJSON t1 ++ ", \"arg\": " ++ lambdaToJSON t2 ++ "}}"


lambdaVarToJSON :: LambdaVar -> String
lambdaVarToJSON (Var x) = "{\"var\": \"" ++ x ++ "\"}"
lambdaVarToJSON (Abs x t) = "{\"lam\": {\"var\": \"" ++ x ++ "\", \"body\": " ++ lambdaVarToJSON t ++ "}}"
lambdaVarToJSON (App t1 t2) = "{\"app\": {\"fun\": " ++ lambdaVarToJSON t1 ++ ", \"arg\": " ++ lambdaVarToJSON t2 ++ "}}"

main :: IO ()
main = do 
    terms <- sequence $ replicate 10 sampler
    writeFile "term_input.json" $ intercalate "\n" $ map (lambdaVarToJSON . toLambdaVar)  terms