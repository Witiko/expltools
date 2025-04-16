-- The semantic analysis step of static analysis determines the meaning of the different function calls.

local syntactic_analysis = require("explcheck-syntactic-analysis")
local parsers = require("explcheck-parsers")

local call_types = syntactic_analysis.call_types
local get_calls = syntactic_analysis.get_calls
local transform_replacement_text_tokens = syntactic_analysis.transform_replacement_text_tokens

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
local function semantic_analysis(pathname, content, issues, results, options)  -- luacheck: ignore pathname options

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
  local function get_statements(tokens, groupings, calls)
    local statements = {}
    local replacement_text_tokens = {}
    local replacement_text_calls = {}
    for _, call in ipairs(calls) do
      local call_type, token_range = table.unpack(call)
      local statement
      if call_type == CALL then  -- a function call
        local _, _, csname, arguments = table.unpack(call)  -- luacheck: ignore arguments
        local function_definition = lpeg.match(parsers.expl3_function_definition_csname, csname)
        if function_definition ~= nil then  -- function definition
          local protected, nopar = table.unpack(function_definition)  -- determine properties of the defined function
          -- determine the replacement text
          local replacement_text_specifier, replacement_text_token_range = table.unpack(arguments[#arguments])
          if replacement_text_specifier ~= "n" then  -- replacement text is hidden behind expansion, give up
            goto other_statement
          end
          -- determine the name of the defined function
          local defined_csname_specifier, defined_csname_token_range = table.unpack(arguments[1])
          assert(defined_csname_specifier == "N" and #defined_csname_token_range == 1)
          local defined_csname = tokens[defined_csname_token_range:start()][2]
          -- determine the number of parameters of the defined function
          local num_parameters
          local _, _, argument_specifiers = defined_csname:find(":([^:]*)")  -- first, parse the name of the defined function
          if argument_specifiers ~= nil and lpeg.match(parsers.N_or_n_type_argument_specifiers, argument_specifiers) ~= nil then
            num_parameters = #argument_specifiers
          end
          for _, argument in ipairs(arguments) do  -- next, try to look for p-type "TeX parameter" argument specifiers
            if lpeg.match(parsers.parameter_argument_specifier, argument[1]) and argument[3] ~= nil then
              if num_parameters == nil or argument[3] > num_parameters then  -- if one method gives a higher number, trust it
                num_parameters = argument[3]
              end
              assert(num_parameters ~= nil)
              break
            end
          end
          if num_parameters == nil then  -- we couldn't determine the number of parameters, give up
            goto other_statement
          end
          -- parse the replacement text and record the function definition
          local transformed_tokens, map_back, map_forward
            = transform_replacement_text_tokens(content, tokens, issues, num_parameters, replacement_text_token_range)
          if transformed_tokens == nil then  -- we couldn't parse the replacement text, give up
            goto other_statement
          end
          local nested_calls
            = get_calls(tokens, transformed_tokens, replacement_text_token_range, map_back, map_forward, issues, groupings)
          table.insert(replacement_text_tokens, {replacement_text_token_range, transformed_tokens, map_back, map_forward})
          table.insert(replacement_text_calls, nested_calls)
          statement = {FUNCTION_DEFINITION, protected, nopar, #replacement_text_calls}
          goto continue
        end
        ::other_statement::
        statement = {OTHER_STATEMENT}
        ::continue::
      elseif call_type == OTHER_TOKENS then  -- other tokens
        local statement_type = classify_tokens(tokens, token_range)
        statement = {statement_type}
      else
        error('Unexpected call type "' .. call_type .. '"')
      end
      table.insert(statements, statement)
    end
    assert(#statements == #calls)
    assert(#replacement_text_calls == #replacement_text_tokens)
    return statements
  end

  local statements = {}
  for part_number, part_calls in ipairs(results.calls) do
    local part_tokens = results.tokens[part_number]
    local part_groupings = results.groupings[part_number]
    local part_statements = get_statements(part_tokens, part_groupings, part_calls)
    table.insert(statements, part_statements)
  end

  -- Store the intermediate results of the analysis.
  results.statements = statements
end

return {
  process = semantic_analysis,
  statement_types = statement_types,
}
