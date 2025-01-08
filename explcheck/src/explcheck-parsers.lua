-- Common LPEG parsers used by different modules of the static analyzer explcheck.

local lpeg = require("lpeg")
local P, R, S = lpeg.P, lpeg.R, lpeg.S

-- Base parsers
---- Generic
local any = P(1)
local eof = -any
local fail = P(false)

---- Tokens
local lbrace = P("{")
local rbrace = P("}")
local backslash = P([[\]])
local letter = R("AZ","az")
local underscore = P("_")
local colon = P(":")

---- Spacing
local newline = (
  P("\n")
  + P("\r\n")
  + P("\r")
)
local linechar = any - newline
local spacechar = S("\t ")
local optional_spaces = spacechar^0
local optional_spaces_and_newline = (
  optional_spaces
  * (
    newline
    * optional_spaces
  )^-1
)

-- Intermediate parsers.
---- Parts of TeX syntax
local argument = (
  lbrace
  * (any - rbrace)^0
  * rbrace
)

local expl3_function = (
  backslash
  * (underscore * underscore)^-1 * letter^1  -- module
  * underscore
  * letter^1  -- description
  * colon
  * S("NncVvoxefTFpwD")^1  -- argspec
  * (eof + -letter)
)
local expl3_variable_or_constant = (
  backslash
  * S("cgl")  -- scope
  * underscore
  * (
    letter^1  -- just description
    + underscore^-1 * letter^1  -- module
    * underscore
    * letter^1  -- description
  )
  * underscore
  * letter^1  -- type
  * (eof + -letter)
)
local expl3like_material = (
  expl3_function
  + expl3_variable_or_constant
)

---- Standard delimiters
local provides = (
  P([[\ProvidesExpl]])
  * (
      P("Package")
      + P("Class")
      + P("File")
    )
  * optional_spaces_and_newline
  * argument
  * optional_spaces_and_newline
  * argument
  * optional_spaces_and_newline
  * argument
  * optional_spaces_and_newline
  * argument
)
local expl_syntax_on = P([[\ExplSyntaxOn]])
local expl_syntax_off = P([[\ExplSyntaxOff]])

return {
  any = any,
  eof = eof,
  expl3like_material = expl3like_material,
  expl_syntax_off = expl_syntax_off,
  expl_syntax_on = expl_syntax_on,
  fail = fail,
  linechar = linechar,
  newline = newline,
  provides = provides,
}
