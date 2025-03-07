-- The syntactic analysis step of static analysis converts TeX tokens into a tree of function calls.

local new_range = require("explcheck-ranges")
local parsers = require("explcheck-parsers")  -- luacheck: ignore parsers

local lpeg = require("lpeg")  -- luacheck: ignore lpeg

-- Convert the content to a tree of function calls an register any issues.
local function syntactic_analysis(pathname, content, issues, results, options)  -- luacheck: ignore pathname content issues options

  -- Extract function calls from TeX tokens and groupings.
  local function get_calls(tokens, token_range, groupings)  -- luacheck: ignore tokens token_range groupings
    -- TODO: See the documentation of `\peek_N_type:TF` for a definition of N- and n-type tokens.
  end

  local calls = {}
  for part_number, part_tokens in ipairs(results.tokens) do
    local part_groupings = results.groupings[part_number]
    local part_token_range = new_range(1, #part_tokens, "inclusive", #part_tokens)
    local part_calls = get_calls(part_tokens, part_token_range, part_groupings)
    table.insert(calls, part_calls)
  end

  -- Store the intermediate results of the analysis.
  results.calls = calls
end

return syntactic_analysis
