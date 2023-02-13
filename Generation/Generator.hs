import Data.Char
import Data.List
import qualified Data.Lambda as L
import qualified Data.Lambda.Random.MixedSystem as M
import Data.Lambda.Model 
import Data.Lambda.Random

-- numbers chosen as parameters are a bit arbitrary, since their significance is hard to understand from the docs
plainNatSampler = M.rejectionSampler natural 100 (1.0e-9 :: Double)

-- a sampler for CLOSED and REDUCIBLE lambda terms
sampler :: IO L.Lambda
sampler = filterClosedIO (\t -> case t of 
                            (L.App (L.Abs (L.Abs _)) _) -> False
                            (L.App _ _)                 -> True
                            _           -> False) 
                         plainNatSampler 100 1000

-- an ADT which models lambda terms with named variables
data LambdaVar = Var String
               | Abs String LambdaVar
               | App LambdaVar LambdaVar


instance Show LambdaVar where
    show (Var x) = x
    show (Abs x t) = "λ" ++ x ++ ".(" ++ show t ++ ")"
    show (App lt rt) = "(" ++ show lt ++ ") (" ++ show rt ++ ")"

-- given an identifier, compute the next identifier in a lexicographical order
next :: String -> String
next [] = "a"
next s = let l = last s
          in case l of
            'z' -> next (init s) ++ "a"
            c   -> init s ++ [chr (ord c + 1)]

--convert a lambda term (with DeBruijn indices) to a Lambda term using named variables instead
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

--convert a lambda term with DeBruijn indices to its JSON representation, embedded in plain text
lambdaToJSON :: L.Lambda -> String
lambdaToJSON (L.Var i) = "{\"i\": " ++ show (L.toInt i) ++ "}"
lambdaToJSON (L.Abs t) = "{\"lam\": " ++ lambdaToJSON t ++ "}"
lambdaToJSON (L.App t1 t2) = "{\"app\": {\"fun\": " ++ lambdaToJSON t1 ++ ", \"arg\": " ++ lambdaToJSON t2 ++ "}}"

--convert a lambda term with named variables to its JSON representation, embedded in plain text
lambdaVarToJSON :: LambdaVar -> String
lambdaVarToJSON (Var x) = "{\"var\": \"" ++ x ++ "\"}"
lambdaVarToJSON (Abs x t) = "{\"lam\": {\"var\": \"" ++ x ++ "\", \"body\": " ++ lambdaVarToJSON t ++ "}}"
lambdaVarToJSON (App t1 t2) = "{\"app\": {\"fun\": " ++ lambdaVarToJSON t1 ++ ", \"arg\": " ++ lambdaVarToJSON t2 ++ "}}"

--write specified number of generated terms to files
main :: IO ()
main = do 
    terms <- sequence $ replicate 100 sampler
    writeFile "Generation/secd_terms.json" $ intercalate "\n" $ map (lambdaVarToJSON . toLambdaVar) terms
    writeFile "Generation/krivine_terms.json" $ intercalate "\n" $ map lambdaToJSON terms