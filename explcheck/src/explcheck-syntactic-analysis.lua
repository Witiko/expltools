-- The syntactic analysis step of static analysis converts TeX tokens into a tree of function calls.

local parsers = require("explcheck-parsers")  -- luacheck: ignore parsers

local lpeg = require("lpeg")  -- luacheck: ignore lpeg

-- Convert the content to a tree of function calls an register any issues.
local function syntactic_analysis(pathname, all_content, issues, results, options)  -- luacheck: ignore pathname all_content issues options
  local all_tokens = results.tokens  -- luacheck: ignore all_tokens
  local all_groupings = results.groupings  -- luacheck: ignore all_groupings
end

return syntactic_analysis
