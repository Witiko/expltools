local lpeg = require("lpeg")

-- Define base parsers.
local expl_syntax_on = lpeg.P([[\ExplSyntaxOn]])
local expl_syntax_off = lpeg.P([[\ExplSyntaxOff]])
local any = lpeg.P(1)
local eof = -any

-- Define top-level grammar rules.
local Opener = expl_syntax_on  -- TODO: Add other openers: `\ProvidesExplPackage`, `\ProvidesExplClass`, and `\ProvidesExplFile`.
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
