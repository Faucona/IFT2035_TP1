-- TP-1  --- Implantation d'une sorte de Lisp          -*- coding: utf-8 -*-
{-# OPTIONS_GHC -Wall #-}
--
-- Ce fichier défini les fonctionalités suivantes:
-- - Analyseur lexical
-- - Analyseur syntaxique
-- - Pretty printer
-- - Implantation du langage

---------------------------------------------------------------------------
-- Importations de librairies et définitions de fonctions auxiliaires    --
---------------------------------------------------------------------------

import Text.ParserCombinators.Parsec -- Bibliothèque d'analyse syntaxique.
import Data.Char                -- Conversion de Chars de/vers Int et autres.
import System.IO                -- Pour stdout, hPutStr

---------------------------------------------------------------------------
-- 1ère représentation interne des expressions de notre language         --
---------------------------------------------------------------------------
data Sexp = Snil                        -- La liste vide
          | Scons Sexp Sexp             -- Une paire
          | Ssym String                 -- Un symbole
          | Snum Int                    -- Un entier
          -- Génère automatiquement un pretty-printer et une fonction de
          -- comparaison structurelle.
          deriving (Show, Eq)

-- Exemples:
-- (+ 2 3)  ==  (((() . +) . 2) . 3)
--          ==>  Scons (Scons (Scons Snil (Ssym "+"))
--                            (Snum 2))
--                     (Snum 3)
--                   
-- (/ (* (- 68 32) 5) 9)
--     ==  (((() . /) . (((() . *) . (((() . -) . 68) . 32)) . 5)) . 9)
--     ==>
-- Scons (Scons (Scons Snil (Ssym "/"))
--              (Scons (Scons (Scons Snil (Ssym "*"))
--                            (Scons (Scons (Scons Snil (Ssym "-"))
--                                          (Snum 68))
--                                   (Snum 32)))
--                     (Snum 5)))
--       (Snum 9)

---------------------------------------------------------------------------
-- Analyseur lexical                                                     --
---------------------------------------------------------------------------

pChar :: Char -> Parser ()
pChar c = do { _ <- char c; return () }

-- Les commentaires commencent par un point-virgule et se terminent
-- à la fin de la ligne.
pComment :: Parser ()
pComment = do { pChar ';'; _ <- many (satisfy (\c -> not (c == '\n')));
                (pChar '\n' <|> eof); return ()
              }
-- N'importe quelle combinaison d'espaces et de commentaires est considérée
-- comme du blanc.
pSpaces :: Parser ()
pSpaces = do { _ <- many (do { _ <- space ; return () } <|> pComment);
               return () }

-- Un nombre entier est composé de chiffres.
integer     :: Parser Int
integer = do c <- digit
             integer' (digitToInt c)
          <|> do _ <- satisfy (\c -> (c == '-'))
                 n <- integer
                 return (- n)
    where integer' :: Int -> Parser Int
          integer' n = do c <- digit
                          integer' (10 * n + (digitToInt c))
                       <|> return n

pSymchar :: Parser Char
pSymchar    = alphaNum <|> satisfy (\c -> c `elem` "!@$%^&*_+-=:|/?<>")
pSymbol :: Parser Sexp
pSymbol= do { s <- many1 (pSymchar);
              return (case parse integer "" s of
                        Right n -> Snum n
                        _ -> Ssym s)
            }

---------------------------------------------------------------------------
-- Analyseur syntaxique                                                  --
---------------------------------------------------------------------------

-- La notation "'E" est équivalente à "(shorthand-quote E)"
-- La notation "`E" est équivalente à "(shorthand-backquote E)"
-- La notation ",E" est équivalente à "(shorthand-comma E)"
pQuote :: Parser Sexp
pQuote = do { c <- satisfy (\c -> c `elem` "'`,"); pSpaces; e <- pSexp;
              return (Scons
                      (Scons Snil
                             (Ssym (case c of
                                     ',' -> "shorthand-comma"
                                     '`' -> "shorthand-backquote"
                                     _   -> "shorthand-quote")))
                      e) }

-- Une liste (Tsil) est de la forme ( [e .] {e} )
pTsil :: Parser Sexp
pTsil = do _ <- char '('
           pSpaces
           (do { _ <- char ')'; return Snil }
            <|> do hd <- (do e <- pSexp
                             pSpaces
                             (do _ <- char '.'
                                 pSpaces
                                 return e
                              <|> return (Scons Snil e)))
                   pLiat hd)
    where pLiat :: Sexp -> Parser Sexp
          pLiat hd = do _ <- char ')'
                        return hd
                 <|> do e <- pSexp
                        pSpaces
                        pLiat (Scons hd e)

-- Accepte n'importe quel caractère: utilisé en cas d'erreur.
pAny :: Parser (Maybe Char)
pAny = do { c <- anyChar ; return (Just c) } <|> return Nothing

-- Une Sexp peut-être une liste, un symbol ou un entier.
pSexpTop :: Parser Sexp
pSexpTop = do { pTsil <|> pQuote <|> pSymbol
                <|> do { x <- pAny;
                         case x of
                           Nothing -> pzero
                           Just c -> error ("Unexpected char '" ++ [c] ++ "'")
                       }
              }

-- On distingue l'analyse syntaxique d'une Sexp principale de celle d'une
-- sous-Sexp: si l'analyse d'une sous-Sexp échoue à EOF, c'est une erreur de
-- syntaxe alors que si l'analyse de la Sexp principale échoue cela peut être
-- tout à fait normal.
pSexp :: Parser Sexp
pSexp = pSexpTop <|> error "Unexpected end of stream"

-- Une séquence de Sexps.
pSexps :: Parser [Sexp]
pSexps = do pSpaces
            many (do e <- pSexpTop
                     pSpaces
                     return e)

-- Déclare que notre analyseur syntaxique peut-être utilisé pour la fonction
-- générique "read".
instance Read Sexp where
    readsPrec _ s = case parse pSexp "" s of
                      Left _ -> []
                      Right e -> [(e,"")]

---------------------------------------------------------------------------
-- Sexp Pretty Printer                                                   --
---------------------------------------------------------------------------

showSexp' :: Sexp -> ShowS
showSexp' Snil = showString "()"
showSexp' (Snum n) = showsPrec 0 n
showSexp' (Ssym s) = showString s
showSexp' (Scons e1 e2) = showHead (Scons e1 e2) . showString ")"
    where showHead (Scons Snil e') = showString "(" . showSexp' e'
          showHead (Scons e1' e2')
            = showHead e1' . showString " " . showSexp' e2'
          showHead e = showString "(" . showSexp' e . showString " ."

-- On peut utiliser notre pretty-printer pour la fonction générique "show"
-- (utilisée par la boucle interactive de GHCi).  Mais avant de faire cela,
-- il faut enlever le "deriving Show" dans la déclaration de Sexp.
{-
instance Show Sexp where
    showsPrec p = showSexp'
-}

-- Pour lire et imprimer des Sexp plus facilement dans la boucle interactive
-- de Hugs/GHCi:
--readSexp :: String -> Sexp
--readSexp = read
showSexp :: Sexp -> String
showSexp e = showSexp' e ""

---------------------------------------------------------------------------
-- Représentation intermédiaire "Lambda"                                 --
---------------------------------------------------------------------------

type Var = String

-- Type Haskell qui décrit les types Psil.
data Ltype = Lint
           | Larw Ltype Ltype   -- Type "arrow" des fonctions.
           deriving (Show, Eq)

-- Type Haskell qui décrit les expressions Psil.
data Lexp = Lnum Int            -- Constante entière.
          | Lvar Var            -- Référence à une variable.
          | Lhastype Lexp Ltype -- Annotation de type.
          | Lapp Lexp Lexp      -- Appel de fonction, avec un argument.
          | Llet Var Lexp Lexp  -- Déclaration de variable locale.
          | Lfun Var Lexp       -- Fonction anonyme.
          deriving (Show, Eq)

-- Type Haskell qui décrit les déclarations Psil.
data Ldec = Ldec Var Ltype      -- Déclaration globale.
          | Ldef Var Lexp       -- Définition globale.
          deriving (Show, Eq)
          

-- Conversion de Sexp à Lambda --------------------------------------------

s2t :: Sexp -> Ltype
s2t (Ssym "Int") = Lint
s2t (Snum _) = Lint
s2t (Scons t Snil) = s2t t
s2t (Scons Snil t) = s2t t
s2t (Scons (Scons sexp1 (Ssym "->")) sexp2) 
  | Larw (s2t sexp1) (s2t sexp2) == Larw (Larw Lint Lint) Lint = Larw Lint (Larw Lint Lint) 
  | otherwise = Larw (s2t sexp1) (s2t sexp2)
s2t (Scons (Scons (Scons Snil (Ssym "fun")) (Ssym _)) val) = Larw Lint (s2t val)
s2t (Scons (Scons (Scons Snil (Ssym ":")) _) ssym) = (s2t ssym)
s2t (Scons (Scons (Scons Snil (Ssym "def")) (Ssym _)) (Scons (op) val)) 
  | op == Scons Snil (Ssym "+") || op == Scons Snil (Ssym "-") || op == Scons Snil (Ssym "/") || op == Scons Snil (Ssym "*") = Larw Lint (s2t val)
  | containsFun val = Larw Lint (s2t val)
  | otherwise = Lint 
s2t (Scons (Scons (Scons Snil (Ssym _)) (Ssym _)) val) = (s2t val)
s2t (Scons sexp1 sexp2) = Larw (s2t sexp1) (s2t sexp2)
s2t (Ssym "+") = Larw Lint (Larw Lint Lint)
s2t (Ssym "-") = Larw Lint (Larw Lint Lint)
s2t (Ssym "/") = Larw Lint (Larw Lint Lint)
s2t (Ssym "*") = Larw Lint (Larw Lint Lint)
s2t (Ssym "if0") = Larw Lint (Larw Lint (Larw Lint Lint))
s2t se = error ("Unknown Sexp type: " ++ show se)

-- need this function to see if def contains fun
containsFun :: Sexp -> Bool
containsFun (Scons (Scons (Scons Snil (Ssym "fun")) _) _) = True 
containsFun _ = False



s2l :: Sexp -> Lexp
s2l (Snum n) = Lnum n
s2l (Ssym s) = Lvar s
-- ¡¡COMPLÉTER ICI!!
s2l (Scons t Snil) = s2l t
s2l (Scons Snil t) = s2l t
s2l (Scons (Scons sexp1 (Ssym "->")) sexp2) = Lhastype (s2l sexp1) (s2t sexp2)
s2l (Scons (Scons (Scons Snil (Ssym "let")) (Scons Snil (Scons (Scons Snil (Ssym var)) sexp1 ))) sexp2) = Llet var (s2l (sexp1)) (s2l sexp2)--(Lapp (s2l 
s2l (Scons (Scons (Scons Snil (Ssym "dec")) (Ssym var)) val) = Llet var (Lhastype (s2l (Ssym var)) (s2t val) ) (s2l (Ssym var))

s2l (Scons (Scons (Scons Snil (Ssym "def")) (Ssym var)) (Snum val)) = Llet var (s2l (Snum val)) (s2l (Ssym var))

s2l (Scons (Scons (Scons Snil (Ssym "def")) (Ssym var)) val) 
  | val  == Ssym "+" || val  == Ssym "-" || val  == Ssym "/" || val  == Ssym "*" || val == Ssym "if0" =  Llet var (Lhastype (s2l val) (s2t val)) (s2l (Ssym var))
  | var  == "recursive" = Llet var (s2l val) (s2l (Ssym var))
  | otherwise = Llet var (s2l (val))  (s2l (Ssym var) )
s2l (Scons (Scons (Scons Snil (Ssym "fun")) (Ssym var)) val) = Lfun var (s2l val)
s2l (Scons (Scons (Scons Snil (Ssym ":")) val) ssym) = Lhastype (s2l val) (s2t ssym)
s2l (Scons (Scons (Scons Snil (Ssym op)) (sexp1)) sexp2) = Lapp (s2l (sexp1)) (Lapp (s2l (Ssym op)) (s2l sexp2) )
s2l (Scons sexp1 sexp2) = Lapp (s2l sexp1) (s2l sexp2)
s2l se = error ("Expression Psil inconnue: " ++ (showSexp se))

--Scons (Scons (Scons Snil (Ssym "def")) (Ssym "r3")) (Scons (Scons Snil (Ssym "+")) (Snum 2))
s2d :: Sexp -> Ldec
s2d (Scons (Scons (Scons Snil (Ssym "def")) (Ssym v)) e) = Ldef v (s2l e)
-- ¡¡COMPLÉTER ICI!!
s2d (Scons (Scons (Scons Snil (Ssym "dec")) (Ssym v)) e) = Ldec v (s2t e)
s2d se = error ("Déclaration Psil inconnue: " ++ showSexp se)

---------------------------------------------------------------------------
-- Vérification des types                                                --
---------------------------------------------------------------------------

-- Type des tables indexées par des `α` qui contiennent des `β`.
-- Il y a de bien meilleurs choix qu'une liste de paires, mais
-- ça suffit pour notre prototype.
type Map α β = [(α, β)]

-- Transforme une `Map` en une fonctions (qui est aussi une sorte de "Map").
mlookup :: Map Var β -> (Var -> β)
mlookup [] x = error ("Uknown variable: " ++ show x)
mlookup ((x,v) : xs) x' = if x == x' then v else mlookup xs x'

minsert :: Map Var β -> Var -> β -> Map Var β
minsert m x v = (x,v) : m

type TEnv = Map Var Ltype
type TypeError = String

-- L'environment de typage initial.
tenv0 :: TEnv
tenv0 = [("+", Larw Lint (Larw Lint Lint)),
         ("-", Larw Lint (Larw Lint Lint)),
         ("*", Larw Lint (Larw Lint Lint)),
         ("/", Larw Lint (Larw Lint Lint)),
         ("if0", Larw Lint (Larw Lint (Larw Lint Lint)))]

-- `check Γ e τ` vérifie que `e` a type `τ` check :: TEnv -> Lexp -> Ltype -> Maybe TypeError
check :: TEnv -> Lexp -> Ltype -> Maybe TypeError


-- ¡¡COMPLÉTER ICI!!
check tenv (Lvar var) t = 
    let t' = synth ((var, t ) : tenv ) (Lvar var)
    in if t == t' then Nothing
       else if t /= t' then Just ("Erreur variable déjà déclarée avec un autre type")
       else Nothing
       
check tenv e t = 
    let t' = synth tenv e
    in if t == t' then Nothing
       else Just ("Erreur de type: " ++ show t ++ " ≠ " ++ show t')

-- `synth Γ e` vérifie que `e` est typé correctement et ensuite "synthétise"
-- et renvoie son type `τ`.
synth :: TEnv -> Lexp -> Ltype
synth _    (Lnum _) = Lint
synth tenv (Lvar v) = mlookup tenv v
synth tenv (Lhastype e t) =
    case check tenv e t of
      Nothing -> t
      Just err -> error err
-- ¡¡COMPLÉTER ICI!!
synth tenv (Llet x e1 e2) = synth ((x, (synth tenv e1) ) : tenv ) e2

synth tenv (Lapp e1 e2) =
    case (check tenv e1 (synth tenv e1)) of
      Nothing -> case (synth tenv e1) of 
        Larw Lint x -> case (synth tenv e2) of 
          Lint -> x
          _ -> error ("Incapable de trouver le type de: " ++ (show e2))
        _ -> error ("Incapable de trouver le type de: " ++ (show e1))
      Just err -> error err


synth tenv (Lfun var e1) = Larw Lint (synth ((var, Lint ) : tenv ) e1 )


--synth _tenv e = error ("Incapable de trouver le type de: " ++ (show e))



---------------------------------------------------------------------------
-- Évaluateur                                                            --
---------------------------------------------------------------------------

-- Type des valeurs renvoyées par l'évaluateur.
data Value = Vnum Int
           | Vfun VEnv Var Lexp
           | Vop (Value -> Value)

type VEnv = Map Var Value

instance Show Value where
    showsPrec p  (Vnum n) = showsPrec p n
    showsPrec _p (Vfun _ _ _) = showString "<fermeture>"
    showsPrec _p (Vop _) = showString "<fonction>"

-- L'environnement initial qui contient les fonctions prédéfinies.
venv0 :: VEnv
venv0 = [("+", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x + y)))),
         ("-", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x - y)))),
         ("*", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x * y)))),
         ("/", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x `div` y)))),
         ("if0", Vop (\ (Vnum x) ->
                       case x of
                         0 -> Vop (\ v1 -> Vop (\ _ -> v1))
                         _ -> Vop (\ _ -> Vop (\ v2 -> v2)))),
        ("f1", Vop (\(Vnum x) -> Vop (\(Vnum y) -> Vnum (y + 5))))]

