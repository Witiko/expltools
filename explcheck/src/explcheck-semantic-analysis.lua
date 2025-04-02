-- The semantic analysis step of static analysis determines the meaning of the different function calls.

-- Determine the meaning of function calls and register any issues.
local function semantic_analysis(pathname, content, _, _, options)  -- luacheck: ignore pathname content options
end

return {
  process = semantic_analysis,
}
