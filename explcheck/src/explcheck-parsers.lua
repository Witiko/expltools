-- Common LPEG parsers used by different modules of the static analyzer explcheck.

local registered_prefixes = require("explcheck-latex3").prefixes

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
local slash = P("/")
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
local expl3_endlinechar = ' '
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
  + Ct(C(S("TFp")))
  + Cc({})
)
local deprecated_argument_specifiers = (
  P("n") * Cc({"N", "c"})
  + P("N") * Cc({"n", "o", "V", "v", "f", "e", "x"})
  + Cc({})
)

---- Expl3 control sequence names
local expl3_function_csname = (
  (underscore * underscore)^-1 * letter^1  -- module
  * underscore
  * letter * (letter + underscore)^0  -- description
  * colon
  * argument_specifier^0  -- argspec
  * #(eof + -letter)
)

local any_type = (
  letter^1  -- type
  * (
    eof
    + (
      any
      - letter
      - underscore
    )
  )
)
local any_expl3_variable_or_constant_csname = (
  S("cgl")  -- scope
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
  expl3_catcodes[0] * (
    expl3_function_csname
    + any_expl3_variable_or_constant_csname
  )
)

local expl3_expandable_variable_or_constant_type = (
  P("bitset")
  + P("clist")
  + P("dim")
  + P("fp") * -#P("array")
  + P("int") * -#P("array")
  + P("muskip")
  + P("skip")
  + P("str")
  + P("tl")
)
local expl3_unexpandable_variable_or_constant_type = (
  P("bool")
  + P("cctab")
  + S("hv")^-1 * P("box")
  + P("coffin")
  + P("flag")
  + P("fparray")
  + P("intarray")
  + P("io") * S("rw")
  + P("prop")
  + P("quark")
  + P("regex")
  + P("scan")
  + P("seq")
)

local expl3_variable_or_constant_type = (
  expl3_expandable_variable_or_constant_type
  + expl3_unexpandable_variable_or_constant_type
)

local expl3_maybe_unexpandable_csname = (
  (
    -#(expl3_unexpandable_variable_or_constant_type * eof)
    * (any - underscore)^0
    * underscore
  )^0
  * expl3_unexpandable_variable_or_constant_type
  * eof
)