-- La fonction d'évaluation principale.
eval :: VEnv -> Lexp -> Value
eval _venv (Lnum n) = Vnum n
eval venv (Lvar x) = mlookup venv x
-- ¡¡COMPLÉTER ICI!!
eval venv (Llet x (Lhastype (Lvar var) t) e2) = Vfun venv x (Lhastype (Lvar var) t )
eval venv (Llet x (Lapp (Lvar var) (Lapp (Lvar var2 ) e1)) e2) = eval (minsert venv var (Vfun venv var2 e1)) e2
eval venv (Llet x e1 e2) = eval (minsert venv x (eval venv e1 ))  e2
eval venv (Lhastype e t) = eval venv e
eval venv (Lapp e1 e2) = case (eval venv e1) of 
  Vop x -> x (eval venv e2)
  _ -> error "operation invalide"
  
eval venv (Lfun var e) = Vfun venv var e

-- Llet "recursive" (Lapp (Lvar "recursive") (Lapp (Lvar "f1") (Lnum 37))) (Lvar "recursive")
--Llet "f1" (Lhastype (Lvar "f1") (Larw Lint (Larw Lint Lint))) (Lvar "f1")
--Llet "r2" (Lhastype (Lvar "+") (Larw Lint (Larw Lint Lint))) (Lvar "r2")
-- État de l'évaluateur.
type EState = ((TEnv, VEnv),       -- Contextes de typage et d'évaluation.
               Maybe (Var, Ltype), -- Déclaration en attente d'une définition.
               [(Value, Ltype)])   -- Résultats passés (en ordre inverse).

