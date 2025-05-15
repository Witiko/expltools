-- The semantic analysis step of static analysis determines the meaning of the different function calls.

local token_types = require("explcheck-lexical-analysis").token_types
local syntactic_analysis = require("explcheck-syntactic-analysis")
local ranges = require("explcheck-ranges")
local parsers = require("explcheck-parsers")
local identity = require("explcheck-utils").identity

local ARGUMENT = token_types.ARGUMENT
local CONTROL_SEQUENCE = token_types.CONTROL_SEQUENCE

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

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

local statement_confidences = {
  DEFINITELY = 1,
  MAYBE = 0.5,
}

local DEFINITELY = statement_confidences.DEFINITELY
local MAYBE = statement_confidences.MAYBE

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

  -- Extract statements from function calls and record them. For all identified function definitions, also record replacement texts.
  local function record_statements_and_replacement_texts(tokens, transformed_tokens, calls, first_map_back, first_map_forward)
    local statements = {}
    local replacement_text_tokens = {}
    for call_number, call in ipairs(calls) do
      local call_range = new_range(call_number, call_number, INCLUSIVE, #calls)
      local call_type, token_range = table.unpack(call)

      -- Get the byte range for a given token.
      local function get_token_byte_range(token_number)
        local byte_range = tokens[token_number][4]
        return byte_range
      end

      if call_type == CALL then  -- a function call
        local _, _, csname, arguments = table.unpack(call)

        -- Ignore error S204 (Missing stylistic whitespaces) in Lua code.
        for _, arguments_number in ipairs(lpeg.match(parsers.expl3_function_call_with_lua_code_argument_csname, csname)) do
          local _, lua_code_token_range = table.unpack(arguments[arguments_number])
          if #lua_code_token_range > 0 then
            local lua_code_byte_range = lua_code_token_range:new_range_from_subranges(get_token_byte_range, #content)
            issues:ignore('s204', lua_code_byte_range)
          end
        end

        -- Process a function definition.
        local function_definition = lpeg.match(parsers.expl3_function_definition_csname, csname)
        if function_definition ~= nil then
          local is_function_conditional, is_protected = table.unpack(function_definition)
          -- determine the replacement text
          local replacement_text_specifier, replacement_text_token_range = table.unpack(arguments[#arguments])
          if replacement_text_specifier ~= "n" then  -- replacement text is hidden behind expansion, give up
            goto other_statement
          end
          -- determine the name(s) of the defined function
          local defined_csname_specifier, defined_csname_token_range = table.unpack(arguments[1])
          assert(defined_csname_specifier == "N" and #defined_csname_token_range == 1)
          local defined_csname_token_type, defined_csname
            = table.unpack(transformed_tokens[first_map_forward(defined_csname_token_range:start())])
          if defined_csname_token_type == ARGUMENT then  -- name is hidden behind an argument, give up
            goto other_statement
          end
          assert(defined_csname ~= nil)
          -- determine the number of parameters of the defined function
          local num_parameters
          local _, _, defined_csname_stem, argument_specifiers  -- first, parse the name of the defined function
            = defined_csname:find("([^:]*):([^:]*)")
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
          local mapped_replacement_text_token_range = new_range(
            first_map_forward(replacement_text_token_range:start()),
            first_map_forward(replacement_text_token_range:stop()),
            INCLUSIVE + MAYBE_EMPTY,
            #transformed_tokens
          )
          local doubly_transformed_tokens, second_map_back, second_map_forward
            = transform_replacement_text_tokens(content, transformed_tokens, issues, num_parameters, mapped_replacement_text_token_range)
          if doubly_transformed_tokens == nil then  -- we couldn't parse the replacement text, give up
            goto other_statement
          end
          local function map_back(...) return first_map_back(second_map_back(...)) end
          local function map_forward(...) return second_map_forward(first_map_forward(...)) end
          table.insert(replacement_text_tokens, {replacement_text_token_range, doubly_transformed_tokens, map_back, map_forward})
          -- determine all effectively defined csnames
          local effectively_defined_csnames
          local confidence = DEFINITELY
          if is_function_conditional then  -- conditional function
            local conditions_specifier, conditions_token_range = table.unpack(arguments[#arguments - 1])
            local conditions
            if conditions_specifier ~= "n" then  -- conditions are hidden behind expansion, assume all conditions with lower confidence
              goto unknown_conditions
            else
              -- try to determine the list of conditions
              local conditions_token_texts = {}
              for _, token in conditions_token_range:enumerate(transformed_tokens, first_map_forward) do
                local token_type, token_payload = table.unpack(token)
                if token_type == CONTROL_SEQUENCE or token_type == ARGUMENT then  -- complex material containing arguments and csnames
                  goto unknown_conditions  -- assume all conditions with lower confidence
                else
                  table.insert(conditions_token_texts, token_payload)
                end
              end
              local conditions_text = table.concat(conditions_token_texts)
              local condition_list = lpeg.match(parsers.conditions, conditions_text)
              if condition_list == nil then  -- cound not parse the conditions, assume all conditions with lower confidence
                goto unknown_conditions
              end
              conditions = {}
              for _, condition in ipairs(condition_list) do
                conditions[condition] = true
              end
              goto done_reading_conditions
            end
            ::unknown_conditions::
            confidence = math.min(confidence, MAYBE)
            conditions = {p = true, T = true, F = true, TF = true}
            ::done_reading_conditions::
            -- determine the defined csnames
            if defined_csname_stem == nil or argument_specifiers == nil then  -- we couldn't parse the defined csname, give up
              goto other_statement
            end
            effectively_defined_csnames = {}
            if conditions.p ~= nil then  -- predicate function
              if is_protected then
                local byte_range = token_range:new_range_from_subranges(get_token_byte_range, #content)
                issues:add("e404", "protected predicate function", byte_range)
              end
              table.insert(effectively_defined_csnames, string.format("%s_p:%s", defined_csname_stem, argument_specifiers))
            end
            if conditions.T ~= nil then  -- true-branch conditional function
              table.insert(effectively_defined_csnames, string.format("%s:%sT", defined_csname_stem, argument_specifiers))
            end
            if conditions.F ~= nil then  -- false-branch conditional function
              table.insert(effectively_defined_csnames, string.format("%s:%sF", defined_csname_stem, argument_specifiers))
            end
            if conditions.TF ~= nil then  -- true-and-false-branch conditional function
              table.insert(effectively_defined_csnames, string.format("%s:%sTF", defined_csname_stem, argument_specifiers))
            end
          else  -- non-conditional function
            effectively_defined_csnames = {defined_csname}
          end
          -- record function definition statements for all effectively defined csnames
          for _, effectively_defined_csname in ipairs(effectively_defined_csnames) do  -- lua
            local statement
              = {FUNCTION_DEFINITION, call_range, confidence, effectively_defined_csname, function_definition, #replacement_text_tokens}
            table.insert(statements, statement)
          end
          goto continue
        end

        ::other_statement::
        local statement = {OTHER_STATEMENT, call_range}
        table.insert(statements, statement)
      elseif call_type == OTHER_TOKENS then  -- other tokens
        local statement_type = classify_tokens(tokens, token_range)
        local statement = {statement_type, call_range}
        table.insert(statements, statement)
      else
        error('Unexpected call type "' .. call_type .. '"')
      end
      ::continue::
    end
    return statements, replacement_text_tokens
  end

  -- Extract statements from function calls. For all identified function definitions, record replacement texts and recursively
  -- apply syntactic and semantic analysis on them.
  local function get_statements(tokens, groupings, calls)

    -- First, record top-level statements.
    local replacement_texts = {tokens = nil, calls = {}, statements = {}, nesting_depth = {}}
    local statements
    statements, replacement_texts.tokens = record_statements_and_replacement_texts(tokens, tokens, calls, identity, identity)

    -- Then, process any new replacement texts until convergence.
    local previous_num_replacement_texts = 0
    local current_num_replacement_texts = #replacement_texts.tokens
    local current_nesting_depth = 1
    while previous_num_replacement_texts < current_num_replacement_texts do
      for replacement_text_number = previous_num_replacement_texts + 1, current_num_replacement_texts do
        local replacement_text_tokens = replacement_texts.tokens[replacement_text_number]
        local replacement_text_token_range, transformed_tokens, map_back, map_forward = table.unpack(replacement_text_tokens)
        -- record the current nesting depth with the replacement text
        table.insert(replacement_texts.nesting_depth, current_nesting_depth)
        -- extract nested calls from the replacement text using syntactic analysis
        local nested_calls
          = get_calls(tokens, transformed_tokens, replacement_text_token_range, map_back, map_forward, issues, groupings)
        table.insert(replacement_texts.calls, nested_calls)
        -- extract nested statements and replacement texts from the nested calls using semactic analysis
        local nested_statements, nested_replacement_text_tokens
          = record_statements_and_replacement_texts(tokens, transformed_tokens, nested_calls, map_back, map_forward)
        for _, nested_statement in ipairs(nested_statements) do
          if nested_statement[1] == FUNCTION_DEFINITION then
            -- make the reference to the replacement text absolute instead of relative
            nested_statement[#nested_statement] = nested_statement[#nested_statement] + current_num_replacement_texts
          end
        end
        table.insert(replacement_texts.statements, nested_statements)
        for _, nested_tokens in ipairs(nested_replacement_text_tokens) do
          table.insert(replacement_texts.tokens, nested_tokens)
        end
      end
      previous_num_replacement_texts = current_num_replacement_texts
      current_num_replacement_texts = #replacement_texts.tokens
      current_nesting_depth = current_nesting_depth + 1
    end

    assert(#replacement_texts.tokens == current_num_replacement_texts)
    assert(#replacement_texts.calls == current_num_replacement_texts)
    assert(#replacement_texts.statements == current_num_replacement_texts)
    assert(#replacement_texts.nesting_depth == current_num_replacement_texts)

    return statements, replacement_texts
  end

  -- Extract statements from function calls.
  local statements = {}
  local replacement_texts = {}
  for part_number, part_calls in ipairs(results.calls) do
    local part_tokens = results.tokens[part_number]
    local part_groupings = results.groupings[part_number]
    local part_statements, part_replacement_texts = get_statements(part_tokens, part_groupings, part_calls)
    table.insert(statements, part_statements)
    table.insert(replacement_texts, part_replacement_texts)
  end

  assert(#statements == #results.calls)
  assert(#statements == #replacement_texts)

  -- Report issues that are apparent after the semantic analysis.
  --- Collect all segments of top-level and nested tokens, calls, and statements.
  local token_segments, call_segments, statement_segments = {}, {}, {}
  for part_number, part_calls in ipairs(results.calls) do
    local part_statements = statements[part_number]
    table.insert(call_segments, part_calls)
    table.insert(statement_segments, part_statements)
    local part_tokens = results.tokens[part_number]
    table.insert(token_segments, {part_tokens, part_tokens, identity})
    local part_replacement_texts = replacement_texts[part_number]
    for replacement_text_number, nested_calls in ipairs(part_replacement_texts.calls) do
      local nested_statements = part_replacement_texts.statements[replacement_text_number]
      table.insert(call_segments, nested_calls)
      table.insert(statement_segments, nested_statements)
      local _, nested_tokens, _, map_forward = table.unpack(part_replacement_texts.tokens[replacement_text_number])
      table.insert(token_segments, {part_tokens, nested_tokens, map_forward})
    end
  end

  --- Make a pass over the segments, building up information.
  local defined_private_functions = {}
  local used_csnames = {}
  for segment_number, segment_statements in ipairs(statement_segments) do
    local segment_calls = call_segments[segment_number]
    local part_tokens, segment_tokens, map_forward = table.unpack(token_segments[segment_number])
    for _, statement in ipairs(segment_statements) do
      local statement_type, call_range = table.unpack(statement)
      for _, call in call_range:enumerate(segment_calls) do
        local _, call_token_range, call_csname, arguments = table.unpack(call)
        local call_byte_range = call_token_range:new_range_from_subranges(
          function(token_number)
            local byte_range = part_tokens[token_number][4]
            return byte_range
          end,
          #content
        )
        if statement_type == FUNCTION_DEFINITION then
          -- Record private function defitions.
          local _, _, confidence, defined_csname = table.unpack(statement)
          if confidence == DEFINITELY and defined_csname:sub(1, 2) == "__" then
            table.insert(defined_private_functions, {defined_csname, call_byte_range})
          end
        elseif statement_type == OTHER_STATEMENT then
          -- Record control sequences used in other statements.
          used_csnames[call_csname] = true
          for _, argument in ipairs(arguments) do
            local argument_specifier, argument_token_range = table.unpack(argument)
            if lpeg.match(parsers.N_or_n_type_argument_specifier, argument_specifier) ~= nil then
              for _, token in argument_token_range:enumerate(segment_tokens, map_forward) do
                local token_type, token_payload = table.unpack(token)
                if token_type == CONTROL_SEQUENCE then
                  used_csnames[token_payload] = true
                end
              end
            end
          end
        elseif statement_type == OTHER_TOKENS_SIMPLE or statement_type == OTHER_TOKENS_COMPLEX then
          -- Record control sequence names in blocks of other unrecognized tokens.
          for _, token in call_token_range:enumerate(segment_tokens, map_forward) do
            local token_type, token_payload = table.unpack(token)
            if token_type == CONTROL_SEQUENCE then
              used_csnames[token_payload] = true
            end
          end
        else
          error('Unexpected statement type "' .. statement_type .. '"')
        end
      end
    end
  end

  --- Report issues apparent from the collected information.
  for _, defined_private_function in ipairs(defined_private_functions) do
    local defined_csname, call_byte_range = table.unpack(defined_private_function)
    if used_csnames[defined_csname] == nil then
      issues:add('w401', 'unused private function', call_byte_range)
    end
  end

  -- Store the intermediate results of the analysis.
  results.statements = statements
  results.replacement_texts = replacement_texts
end

return {
  process = semantic_analysis,
  statement_types = statement_types,
}
