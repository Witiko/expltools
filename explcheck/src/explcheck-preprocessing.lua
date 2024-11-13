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

-- Define intermediate parsers.
---- Parts of TeX syntax
local comment = (
  percent_sign
  * linechar^0
  * newline
  * spacechar^0
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
  * spacechar^0
  * argument
  * comment^-1
  * argument
  * comment^-1
  * argument
  * comment^-1
  * argument
)
local expl_syntax_on = P([[\ExplSyntaxOn]])
local expl_syntax_off = P([[\ExplSyntaxOff]])

local function preprocessing(state)
  -- Determine the bytes where lines begin.
  local line_starting_byte_numbers = {}
  local function record_line(line_start)
    table.insert(line_starting_byte_numbers, line_start)
  end
  local function line_too_long(range_start, range_end)
    table.insert(state.warnings, {'s103', 'line too long', {range_start, range_end + 1}})
  end
  local line_numbers_grammar = (
    Cp() / record_line
    * (
      (
        (
          Cp() * linechar^81 * Cp() / line_too_long
          + linechar^0
        )
        * newline
        * Cp()
      ) / record_line
    )^0
  )
  lpeg.match(line_numbers_grammar, state.content)
  -- Determine which parts of the input files contain expl3 code.
  state.ranges = {}
  local function capture_range(range_start, range_end)
    table.insert(state.ranges, {range_start, range_end + 1})
  end
  local function unexpected_pattern(pattern, code, message)
    local issues = (code:sub(1, 1) == "e" and state.errors) or state.warnings
    return Cp() * pattern * Cp() / function(range_start, range_end)
      table.insert(issues, {code, message, {range_start, range_end + 1}})
    end
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
    Opener = expl_syntax_on + provides,
    Closer = expl_syntax_off,
  }
  lpeg.match(analysis_grammar, state.content)
  -- If no parts were detected, assume that the whole input file is in expl3.
  if(#state.ranges == 0 and #state.content > 0) then
    table.insert(state.ranges, {0, #state.content})
    table.insert(state.warnings, {'w100', 'no standard delimiters', nil})
    local updated_errors = {}
    for _, issue in ipairs(state.errors) do
      if issue[1] ~= 'e102' then
        table.insert(updated_errors, issue)
      end
    end
    state.errors = updated_errors
  end
  return line_starting_byte_numbers
end

return preprocessing