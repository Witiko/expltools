-- The syntactic analysis step of static analysis converts TeX tokens into a tree of function calls.

local parsers = require("explcheck-parsers")  -- luacheck: ignore parsers

local lpeg = require("lpeg")  -- luacheck: ignore lpeg

-- Convert the content to a tree of function calls an register any issues.
local function syntactic_analysis(pathname, all_content, issues, results, options)  -- luacheck: ignore pathname all_content issues options
  local tokens = results.tokens  -- luacheck: ignore tokens
end

return syntactic_analysis
