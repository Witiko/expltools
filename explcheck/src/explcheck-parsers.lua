-- Common LPEG parsers used by different modules of the static analyzer explcheck.

local lpeg = require("lpeg")
local C, Cc, Cp, Cs, Ct, Cmt, P, R, S = lpeg.C, lpeg.Cc, lpeg.Cp, lpeg.Cs, lpeg.Ct, lpeg.Cmt, lpeg.P, lpeg.R, lpeg.S

-- Base parsers
---- Generic
local any = P(1)
local eof = -any
local fail = P(false)
local success = P(true)

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

---- Comma-lists
local function comma_list(item_parser)
  return Ct(
    eof
    + C(item_parser)
    * (
      P(",") * C(item_parser)
    )^0
    * P(",")^-1
    * eof
  )
end

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
  [15] = control_character - newline,  -- invalid character
}
expl3_catcodes[12] = any  -- other
for catcode = 0, 15 do
  local parser = expl3_catcodes[catcode]
  if catcode ~= 12 then
    expl3_catcodes[12] = expl3_catcodes[12] - parser
  end
end

local determine_expl3_catcode = fail
for catcode = 0, 15 do
  local parser = expl3_catcodes[catcode]
  determine_expl3_catcode = (
    determine_expl3_catcode
    + parser
    / function()
      return catcode
    end
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

local N_type_argument_specifier = S("NV")
local n_type_argument_specifier = S("ncvoxefTF")
local parameter_argument_specifier = S("p")
local weird_argument_specifier = S("w")
local do_not_use_argument_specifier = S("D")
local N_or_n_type_argument_specifier = (
  N_type_argument_specifier
  + n_type_argument_specifier
)
local N_or_n_type_argument_specifiers = (
  N_or_n_type_argument_specifier^0
  * eof
)
local argument_specifier = (
  N_type_argument_specifier
  + n_type_argument_specifier
  + parameter_argument_specifier
  + weird_argument_specifier
  + do_not_use_argument_specifier
)
local argument_specifiers = (
  argument_specifier^0
  * eof
)
local variant_argument_specifiers = comma_list(argument_specifier^0)
local do_not_use_argument_specifiers = (
  (
    argument_specifier
    - do_not_use_argument_specifier
  )^0
  * do_not_use_argument_specifier
)

local compatible_argument_specifiers = (
  P("N") * Cc({"N", "c"})
  + P("n") * Cc({"n", "o", "V", "v", "f", "e", "x"})
  + C(argument_specifier)
  + Cc({})
)
local deprecated_argument_specifiers = (
  P("n") * Cc({"N", "c"})
  + P("N") * Cc({"n", "o", "V", "v", "f", "e", "x"})
  + Cc({})
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
  + P("io") * S("rw")
  + P("muskip")
  + P("prop")
  + P("regex")
  + P("seq")
  + P("skip")
  + P("str")
  + P("tl")
)

local expl3_maybe_standard_library_csname = (
  (
    expl3_variable_or_constant_type
    + P("benchmark")
    + P("char")
    + P("codepoint")
    + S("hv") * P("coffin")
    + P("color")
    + P("cs")
    + P("debug")
    + P("draw")
    + P("exp")
    + P("file")
    + P("graph")  -- part of the lt3graph package
    + P("graphics")
    + P("group")
    + P("hook")  -- part of the lthooks module
    + P("if")
    + P("keys")
    + P("keyval")
    + P("legacy")
    + P("lua")
    + P("mark")  -- part of the ltmarks module
    + P("mode")
    + P("msg")
    + P("opacity")
    + P("para")  -- part of the ltpara module
    + P("pdf")
    + P("peek")
    + P("prg")
    + P("property")  -- part of the ltproperties module
    + P("quark")
    + P("reverse_if")
    + P("scan")
    + P("socket")  -- part of the ltsockets module
    + P("sort")
    + P("sys")
    + P("tag")  -- part of the tagpdf package
    + P("text")
    + P("token")
    + P("use")
    + P("withargs")  -- part of the withargs package
  )
  * (
    underscore
    * (any - colon)^0
  )^-1
  * colon
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
  S("gl")
  * underscore
  * P("tmp") * S("ab")
  * underscore
  * expl3_variable_or_constant_type
  * eof
)

local expl3like_csname = (
  underscore^0
  * letter^1
  * (
    underscore  -- a csname with at least one underscore in the middle
    * (letter + underscore)^1
    * (
      colon
      * letter^0
    )^-1
    + (letter + underscore)^0
    * colon  -- a csname with at least one colon at the end
    * letter^0
  )
)

---- Comments
local commented_line_letter = (
  linechar
  + newline
  - expl3_catcodes[0]
  - expl3_catcodes[9]
  - expl3_catcodes[14]
)
local function commented_line(closer)
  return (
    (
      commented_line_letter
      - closer
    )^1  -- initial state
    + (
      expl3_catcodes[0]  -- even backslash
      * (
        expl3_catcodes[0]
        + #closer
      )
    )^1
    + (
      expl3_catcodes[0]  -- odd backslash
      * (
        expl3_catcodes[9]
        + expl3_catcodes[14]
        + commented_line_letter
      )
    )
    + (
      #(
        expl3_catcodes[9]^1
        * -expl3_catcodes[14]
      )
      * expl3_catcodes[9]^1  -- spaces
    )
  )^0
  * (
    #(
      expl3_catcodes[9]^0
      * expl3_catcodes[14]
    )
    * Cp()
    * (
      (
        expl3_catcodes[9]^0
        * expl3_catcodes[14]  -- comment
        * linechar^0
        * Cp()
        * closer
        * (
          #blank_line  -- blank line
          + expl3_catcodes[9]^0  -- leading spaces
        )
      )
    )
    + closer
  )
