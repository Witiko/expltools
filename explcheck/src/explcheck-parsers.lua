-- Common LPEG parsers used by different modules of the static analyzer explcheck.

local lpeg = require("lpeg")
local Cp, P, R, S = lpeg.Cp, lpeg.P, lpeg.R, lpeg.S

-- Base parsers
---- Generic
local any = P(1)
local eof = -any
local fail = P(false)

---- Tokens
local ampersand = P("&")
local backslash = P([[\]])
local circumflex = P("^")
local colon = P(":")
local control_character = R("\x00\x1F") + P("\x7F")
local digit = R("09")
local dollar_sign = P("$")
local form_feed = P("\x0C")
local hash_sign = P("#")
local lbrace = P("{")
local letter = R("AZ", "az")
local percent_sign = P("%")
local punctuation = R("!/", ":@", "[`", "{~")
local rbrace = P("}")
local tilde = P("~")
local underscore = P("_")

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
local blank_line = optional_spaces * newline

-- Intermediate parsers
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

local commented_line_letter = (
  linechar
  + newline
  - backslash
  - percent_sign
)
local commented_line = (
  (
    (
      commented_line_letter
      - newline
    )^1  -- initial state
    + (
      backslash  -- even backslash
      * (
        backslash
        + #newline
      )
    )^1
    + (
      backslash
      * (
        percent_sign
        + commented_line_letter
      )
    )
  )^0
  * (
    #percent_sign
    * Cp()
    * (
      (
        percent_sign  -- comment
        * linechar^0
        * Cp()
        * newline
        * #blank_line  -- blank line
      )
      + percent_sign  -- comment
      * linechar^0
      * Cp()
      * newline
      * optional_spaces  -- leading spaces
    )
    + newline
  )
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
  ampersand = ampersand,
  any = any,
  backslash = backslash,
  circumflex = circumflex,
  colon = colon,
  commented_line = commented_line,
  control_character = control_character,
  digit = digit,
  dollar_sign = dollar_sign,
  eof = eof,
  expl3like_material = expl3like_material,
  expl_syntax_off = expl_syntax_off,
  expl_syntax_on = expl_syntax_on,
  fail = fail,
  form_feed = form_feed,
  hash_sign = hash_sign,
  lbrace = lbrace,
  letter = letter,
  linechar = linechar,
  newline = newline,
  percent_sign = percent_sign,
  provides = provides,
  punctuation = punctuation,
  rbrace = rbrace,
  spacechar = spacechar,
  tilde = tilde,
}
