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
local comma = P(",")
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
local decimal_digit = R("09")
local lowercase_hexadecimal_digit = decimal_digit + R("af")
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

---- Syntax recognized by TeX's input and token processors
local optional_spaces = expl3_catcodes[9]^0
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
      - (expl3_catcodes[9] * #blank_or_empty_last_line)
    )^1
    * (
      blank_or_empty_last_line / ""
    )
  )
  + (
    (
      linechar
      - (expl3_catcodes[9] * #blank_line)
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

---- Arguments and argument specifiers
local argument = (
  expl3_catcodes[1]
  * (any - expl3_catcodes[2])^0
  * expl3_catcodes[2]
)

local weird_argument_specifier = S("wD")
local argument_specifier = S("NncVvoxefTFp") + weird_argument_specifier
local argument_specifiers = argument_specifier^0 * eof
local weird_argument_specifiers = (
  (
    argument_specifier
    - weird_argument_specifier
  )^0
  * weird_argument_specifier
)

---- Function, variable, and constant names
local expl3_function_csname = (
  (underscore * underscore)^-1 * letter^1  -- module
  * underscore
  * letter * (letter + underscore)^0  -- description
  * colon
  * argument_specifier^0  -- argspec
  * (eof + -letter)
)
local expl3_function = expl3_catcodes[0] * expl3_function_csname

local any_type = (
  letter^1  -- type
  * (eof + -letter)
)
local any_expl3_variable_or_constant = (
  expl3_catcodes[0]
  * S("cgl")  -- scope
  * underscore
  * (
    letter * (letter + underscore * -#any_type)^0  -- just description
    + underscore^-1 * letter^1  -- module
    * underscore
    * letter * (letter + underscore * -#any_type)^0  -- description
  )
  * underscore
  * any_type
)

local expl3like_material = (
  expl3_function
  + any_expl3_variable_or_constant
)

local expl3_variable_or_constant_type = (
  P("bitset")
  + S("hv")^-1 * P("box")
  + P("bool")
  + P("cctab")
  + P("clist")
  + P("coffin")
  + P("dim")
  + P("flag")
  + P("fp") * P("array")^-1
  + P("int") * P("array")^-1
  + P("ior")
  + P("iow")
  + P("muskip")
  + P("prop")
  + P("regex")
  + P("seq")
  + P("skip")
  + P("str")
  + P("tl")
)

local expl3_variable_or_constant_csname = (
  S("cgl")  -- scope
  * underscore
  * (
    underscore^-1 * letter^1  -- module
    * underscore
    * letter * (letter + underscore * -#(expl3_variable_or_constant_type * eof))^0  -- description
  )
  * underscore
  * expl3_variable_or_constant_type
  * eof
)
local expl3_scratch_variable_csname = (
  P("l")
  * underscore
  * P("tmp") * S("ab")
  * underscore
  * expl3_variable_or_constant_type
  * eof
)

local non_expl3_csname = (
  letter^1
  * eof
)

---- Comments
local commented_line_letter = (
  linechar
  + newline
  - expl3_catcodes[0]
  - expl3_catcodes[14]
  - expl3_catcodes[9]
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
    + (
      #(
        optional_spaces
        * -expl3_catcodes[14]
      )
      * expl3_catcodes[9]
    )
  )^0
  * (
    #(
      optional_spaces
      * expl3_catcodes[14]
    )
    * Cp()
    * (
      (
        optional_spaces
        * expl3_catcodes[14]  -- comment
        * linechar^0
        * Cp()
        * newline
        * #blank_line  -- blank line
      )
      + optional_spaces
      * expl3_catcodes[14]  -- comment
      * linechar^0
      * Cp()
      * newline
      * optional_spaces  -- leading spaces
    )
    + newline
  )
)

-- Explcheck issues
local issue_code = (
  S("EeSsTtWw")
  * decimal_digit
  * decimal_digit
  * decimal_digit
)
local ignored_issues = Ct(
  optional_spaces
  * P("noqa")
  * (
    P(":")
    * optional_spaces
    * (
      Cs(issue_code)
      * optional_spaces
      * comma
      * optional_spaces
    )^0
    * Cs(issue_code)
    * optional_spaces
    + optional_spaces
  )
  * eof
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

---- Assigning functions
local expl3_function_assignment_csname = (
  P("cs_")
  * (
    (
      P("new")
      + P("g")^-1
      * P("set")
    )
    * (
      P("_eq")
      + P("_protected")^-1
      * P("_nopar")^-1
    )
    + P("generate_from_arg_count")
  )
  * P(":N")
)

---- Using variables/constants
local expl3_variable_or_constant_use_csname = (
  expl3_variable_or_constant_type
  * P("_")
  * (
    P("const")
    + P("new")
    + P("g")^-1
    * P("set")
    * P("_eq")^-1
    + P("use")
  )
  * P(":N")
)

---- Defining quarks and scan marks
local expl3_quark_or_scan_mark_definition_csname = (
  (
    P("quark")
    + P("scan")
  )
  * P("_new:N")
  * eof
)
local expl3_quark_or_scan_mark_csname = S("qs") * P("_")

return {
  any = any,
  argument_specifiers = argument_specifiers,
  commented_line = commented_line,
  decimal_digit = decimal_digit,
  determine_expl3_catcode = determine_expl3_catcode,
  double_superscript_convention = double_superscript_convention,
  eof = eof,
  fail = fail,
  expl3like_material = expl3like_material,
  expl3_endlinechar = expl3_endlinechar,
  expl3_function_assignment_csname = expl3_function_assignment_csname,
  expl3_function_csname = expl3_function_csname,
  expl3_scratch_variable_csname = expl3_scratch_variable_csname,
  expl3_variable_or_constant_csname = expl3_variable_or_constant_csname,
  expl3_variable_or_constant_use_csname = expl3_variable_or_constant_use_csname,
  expl3_quark_or_scan_mark_csname = expl3_quark_or_scan_mark_csname,
  expl3_quark_or_scan_mark_definition_csname = expl3_quark_or_scan_mark_definition_csname,
  expl_syntax_off = expl_syntax_off,
  expl_syntax_on = expl_syntax_on,
  ignored_issues = ignored_issues,
  linechar = linechar,
  newline = newline,
  non_expl3_csname = non_expl3_csname,
  provides = provides,
  tex_lines = tex_lines,
  weird_argument_specifiers = weird_argument_specifiers,
}