end

local commented_lines = Ct(
  commented_line(newline)^0
  * commented_line(eof)
  * eof
  + eof
)

------ Explcheck issues
local issue_code = (
  S("EeSsTtWw")
  * decimal_digit
  * decimal_digit
  * decimal_digit
)
local ignored_issues = Ct(
  (
    optional_spaces
    * expl3_catcodes[14]
  )^1
  * optional_spaces
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
  * P("ProvidesExpl")
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
local expl_syntax_on = expl3_catcodes[0] * P("ExplSyntaxOn")
local expl_syntax_off = expl3_catcodes[0] * P("ExplSyntaxOff")
local endinput = (
  expl3_catcodes[0]
  * (
    P("tex_endinput:D")
    + P("endinput")
    + P("file_input_stop:")
  )
)

---- Commands from LaTeX style files
local latex_style_file_csname =
(
  -- LaTeX2e package writer commands
  -- See <https://www.latex-project.org/help/documentation/clsguide.pdf>.
  P("AddToHook")
  + P("AtBeginDocument")
  + P("AtEndDocument")
  + P("AtEndOfClass")
  + P("AtEndOfPackage")
  + P("BCPdata")
  + P("CheckCommand")
  + P("ClassError")
  + P("ClassInfo")
  + P("ClassWarning")
  + P("ClassWarningNoLine")
  + P("CurrentOption")
  + P("DeclareInstance")
  + P("DeclareKeys")
  + P("DeclareOption")
  + P("DeclareRobustCommand")
  + P("DeclareTemplateCode")
  + P("DeclareTemplateInterface")
  + P("DeclareUnknownKeyHandler")
  + P("ExecuteOptions")
  + P("IfClassAtLeastTF")
  + P("IfClassLoadedTF")
  + P("IfClassLoadedWithOptionsTF")
  + P("IfFileAtLeastTF")
  + P("IfFileExists")
  + P("IfFileLoadedTF")
  + P("IfFormatAtLeastTF")
  + P("IfPackageAtLeastTF")
  + P("IfPackageLoadedTF")
  + P("IfPackageLoadedWithOptionsTF")
  + P("InputIfFileExists")
  + P("LinkTargetOff")
  + P("LinkTargetOn")
  + P("LoadClass")
  + P("LoadClassWithOptions")
  + P("MakeLinkTarget")
  + P("MakeLowercase")
  + P("MakeTitlecase")
  + P("MakeUppercase")
  + P("MessageBreak")
  + P("NeedsTeXFormat")
  + P("NewDocumentCommand")
  + P("NewDocumentEnvironment")
  + P("NewProperty")
  + P("NewTemplateType")
  + P("NextLinkTarget")
  + P("OptionNotUsed")
  + P("PackageError")
  + P("PackageInfo")
  + P("PackageWarning")
  + P("PackageWarningNoLine")
  + P("PassOptionsToClass")
  + P("PassOptionsToPackage")
  + P("ProcessKeyOptions")
  + P("ProcessOptions")
  + P("ProvidesClass")
  + P("ProvidesFile")
  + P("ProvidesPackage")
  + P("RecordProperties")
  + P("RefProperty")
  + P("RefUndefinedWarn")
  + P("RequirePackage")
  + P("RequirePackageWithOptions")
  + P("SetKeys")
  + P("SetProperty")
  + P("UseInstance")
  -- LaTeX3 package writer commands
  + P("ProvidesExplClass")
  + P("ProvidesExplPackage")
  -- Other LaTeX2e commands
  -- See <http://mirrors.ctan.org/macros/latex/base/source2e.pdf>.
  + P("@gobble")
  + P("@ifpackagelater")
  + P("@ifpackageloaded")
)

local latex_style_file_content = (
  (
    any
    - #(
      expl3_catcodes[0]
      * latex_style_file_csname
    )
  )^0
  * expl3_catcodes[0]
  * latex_style_file_csname
)

---- Argument expansion functions from the module l3expan
local expl3_expansion_csname = (
  P("exp")
  * underscore
  * letter * (letter + underscore)^0
  * colon
)