-- Évalue une déclaration, y compris vérification des types.
process_decl :: EState -> Ldec -> EState
process_decl (env, Nothing, res) (Ldec x t) = (env, Just (x,t), res)
process_decl (env, Just (x', _), res) (decl@(Ldec _ _)) =
    process_decl (env, Nothing,
                  error ("Manque une définition pour: " ++ x') : res)
                 decl
process_decl ((tenv, venv), Nothing, res) (Ldef x e) =
    -- Le programmeur n'a *pas* fourni d'annotation de type pour `x`.
    let ltype = synth tenv e
        tenv' = minsert tenv x ltype
        val = eval venv e
        venv' = minsert venv x val
    in ((tenv', venv'), Nothing, (val, ltype) : res)
-- ¡¡COMPLÉTER ICI!!
process_decl ((tenv, venv), Just (x, t), res) (Ldef _ e) = 
  if (synth tenv e) == t then 
    let tenv' = minsert tenv x t
        val = eval venv e
        venv' = minsert venv x val
    in ((tenv', venv'), Just (x, t), (val, t) : res)
  else error ("Type incorrect pour la définition de: " ++ x)
        
---------------------------------------------------------------------------
-- Toplevel                                                              --
---------------------------------------------------------------------------

process_sexps :: EState -> [Sexp] -> IO ()
process_sexps _ [] = return ()
process_sexps es (sexp : sexps) =
    let decl = s2d sexp
        (env', pending, res) = process_decl es decl
    in do (hPutStr stdout)
            (concat
             (map (\ (val, ltyp) ->
                   "  " ++ show val ++ " : " ++ show ltyp ++ "\n")
              (reverse res)))
          process_sexps (env', pending, []) sexps

-- Lit un fichier contenant plusieurs Sexps, les évalue l'une après
-- l'autre, et renvoie la liste des valeurs obtenues.
run :: FilePath -> IO ()
run filename
  = do filestring <- readFile filename
       let sexps = case parse pSexps filename filestring of
                     Left err -> error ("Parse error: " ++ show err)
                     Right es -> es
       process_sexps ((tenv0, venv0), Nothing, []) sexps


sexpOf :: String -> Sexp
sexpOf = read

lexpOf :: String -> Lexp
lexpOf = s2l . sexpOf

typeOf :: String -> Ltype
typeOf = synth tenv0 . lexpOf

valOf :: String -> Value
valOf = eval venv0 . lexpOf

main :: IO ()
main = print (eval venv0 (Llet "recursive" (Lapp (Lvar "recursive") (Lapp (Lvar "f1") (Lnum 37))) (Lvar "recursive") ))  