local expl3_standard_library_prefixes = (
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
  + P("graphics")
  + P("graph")  -- part of the lt3graph package
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
  * (
    P("annot")  -- part of the l3pdfannot module
    + P("dict")  -- part of the l3pdfdict module
    + P("field")  -- part of the l3pdffield module
    + P("file")  -- part of the l3pdffile module
    + P("management")  -- part of the l3pdfmanagement module
    + P("meta")  -- part of the l3pdfmeta module
    + P("xform")  -- part of the l3pdfxform module
  )^0
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
local function expl3_well_known_csname(other_prefix_texts)
  local other_prefixes = fail
  for _, prefix_text in ipairs(other_prefix_texts) do
    other_prefixes = (
      other_prefixes +
      #(P(prefix_text) * (underscore + colon))
      * P(prefix_text)
    )
  end
  local prefix = (
    #(expl3_standard_library_prefixes * (underscore + colon))
    * expl3_standard_library_prefixes
    + #(registered_prefixes * (underscore + colon))
    * registered_prefixes
    + other_prefixes
  )
  local well_known_function_csname = (
    P("__")^-1
    * prefix
    * (
      underscore
      * (any - colon)^0
    )^0
    * colon
  )
  local well_known_variable_or_constant_csname = (
    S("cgl")  -- scope
    * underscore
    * underscore^-1
    * prefix
    * underscore
  )
  return (
    well_known_function_csname
    + well_known_variable_or_constant_csname
  )
end

local expl3like_function_with_underscores_csname = (
  underscore^0
  * letter^1
  * underscore  -- a csname with at least one underscore in the middle
  * (letter + underscore)^1
  * (
    colon
    * letter^0
  )^-1
  * eof
)
local expl3like_function_csname = (
  underscore^0
  * letter^1
  * (letter + underscore)^0
  * colon  -- a csname with at least one colon at the end
  * letter^0
  * eof
)
local expl3like_csname = (
  expl3like_function_with_underscores_csname
  + expl3like_function_csname
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
local issue_code_prefix = (
  S("EeSsTtWw")
  * decimal_digit^-3
)
local ignored_issues = (
  optional_spaces
  * Cp()
  * expl3_catcodes[14]
  * (
    optional_spaces
    * expl3_catcodes[14]
  )^0
  * optional_spaces
  * P("noqa")
  * Ct(
    P(":")
    * optional_spaces
    * (
      Cs(issue_code_prefix)
      * optional_spaces
      * comma
      * optional_spaces
    )^0
    * Cs(issue_code_prefix)
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

---- Functions and conditional functions
------ Function definitions
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
    * (
      P("generate_from_arg_count") * Cc(false)  -- indirect application of a creator function
      + Cc(true) * expl3_function_definition_type_signifier  -- direct application of a creator function
      * (P("_protected") * Cc(true) + Cc(false))
      * (P("_nopar") * Cc(true) + Cc(false))
    )
    + P("prg_") * Cc(true)  -- conditional function
    * Cc(true)  -- conditional functions don't support indirect application of a creator function
    * expl3_function_definition_type_signifier
    * (P("_protected") * Cc(true) + Cc(false))
    * Cc(false)  -- conditional functions cannot be "nopar"
    * P("_conditional")
  )
  * colon
  * argument_specifier
)
local expl3_indirect_function_definition_csname = (
  (
    P("cs_") * Cc(false)  -- non-conditional function
    * expl3_function_definition_type_signifier
    * P("_eq")
    + P("prg_") * Cc(true)  -- conditional function
    * expl3_function_definition_type_signifier
    * P("_eq_conditional")
  )
  * colon
  * argument_specifier
  * argument_specifier
)
local expl3_function_definition_csname = Ct(
  Cc(true) * expl3_direct_function_definition_csname
  + Cc(false) * expl3_indirect_function_definition_csname
)

------ Generating function variants
local expl3_function_variant_definition_csname = Ct(
  (
    -- A non-conditional function
    P("cs_generate_variant") * Cc(false)
    -- A conditional function
    + P("prg_generate_conditional_variant") * Cc(true)
  )
  * colon
  * S("Nc")
)

------ Function calls with Lua arguments
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

------ Conditions in a conditional function definition
local condition = (
  P("p")
  + P("T") * P("F")^-1
  + P("F")
)
local conditions = comma_list(condition)

---- Variables and constants
------ Variable names
local expl3_variable_or_constant_csname = (
  S("cgl")  -- scope
  * underscore
  * (
    underscore^-1 * letter^1  -- module
    * underscore
    * letter * (letter + underscore * -#(expl3_variable_or_constant_type * eof))^0  -- description
  )
  * underscore
  * expl3_variable_or_constant_type  -- type
  * eof
)
local expl3_variable_or_constant_csname_scope = (
  C(S("cgl"))  -- scope
  * underscore
)
local expl3_variable_or_constant_csname_type = (
  (any - underscore)^0  -- scope
  * underscore^1
  * (any - underscore)^1  -- module and description
  * (any - #(underscore * expl3_variable_or_constant_type * eof))^0
  * underscore
  * C(expl3_variable_or_constant_type)  -- type
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
local expl3_quark_or_scan_mark_csname = (
  S("qs")
  * underscore
)

------ Variable declarations
local expl3_variable_declaration_csname = Ct(
  C(expl3_variable_or_constant_type)
  * underscore
  * (
    P("g")^-1
    * (
      P("zero")
      + P("clear")
    )
    * underscore
  )^-1
  * P("new:N")
)

------ Variable and constant definitions
local expl3_variable_definition_csname = Ct(
  C(expl3_variable_or_constant_type)
  * underscore
  * (
    P("const") * Cc(true)^-3  -- constant definition
    + Cc(false)  -- variable definition
    * (
      P("gset") * Cc(true)  -- global
      + P("set") * Cc(false)  -- local
    )
    * (
      Cc(false)  -- indirect
      * underscore
      * (
        P("eq")
        + P("from_")
        * C(expl3_variable_or_constant_type)
      )
      + Cc(true)  -- direct
    )
  )
  * P(":N")
)

------ Variable and constant use
local expl3_variable_use_csname = Ct(
  C(expl3_variable_or_constant_type)
  * underscore
  * (
    P("count")
    + P("open")
    + P("show")
    + P("use")
  )
  * P(":N")
)

---- Messages
------ Message names
local function expl3_well_known_message_name(other_prefix_texts)
  local other_prefixes = fail
  for _, prefix_text in ipairs(other_prefix_texts) do
    other_prefixes = (
      other_prefixes
      + #(P(prefix_text) * slash)
      * P(prefix_text)
    )
  end
  return (
    #(expl3_standard_library_prefixes * slash)
    * expl3_standard_library_prefixes
    + #(registered_prefixes * slash)
    * registered_prefixes
    + other_prefixes
  )
end

------ Message definitions
local expl3_message_definition = (
  P("msg")
  * underscore
  * (
    P("new")
    + P("g")^-1
    * P("set")
  )
  * colon
)

------ Message use
local expl3_message_use = (
  P("msg")
  * underscore
  * (
    P("none")
    + P("show")
    + P("term")
    + P("log")
    + P("info")
    + P("note")
    + P("warning")
    + P("error")
    + P("expandable_error")
    + P("critical")
    + P("fatal")
  )
  * colon
)

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
  double_superscript_convention = double_superscript_convention,
  do_not_use_argument_specifiers = do_not_use_argument_specifiers,
  endinput = endinput,
  eof = eof,
  expl3like_csname = expl3like_csname,
  expl3like_function_csname = expl3like_function_csname,
  expl3like_material = expl3like_material,
  expl3_catcodes = expl3_catcodes,
  expl3_endlinechar = expl3_endlinechar,
  expl3_expansion_csname = expl3_expansion_csname,
  expl3_function_call_with_lua_code_argument_csname = expl3_function_call_with_lua_code_argument_csname,
  expl3_function_csname = expl3_function_csname,
  expl3_function_definition_csname = expl3_function_definition_csname,
  expl3_function_variant_definition_csname = expl3_function_variant_definition_csname,
  expl3_maybe_unexpandable_csname = expl3_maybe_unexpandable_csname,
  expl3_message_definition = expl3_message_definition,
  expl3_message_use = expl3_message_use,
  expl3_quark_or_scan_mark_csname = expl3_quark_or_scan_mark_csname,
  expl3_scratch_variable_csname = expl3_scratch_variable_csname,
  expl3_variable_declaration_csname = expl3_variable_declaration_csname,
  expl3_variable_definition_csname = expl3_variable_definition_csname,
  expl3_variable_or_constant_csname = expl3_variable_or_constant_csname,
  expl3_variable_or_constant_csname_scope = expl3_variable_or_constant_csname_scope,
  expl3_variable_or_constant_csname_type = expl3_variable_or_constant_csname_type,
  expl3_variable_use_csname = expl3_variable_use_csname,
  expl3_well_known_csname = expl3_well_known_csname,
  expl3_well_known_message_name = expl3_well_known_message_name,
  expl_syntax_off = expl_syntax_off,
  expl_syntax_on = expl_syntax_on,
  fail = fail,
  ignored_issues = ignored_issues,
  latex_style_file_content = latex_style_file_content,
  linechar = linechar,
  newline = newline,
  N_or_n_type_argument_specifier = N_or_n_type_argument_specifier,
  N_or_n_type_argument_specifiers = N_or_n_type_argument_specifiers,
  N_type_argument_specifier = N_type_argument_specifier,
  n_type_argument_specifier = n_type_argument_specifier,
  provides = provides,
  space = space,
  success = success,
  tab = tab,
  tex_lines = tex_lines,
  variant_argument_specifiers = variant_argument_specifiers,
}
