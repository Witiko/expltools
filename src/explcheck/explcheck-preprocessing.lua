local lpeg = require("lpeg")
local P, S = lpeg.P, lpeg.S

-- Define base parsers.
---- Generic
local any = P(1)
local eof = -any

---- Tokens
local lbrace = P("{")
local rbrace = P("}")
local percent_sign = P("%")

---- Spacing
local newline = P("\n")
              + P("\r\n")
              + P("\r")
local linechar = any - newline
local spacechar = S("\t ")

-- Define intermediate parsers.
---- Parts of TeX syntax
local comment = percent_sign
              * linechar^0
              * newline
              * spacechar^0
local argument = lbrace
               * (
                 comment
                 + (any - rbrace)
               )^0
               * rbrace

---- Standard delimiters
local provides = P([[\ProvidesExpl]])
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
local expl_syntax_on = P([[\ExplSyntaxOn]])
local expl_syntax_off = P([[\ExplSyntaxOff]])

-- Define top-level grammar rules.
local Opener = expl_syntax_on
             + provides
local Closer = expl_syntax_off

local function preprocessing(state)
  -- Determine which parts of the input files contain expl3 code.
  state.ranges = {}
  local function capture_range(range_start, range_end)
    table.insert(state.ranges, {range_start, range_end + 1})
  end
  local grammar = (
    (
      (any - Opener)^0
      * Opener
      * lpeg.Cp()
      * (any - Closer)^0
      * lpeg.Cp()
      * (Closer + eof)
    ) / capture_range
  )^0
  lpeg.match(grammar, state.content)
  -- If no parts were detected, assume that the whole input file is in expl3.
  if(#state.ranges == 0 and #state.content > 0) then
    table.insert(state.ranges, {0, #state.content})
    table.insert(state.warnings, {'W100', 'no standard delimiters', nil})
  end
end

return preprocessing