---- Assigning functions
local expl3_function_definition_type_signifier = (
  P("new") * Cc(false) * Cc(true)  -- definition
  + (  -- assignment
    C(true)
    * (
      P("gset") * Cc(true)  -- global
      + P("set") * Cc(false)  -- local
    )
  )
)
local expl3_direct_function_definition_csname = (
  (
    P("cs_") * Cc(false)  -- non-conditional function
    * expl3_function_definition_type_signifier
    * (P("_protected") * Cc(true) + Cc(false))
    * (P("_nopar") * Cc(true) + Cc(false))
    + P("prg_") * Cc(true)  -- conditional function
    * expl3_function_definition_type_signifier
    * (P("_protected") * Cc(true) + Cc(false))
    * Cc(false)  -- conditional functions cannot be "nopar"
    * P("_conditional")
  )
  * P(":N")
)
local expl3_indirect_function_definition_csname = (
  (
    P("cs_") * Cc(false)  -- non-conditional function
    * expl3_function_definition_type_signifier
    * P("_eq")
    + P("prg") * Cc(true)  -- conditional function
    * expl3_function_definition_type_signifier
    * P("_eq_conditional")
  )
  * P(":NN")
)
local expl3_function_definition_csname = Ct(
  Cc(true) * expl3_direct_function_definition_csname
  + Cc(false) * expl3_indirect_function_definition_csname
)
local expl3_function_definition_or_assignment_csname = (
  (
    -- A non-conditional function
    P("cs")
    * underscore
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
    -- A conditional function
    + P("prg")
    * underscore
    * (
      (
        P("new")
        + P("g")^-1
        * P("set")
      )
      * (
        P("_eq")
        + P("_protected")^-1
      )
    )
    * P("_conditional")
  )
  * P(":N")
)

---- Generating function variants
local expl3_function_variant_definition_csname = Ct(
  (
    -- A non-conditional function
    P("cs_generate_variant") * Cc(false)
    -- A conditional function
    + P("prg_generate_conditional_variant") * Cc(true)
  )
  * P(":N")
)

---- Function calls with Lua arguments
local expl3_function_call_with_lua_code_argument_csname = Ct(
  P("lua")
  * underscore
  * (
    P("now")
    + P("shipout")
  )
  * colon
  * S("noex")
  * eof
  * Cc(1)
  + success
)

---- Using variables/constants
local expl3_variable_or_constant_use_csname = (
  expl3_variable_or_constant_type
  * underscore
  * (
    P("const")
    + P("new")
    + P("g")^-1
    * P("set")
    * (
      underscore
      * (
        P("eq")
        + P("true")
        + P("false")
      )
    )^-1
    + P("use")
    + P("show")
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
local expl3_quark_or_scan_mark_csname = (
  S("qs")
  * underscore
)

---- Conditions in a conditional function definition
local condition = (
  P("p")
  + P("T") * P("F")^-1
  + P("F")
)
local conditions = comma_list(condition)

return {
  any = any,
  argument_specifiers = argument_specifiers,
  commented_lines = commented_lines,
  compatible_argument_specifiers = compatible_argument_specifiers,
  condition = condition,
  conditions = conditions,
  decimal_digit = decimal_digit,
  deprecated_argument_specifiers = deprecated_argument_specifiers,
  determine_expl3_catcode = determine_expl3_catcode,
  do_not_use_argument_specifier = do_not_use_argument_specifier,
  do_not_use_argument_specifiers = do_not_use_argument_specifiers,
  double_superscript_convention = double_superscript_convention,
  endinput = endinput,
  eof = eof,
  expl3_catcodes = expl3_catcodes,
  expl3_endlinechar = expl3_endlinechar,
  expl3_expansion_csname = expl3_expansion_csname,
  expl3_function_call_with_lua_code_argument_csname = expl3_function_call_with_lua_code_argument_csname,
  expl3_function_csname = expl3_function_csname,
  expl3_function_definition_csname = expl3_function_definition_csname,
  expl3_function_definition_or_assignment_csname = expl3_function_definition_or_assignment_csname,
  expl3_function_variant_definition_csname = expl3_function_variant_definition_csname,
  expl3like_csname = expl3like_csname,
  expl3like_material = expl3like_material,
  expl3_maybe_standard_library_csname = expl3_maybe_standard_library_csname,
  expl3_quark_or_scan_mark_csname = expl3_quark_or_scan_mark_csname,
  expl3_quark_or_scan_mark_definition_csname = expl3_quark_or_scan_mark_definition_csname,
  expl3_scratch_variable_csname = expl3_scratch_variable_csname,
  expl3_variable_or_constant_csname = expl3_variable_or_constant_csname,
  expl3_variable_or_constant_use_csname = expl3_variable_or_constant_use_csname,
  expl_syntax_off = expl_syntax_off,
  expl_syntax_on = expl_syntax_on,
  fail = fail,
  ignored_issues = ignored_issues,
  latex_style_file_content = latex_style_file_content,
  linechar = linechar,
  newline = newline,
  N_or_n_type_argument_specifier = N_or_n_type_argument_specifier,
  N_or_n_type_argument_specifiers = N_or_n_type_argument_specifiers,
  n_type_argument_specifier = n_type_argument_specifier,
  N_type_argument_specifier = N_type_argument_specifier,
  parameter_argument_specifier = parameter_argument_specifier,
  provides = provides,
  space = space,
  success = success,
  tab = tab,
  tex_lines = tex_lines,
  variant_argument_specifiers = variant_argument_specifiers,
  weird_argument_specifier = weird_argument_specifier,
}
