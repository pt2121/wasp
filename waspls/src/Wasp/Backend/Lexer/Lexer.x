{
-- This file is processed by Alex (https://www.haskell.org/alex/) and generates
-- the module `Wasp.Backend.Lexer.Lexer`

module Wasp.Backend.Lexer.Lexer
  ( Wasp.Backend.Lexer.Lexer.lex
  ) where

import Wasp.Backend.Lexer.Internal
import Wasp.Backend.Token (Token)
import qualified Wasp.Backend.Token as T
}

-- Character set aliases
$space = [\ \t\f\v\r] -- Non-newline whitespace
$digit = 0-9
$alpha = [a-zA-Z]
$identstart = [_$alpha]
$ident = [_$alpha$digit]
$any = [.$white]

-- Regular expression aliases
-- matches string-literal on a single line, from https://stackoverflow.com/a/9260547/3902376
@string = \"([^\\\"]|\\.)*\"
@double = "-"? $digit+ "." $digit+
@integer = "-"? $digit+
@ident = $identstart $ident* "'"*
@linecomment = "//" [^\n\r]*
-- Based on https://stackoverflow.com/a/16165598/1509394 .
@blockcomment = "/*" (("*"[^\/]) | [^\*] | $white)* "*/"

tokens :-

<0>       $space+ { createToken T.White }
<0>       \n { createToken T.Newline } 
<0>       @linecomment { createToken T.Comment }
<0>       @blockcomment { createToken T.Comment }

-- Quoter rules:
-- Uses Alex start codes to lex quoted characters with different rules:
-- - On "{=tag", enter <quoter> start code and make a TLQuote token
-- - While in <quoter>, if "tag=}" is seen
--   - If this closing tag matches the opening, enter <0> and make a TRQuote token
--   - Otherwise, stay in <quoter> and make a TQuoted token
-- - Otherwise, take one character at a time and make a TQuoted token
<0>       "{=" @ident { beginQuoter }
<quoter>  @ident "=}" { lexQuoterEndTag }
<quoter>  $any { createToken T.Quoted }

-- Simple tokens
<0>       "(" { createToken T.LParen }
<0>       ")" { createToken T.RParen }
<0>       "[" { createToken T.LSquare }
<0>       "]" { createToken T.RSquare }
<0>       "{" { createToken T.LCurly }
<0>       "}" { createToken T.RCurly }
<0>       "," { createToken T.Comma }
<0>       ":" { createToken T.Colon }
<0>       "import" { createToken T.KwImport }
<0>       "from" { createToken T.KwFrom }
<0>       "true" { createToken T.KwTrue }
<0>       "false" { createToken T.KwFalse }

-- Strings, numbers, identifiers
<0>       @string { createToken T.String }
<0>       @double { createToken T.Double }
<0>       @integer { createToken T.Int }
<0>       @ident { createToken T.Identifier }

{
-- | Lexes a single token from the input, returning "Nothing" if the lexer has
-- reached the end of the input. This function uses a continuation passing style
-- so that this function and its consumer can benefit from tail call
-- optimization.
--
-- This function internally calls `alexScan`, which is a function generated by
-- Alex responsible for doing actual lexing/scanning.
lexOne :: (Maybe Token -> Lexer a) -> Lexer a
lexOne continue = do
  input@(LexInput _ _ remaining) <- getInput
  startCodeInt <- startCodeToInt quoter <$> getStartCode
  case alexScan input startCodeInt of
    AlexError (LexInput _ _ (c:_)) -> do
      token <- createToken T.Error [c]
      updateInput 1
      continue (Just token)
    AlexError (LexInput c _ []) -> do
      token <- createToken T.Error [c]
      updateInput 1
      continue (Just token)
    AlexSkip _ _ ->
      error "AlexSkip is impossible: lexer should not skip any input"
    AlexToken _ numChars makeToken -> do
      let lexeme = take numChars remaining
      token <- makeToken lexeme
      updateInput numChars
      continue (Just token)
    AlexEOF -> continue Nothing

-- | @lex source@ lexes all of @source@ into "Token"s.
lex :: String -> [Token]
lex source = runLexer (lexOne continue) $ initialLexState source
  where
    continue :: Maybe Token -> Lexer [Token]
    continue Nothing = return []
    -- This is written awkwardly like this so it is a tail call to @lexOne@
    continue (Just tok) = (tok:) <$> lexOne continue
}
