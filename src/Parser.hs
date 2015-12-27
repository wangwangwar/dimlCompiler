module Parser where

import Text.Parsec
import Text.Parsec.String (Parser)
import Text.Parsec.Language
import qualified Text.Parsec.Expr as Expr

import Control.Applicative hiding (many, (<|>))
import Data.Functor.Identity
import System.IO

import Lexer
import Syntax
import Type

--------------------------------------
-- Parsing Programs from IO
--------------------------------------

-- parses contents of string or file,
-- excluding leading whitespace
contents :: Parser a -> Parser a
contents p = whitespace *> p

-- parses semicolon terminated expression
topLevel :: Parser [DimlExpr]
topLevel = many1 $ expr <* reservedOp ";"

-- parses file
parseFile :: String -> IO ()
parseFile filename = do
    program <- readFile filename
    print $ parseExpr program

-- parses expression without semicolon
parseExpr :: String -> Either ParseError DimlExpr
parseExpr str = parse (contents expr) "<stdin>" str

-- parses program
parseTopLevel :: String -> Either ParseError [DimlExpr]
parseTopLevel str = parse (contents topLevel) "<stdin>" str

--------------------------------------

-- binary and prefix args are written differently, but do the same thing!
binary :: Name -> Expr.Assoc -> (Expr.Operator String () Data.Functor.Identity.Identity DimlExpr)
binary name = Expr.Infix (reservedOp name >> return (BinOp name))

prefix :: Name -> (DimlExpr -> DimlExpr) -> (Expr.Operator String () Data.Functor.Identity.Identity DimlExpr)
prefix name label = Expr.Prefix (reservedOp name *> return (\x -> label x))

apply :: Expr.Operator String () Data.Functor.Identity.Identity DimlExpr
apply = Expr.Infix space Expr.AssocLeft
    where space = Apply
                <$ whitespace
                <* notFollowedBy (choice . map reservedOp $ ops)

builtins :: [Expr.Operator String () Data.Functor.Identity.Identity DimlExpr]
builtins = [ prefix "fst" (Builtins . TupFst), prefix "snd" (Builtins . TupSnd) ]

opTable :: Expr.OperatorTable String () Data.Functor.Identity.Identity DimlExpr
opTable = [ [apply]
          , builtins
          , [ binary "*" Expr.AssocLeft
            , binary "/" Expr.AssocLeft]
          , [ binary "+" Expr.AssocLeft
            , binary "-" Expr.AssocLeft ]
          , [ binary "<" Expr.AssocLeft
            , binary ">" Expr.AssocLeft
            , binary "==" Expr.AssocLeft ]
        ]

annot :: Parser Type
annot = reservedOp ":" *> typeExpr

expr :: Parser DimlExpr
expr = Expr.buildExpressionParser opTable factor

unitExpr :: Parser DimlExpr
unitExpr = Lit DUnit <$ try (reservedOp "()")

intExpr :: Parser DimlExpr
intExpr = Lit . DInt <$> integer

varExpr :: Parser DimlExpr
varExpr = Var <$> identifier

boolExpr :: Parser DimlExpr
boolExpr =  Lit DTrue <$ reserved "true"
        <|> Lit DFalse <$ reserved "false"

funExpr :: Parser DimlExpr
funExpr = do
    try $ reserved "fun"
    name <- identifier
    char '(' >> whitespace
    arg <- identifier
    argTyp <- optionMaybe annot
    char ')' >> whitespace
    retTyp <- optionMaybe annot
    reservedOp "="
    body <- expr
    return $ Fun name arg argTyp retTyp body

lamExpr :: Parser DimlExpr
lamExpr = Lam <$> try arg <*> optionMaybe annot <*> body
    where arg  = reservedOp "\\" *> identifier
          body = reservedOp "->" *> expr

ifExpr :: Parser DimlExpr
ifExpr = If <$> try e1 <*> e2 <*> e3
    where e1 = reserved "if" *> expr
          e2 = reserved "then" *> expr
          e3 = reserved "else" *> expr

-- explicitly a pair: (x,y)
tupleExpr :: Parser DimlExpr
tupleExpr = do
    e1 <- try $ reservedOp "(" *> expr <* reservedOp ","
    e2 <- expr <* reservedOp ")"
    ann <- optionMaybe annot
    return $ Tuple e1 e2 ann

letExpr :: Parser DimlExpr
letExpr = do
    try $ reserved "let"
    decls <- commaSep $ funExpr <|> declExpr
    reserved "in"
    body <- expr
    return $ foldr Let body decls

-- this parser parses a let declaration
-- ex: (x = 5) from 'let (x = 5) in x'
declExpr :: Parser DimlExpr
declExpr = do
    var <- try $ identifier <* reservedOp "="
    varAsgnmt <- expr
    return $ Decl var varAsgnmt

prIntExpr :: Parser DimlExpr
prIntExpr = do
    toPrint <- try $ reserved "printInt" *> parens expr
    return $ PrintInt toPrint

parensExpr :: Parser DimlExpr
parensExpr = Parens <$> parens expr <*> optionMaybe annot

-- Types:
-- int | bool | arrow type type | prod type type
-------------------------------
unitType :: Parser Type
unitType = Unit <$ reserved "Unit"

boolType :: Parser Type
boolType = tBool <$ reserved "Bool"

intType :: Parser Type
intType = tInt <$ reserved "Int"

prodType :: Parser Type
prodType = do
  --  let nonAgg = (try arrowType) <|> tTypeExpr
    t1 <- tTypeExpr <* reservedOp ","
    t2 <- tTypeExpr
    return $ TProd t1 t2

sumType :: Parser Type
sumType = do
    char '(' >> whitespace
    t1 <- typeExpr
    reservedOp "+"
    t2 <- typeExpr
    char ')' >> whitespace
    return $ TSum t1 t2

-- right associative type
arrowType :: Parser Type
arrowType = tTypeExpr `chainr1` arrow
    where arrow = TArr <$ reservedOp "->"

aggType :: Parser Type
aggType =  prodType
       <|> sumType
    --   <|> parens aggType

-- base type exprs
tTypeExpr :: Parser Type
tTypeExpr =  boolType
         <|> intType
         <|> unitType

typeExpr :: Parser Type
typeExpr = try arrowType
        <|> aggType
        <|> tTypeExpr
        <|> parens typeExpr

factor :: Parser DimlExpr
factor =  declExpr
      <|> funExpr
      <|> lamExpr
      <|> boolExpr
      <|> ifExpr
      <|> letExpr
      <|> intExpr
      <|> prIntExpr
      <|> varExpr
      <|> tupleExpr
      <|> unitExpr
      <|> parensExpr
