-- Common LPEG parsers used by different modules of the static analyzer explcheck.

local lpeg = require("lpeg")
local C, Cp, Cs, Ct, Cmt, P, R, S = lpeg.C, lpeg.Cp, lpeg.Cs, lpeg.Ct, lpeg.Cmt, lpeg.P, lpeg.R, lpeg.S

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
local dollar_sign = P("$")
local form_feed = P("\x0C")
local hash_sign = P("#")
local lbrace = P("{")
local letter = R("AZ", "az")
local percent_sign = P("%")
local rbrace = P("}")
local tilde = P("~")
local underscore = P("_")
local lowercase_hexadecimal_digit = R("09", "af")
local lower_half_ascii_character = R("\x00\x3F")
local upper_half_ascii_character = R("\x40\x7F")

---- Spacing
local newline = (
  P("\n")
  + P("\r\n")
  + P("\r")
)
local linechar = any - newline
local space = S(" ")
local tab = S("\t")

-- Intermediate parsers
---- Default expl3 category code table, corresponds to `\c_code_cctab` in expl3
local expl3_endlinechar = ' '  -- luacheck: ignore expl3_endlinechar
local expl3_catcodes = {
  [0] = backslash,  -- escape character
  [1] = lbrace,  -- begin grouping
  [2] = rbrace,  -- end grouping
  [3] = dollar_sign,  -- math shift
  [4] = ampersand,  -- alignment tab
  [5] = newline,  -- end of line
  [6] = hash_sign,  -- parameter
  [7] = circumflex,  -- superscript
  [8] = fail,  -- subscript
  [9] = space + tab,  -- ignored character
  [10] = tilde,  -- space
  [11] = letter + colon + underscore,  -- letter
  [13] = form_feed,  -- active character
  [14] = percent_sign,  -- comment character
  [15] = control_character,  -- invalid character
}
expl3_catcodes[12] = any  -- other
for catcode, parser in pairs(expl3_catcodes) do
  if catcode ~= 12 then
    expl3_catcodes[12] = expl3_catcodes[12] - parser
  end
end

local determine_expl3_catcode = fail
for catcode, parser in pairs(expl3_catcodes) do
  determine_expl3_catcode = (
    determine_expl3_catcode
    + parser / function() return catcode end
  )
end

---- Parts of TeX syntax
local optional_spaces = space^0
local optional_spaces_and_newline = (
  optional_spaces
  * (
    newline
    * optional_spaces
  )^-1
)
local blank_line = (
  optional_spaces
  * newline
)
local blank_or_empty_last_line = (
  optional_spaces
  * (
    newline
    + eof
  )
)
local tex_line = (
  (
    (
      linechar
      - (space * #blank_or_empty_last_line)
    )^1
    * (
      blank_or_empty_last_line / ""
    )
  )
  + (
    (
      linechar
      - (space * #blank_line)
    )^0
    * (
      blank_line / ""
    )
  )
)
local tex_lines = Ct(
  Ct(
    Cp()
    * Cs(tex_line)
    * Cp()
  )^0
)

local double_superscript_convention = (
  Cmt(
    C(expl3_catcodes[7]),
    function(input, position, capture)
      if input:sub(position, position) == capture then
        return position + 1
      else
        return nil
      end
    end
  )
  * (
    C(lowercase_hexadecimal_digit * lowercase_hexadecimal_digit)
    / function(hexadecimal_digits)
      return string.char(tonumber(hexadecimal_digits, 16)), 4
    end
    + C(lower_half_ascii_character)
    / function(character)
      return string.char(string.byte(character) + 64), 3
    end
    + C(upper_half_ascii_character)
    / function(character)
      return string.char(string.byte(character) - 64), 3
    end
  )
)

local argument = (
  expl3_catcodes[1]
  * (any - expl3_catcodes[2])^0
  * expl3_catcodes[2]
)

local weird_argument_specifier = S("wD")
local argument_specifier = S("NncVvoxefTFp") + weird_argument_specifier
local argument_specifiers = argument_specifier^0
local weird_argument_specifiers = (
  (
    argument_specifier
    - weird_argument_specifier
  )^0
  * weird_argument_specifier
)

local expl3_function = (
  expl3_catcodes[0]
  * (underscore * underscore)^-1 * letter^1  -- module
  * underscore
  * letter^1  -- description
  * colon
  * argument_specifier^1  -- argspec
  * (eof + -letter)
)
local expl3_variable_or_constant = (
  expl3_catcodes[0]
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
  - expl3_catcodes[0]
  - expl3_catcodes[14]
)
local commented_line = (
  (
    (
      commented_line_letter
      - newline
    )^1  -- initial state
    + (
      expl3_catcodes[0]  -- even backslash
      * (
        expl3_catcodes[0]
        + #newline
      )
    )^1
    + (
      expl3_catcodes[0]
      * (
        expl3_catcodes[14]
        + commented_line_letter
      )
    )
  )^0
  * (
    #expl3_catcodes[14]
    * Cp()
    * (
      (
        expl3_catcodes[14]  -- comment
        * linechar^0
        * Cp()
        * newline
        * #blank_line  -- blank line
      )
      + expl3_catcodes[14]  -- comment
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
  expl3_catcodes[0]
  * P([[ProvidesExpl]])
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
local expl_syntax_on = expl3_catcodes[0] * P([[ExplSyntaxOn]])
local expl_syntax_off = expl3_catcodes[0] * P([[ExplSyntaxOff]])

return {
  any = any,
  argument_specifiers = argument_specifiers,
  commented_line = commented_line,
  determine_expl3_catcode = determine_expl3_catcode,
  double_superscript_convention = double_superscript_convention,
  eof = eof,
  fail = fail,
  expl3like_material = expl3like_material,
  expl3_endlinechar = expl3_endlinechar,
  expl_syntax_off = expl_syntax_off,
  expl_syntax_on = expl_syntax_on,
  linechar = linechar,
  newline = newline,
  provides = provides,
  tex_lines = tex_lines,
  weird_argument_specifiers = weird_argument_specifiers,
}
