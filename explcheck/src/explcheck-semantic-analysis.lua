-- The semantic analysis step of static analysis determines the meaning of the different function calls.

local call_types = require("explcheck-syntactic-analysis").call_types
local parsers = require("explcheck-parsers")

local CALL = call_types.CALL
local OTHER_TOKENS = call_types.OTHER_TOKENS

local lpeg = require("lpeg")

local statement_types = {
  FUNCTION_DEFINITION = "function definition",
  OTHER_STATEMENT = "other statement",
  OTHER_TOKENS_SIMPLE = "block of other simple tokens",
  OTHER_TOKENS_COMPLEX = "block of other complex tokens",
}

local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local OTHER_STATEMENT = statement_types.OTHER_STATEMENT
local OTHER_TOKENS_SIMPLE = statement_types.OTHER_TOKENS_SIMPLE
local OTHER_TOKENS_COMPLEX = statement_types.OTHER_TOKENS_COMPLEX

local simple_text_catcodes = {
  [3] = true,  -- math shift
  [4] = true,  -- alignment tab
  [5] = true,  -- end of line
  [7] = true,  -- superscript
  [8] = true,  -- subscript
  [9] = true,  -- ignored character
  [10] = true,  -- space
  [11] = true,  -- letter
  [12] = true,  -- other
}

-- Determine the meaning of function calls and register any issues.
local function semantic_analysis(pathname, content, _, results, options)  -- luacheck: ignore pathname content options

  -- Determine the type of a span of tokens as either "simple text" [1, p. 383] with no expected side effects or
  -- a more complex material that may have side effects and presents a boundary between chunks of well-understood
  -- expl3 statements.
  --
  --  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
  --
  local function classify_tokens(tokens, token_range)
    for _, token in token_range:enumerate(tokens) do
      local catcode = token[3]
      if simple_text_catcodes[catcode] == nil then
        return OTHER_TOKENS_COMPLEX
      end
    end
    return OTHER_TOKENS_SIMPLE
  end

  -- Extract statements from function calls.
  local function get_statements(tokens, calls)
    local statements = {}
    for _, call in ipairs(calls) do
      local call_type, token_range = table.unpack(call)
      local statement
      if call_type == CALL then  -- a function call
        local _, _, csname, arguments = table.unpack(call)  -- luacheck: ignore arguments
        local function_definition = lpeg.match(parsers.expl3_function_definition_csname, csname)
        if function_definition ~= nil then  -- function definition
          local protected, nopar = table.unpack(function_definition)
          statement = {FUNCTION_DEFINITION, protected, nopar}
        else  -- other statement
          statement = {OTHER_STATEMENT}
        end
      elseif call_type == OTHER_TOKENS then  -- other tokens
        local statement_type = classify_tokens(tokens, token_range)
        statement = {statement_type}
      else
        error('Unexpected call type "' .. call_type .. '"')
      end
      table.insert(statements, statement)
    end
    assert(#statements == #calls)
    return statements
  end

  local statements = {}
  for part_number, part_calls in ipairs(results.calls) do
    local part_tokens = results.tokens[part_number]
    local part_statements = get_statements(part_tokens, part_calls)
    table.insert(statements, part_statements)
  end

  -- Store the intermediate results of the analysis.
  results.statements = statements
end

return {
  process = semantic_analysis,
  statement_types = statement_types,
}
