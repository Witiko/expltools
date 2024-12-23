-- The preprocessing step of static analysis determines which parts of the input files contain expl3 code.

local config = require("explcheck-config")
local strip_comments = require("explcheck-preprocessing-comments")

local lpeg = require("lpeg")
local Cp, P, R, S, V = lpeg.Cp, lpeg.P, lpeg.R, lpeg.S, lpeg.V

-- Define base parsers.
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

-- Define intermediate parsers.
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

-- Get the value of an option or the default value if unspecified.
local function get_option(options, key)
  if options == nil or options[key] == nil then
    return config[key]
  end
  return options[key]
end

-- Preprocess the content and register any issues.
local function preprocessing(issues, content, options)

  -- Determine the bytes where lines begin.
  local line_starting_byte_numbers = {}

  local function record_line(line_start)
    table.insert(line_starting_byte_numbers, line_start)
  end

  local function line_too_long(range_start, range_end)
    issues:add('s103', 'line too long', range_start, range_end + 1)
  end

  local line_numbers_grammar = (
    Cp() / record_line
    * (
      (
        (
          Cp() * linechar^(get_option(options, 'max_line_length') + 1) * Cp() / line_too_long
          + linechar^0
        )
        * newline
        * Cp()
      ) / record_line
    )^0
  )
  lpeg.match(line_numbers_grammar, content)

  -- Strip TeX comments before further analysis.
  local transformed_content, map_back = strip_comments(content)

  -- Determine which parts of the input files contain expl3 code.
  local expl_ranges = {}

  local function capture_range(range_start, range_end)
    range_start, range_end = map_back(range_start), map_back(range_end)
    table.insert(expl_ranges, {range_start, range_end + 1})
  end

  local function unexpected_pattern(pattern, code, message, test)
    return Cp() * pattern * Cp() / function(range_start, range_end)
      range_start, range_end = map_back(range_start), map_back(range_end)
      if test == nil or test() then
        issues:add(code, message, range_start, range_end + 1)
      end
    end
  end

  local num_provides = 0
  local Opener = unexpected_pattern(
    provides,
    "e104",
    [[multiple delimiters `\ProvidesExpl*` in a single file]],
    function()
      num_provides = num_provides + 1
      return num_provides > 1
    end
  )
  local Closer = fail
  if not get_option(options, 'expect_expl3_everywhere') then
    Opener = (
      expl_syntax_on
      + Opener
    )
    Closer = (
      expl_syntax_off
      + Closer
    )
  end

  local analysis_grammar = P{
    "Root";
    Root = (
      (
        V"NonExplPart"
        * V"ExplPart" / capture_range
      )^0
      * V"NonExplPart"
    ),
    NonExplPart = (
      (
        unexpected_pattern(
          V"Closer",
          "w101",
          "unexpected delimiters"
        )
        + unexpected_pattern(
            expl3like_material,
            "e102",
            "expl3 material in non-expl3 parts"
          )
        + (any - V"Opener")
      )^0
    ),
    ExplPart = (
      V"Opener"
      * Cp()
      * (
          unexpected_pattern(
            V"Opener",
            "w101",
            "unexpected delimiters"
          )
          + (any - V"Closer")
        )^0
      * Cp()
      * (V"Closer" + eof)
    ),
    Opener = Opener,
    Closer = Closer,
  }
  lpeg.match(analysis_grammar, transformed_content)

  -- If no parts were detected, assume that the whole input file is in expl3.
  if(#expl_ranges == 0 and #content > 0) then
    table.insert(expl_ranges, {0, #content})
    if not get_option(options, 'expect_expl3_everywhere') then
      issues:add('w100', 'no standard delimiters')
      issues:ignore('e102')
    end
  end
  return line_starting_byte_numbers, expl_ranges
end

return preprocessing
