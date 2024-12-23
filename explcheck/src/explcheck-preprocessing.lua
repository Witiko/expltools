-- The preprocessing step of static analysis determines which parts of the input files contain expl3 code.

local defaults = require("explcheck-defaults")

local lpeg = require("lpeg")
local Cp, P, R, S, V = lpeg.Cp, lpeg.P, lpeg.R, lpeg.S, lpeg.V

-- Define base parsers.
---- Generic
local any = P(1)
local eof = -any

---- Tokens
local lbrace = P("{")
local rbrace = P("}")
local percent_sign = P("%")
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
local comment = (
  percent_sign
  * linechar^0
  * newline
  * optional_spaces
)
local argument = (
  lbrace
  * (
    comment
    + (any - rbrace)
  )^0
  * rbrace
)
local expl3like_control_sequence = (
  backslash
  * (letter - underscore - colon)^1
  * (underscore + colon)
  * letter^1
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
  * comment^0
  * argument
  * optional_spaces_and_newline
  * comment^0
  * argument
  * optional_spaces_and_newline
  * comment^0
  * argument
  * optional_spaces_and_newline
  * comment^0
  * argument
)
local expl_syntax_on = P([[\ExplSyntaxOn]])
local expl_syntax_off = P([[\ExplSyntaxOff]])

local function preprocessing(issues, content, max_line_length)
  if max_line_length == nil then
    max_line_length = defaults.max_line_length
  end

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
          Cp() * linechar^(max_line_length + 1) * Cp() / line_too_long
          + linechar^0
        )
        * newline
        * Cp()
      ) / record_line
    )^0
  )
  lpeg.match(line_numbers_grammar, content)
  -- Determine which parts of the input files contain expl3 code.
  local expl_ranges = {}
  local function capture_range(range_start, range_end)
    table.insert(expl_ranges, {range_start, range_end + 1})
  end
  local function unexpected_pattern(pattern, code, message, test)
    return Cp() * pattern * Cp() / function(range_start, range_end)
      if test == nil or test() then
        issues:add(code, message, range_start, range_end + 1)
      end
    end
  end
  local num_provides = 0
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
            expl3like_control_sequence,
            "e102",
            "expl3 control sequences in non-expl3 parts"
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
    Opener = (
      expl_syntax_on
      + unexpected_pattern(
        provides,
        "e104",
        [[multiple delimiters `\ProvidesExpl*` in a single file]],
        function()
          num_provides = num_provides + 1
          return num_provides > 1
        end
      )
    ),
    Closer = expl_syntax_off,
  }
  lpeg.match(analysis_grammar, content)
  -- If no parts were detected, assume that the whole input file is in expl3.
  if(#expl_ranges == 0 and #content > 0) then
    table.insert(expl_ranges, {0, #content})
    issues:add('w100', 'no standard delimiters')
    issues:ignore('e102')
  end
  return line_starting_byte_numbers, expl_ranges
end

return preprocessing
