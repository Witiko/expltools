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
  FUNCTION_VARIANT_DEFINITION = "function variant definition",
  OTHER_STATEMENT = "other statement",
  OTHER_TOKENS_SIMPLE = "block of other simple tokens",
  OTHER_TOKENS_COMPLEX = "block of other complex tokens",
}

local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION
local OTHER_STATEMENT = statement_types.OTHER_STATEMENT
local OTHER_TOKENS_SIMPLE = statement_types.OTHER_TOKENS_SIMPLE
local OTHER_TOKENS_COMPLEX = statement_types.OTHER_TOKENS_COMPLEX

local statement_subtypes = {
  FUNCTION_DEFINITION = {
    DIRECT = "direct function definition",
    INDIRECT = "indirect function definition",
  }
}

local FUNCTION_DEFINITION_DIRECT = statement_subtypes.FUNCTION_DEFINITION.DIRECT
local FUNCTION_DEFINITION_INDIRECT = statement_subtypes.FUNCTION_DEFINITION.INDIRECT

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
      if simple_text_catcodes[token.catcode] == nil then
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

      -- Try and convert tokens from a range into a string.
      local function extract_string_from_tokens(token_range)
        local token_texts = {}
        for _, token in token_range:enumerate(transformed_tokens, first_map_forward) do
          if token.type == CONTROL_SEQUENCE or token.type == ARGUMENT then  -- complex material, give up
            return nil
          else
            table.insert(token_texts, token.payload)
          end
        end
        return table.concat(token_texts)
      end

      -- Get the byte range for a given token.
      local function get_token_byte_range(token_number)
        local byte_range = tokens[token_number].byte_range
        return byte_range
      end

      local call_range = new_range(call_number, call_number, INCLUSIVE, #calls)
      local byte_range = call.token_range:new_range_from_subranges(get_token_byte_range, #content)

      -- Split an expl3 control sequence name to a stem and the argument specifiers.
      local function parse_expl3_csname(csname)
        local _, _, csname_stem, argument_specifiers = csname:find("([^:]*):([^:]*)")
        return csname_stem, argument_specifiers
      end

      -- Replace the argument specifiers in an expl3 control sequence name.
      local function replace_argument_specifiers(csname, argument_specifiers)
        local csname_stem, base_argument_specifiers = parse_expl3_csname(csname)
        if csname_stem == nil or base_argument_specifiers == nil then
          return nil  -- we couldn't parse the csname, give up
        end
        return string.format("%s:%s", csname_stem, argument_specifiers)
      end

      -- Determine the control sequence name of a conditional function given a base control sequence name and a condition.
      local function get_conditional_function_csname(csname, condition)
        local csname_stem, argument_specifiers = parse_expl3_csname(csname)
        if csname_stem == nil or argument_specifiers == nil then
          return nil  -- we couldn't parse the csname, give up
        end
        if condition == "p" then  -- predicate function
          return string.format("%s_p:%s", csname_stem, argument_specifiers)
        elseif condition == "T" then  -- true-branch conditional function
          return string.format("%s:%sT", csname_stem, argument_specifiers)
        elseif condition == "F" then  -- false-branch conditional function
          return string.format("%s:%sF", csname_stem, argument_specifiers)
        elseif condition == "TF" then  -- true-and-false-branch conditional function
          return string.format("%s:%sTF", csname_stem, argument_specifiers)
        else
          error('Unexpected condition "' .. condition .. '"')
        end
      end

      -- Try and extract a list of conditions in a conditional function (variant) definition.
      -- Together with the conditions, include a measurement of confidence about the correctness of the extracted information.
      local function parse_conditions(argument)
        local conditions

        -- try to determine the list of conditions
        local conditions_text, condition_list
        if argument.specifier ~= "n" then  -- conditions are hidden behind expansion, assume all conditions with lower confidence
          goto unknown_conditions
        end
        conditions_text = extract_string_from_tokens(argument.token_range)
        if conditions_text == nil then  -- failed to read conditions
          goto unknown_conditions  -- assume all conditions with lower confidence
        end
        condition_list = lpeg.match(parsers.conditions, conditions_text)
        if condition_list == nil then  -- cound not parse conditions, give up
          return nil
        end
        conditions = {}
        for _, condition in ipairs(condition_list) do
          table.insert(conditions, {condition, DEFINITELY})
        end
        goto done_parsing

        ::unknown_conditions::
        -- assume all possible conditions with lower confidence
        conditions = {{"p", MAYBE}, {"T", MAYBE}, {"F", MAYBE}, {"TF", MAYBE}}

        ::done_parsing::
        return conditions
      end

      -- Try and extract a list of variant argument specifiers in a (conditional) function variant definition.
      -- Together with the argument specifiers, include a measurement of confidence about the correctness of the extracted information.
      local function parse_variant_argument_specifiers(csname, argument)
        -- extract the argument specifiers from the csname
        local _, base_argument_specifiers = parse_expl3_csname(csname)
        if base_argument_specifiers == nil then
          return nil  -- we couldn't parse the csname, give up
        end

        local variant_argument_specifiers

        -- try to determine all sets of variant argument specifiers
        local variant_argument_specifiers_text, variant_argument_specifiers_list
        if argument.specifier ~= "n" then  -- specifiers are hidden behind expansion, assume all possibilities with lower confidence
          goto unknown_argument_specifiers
        end
        variant_argument_specifiers_text = extract_string_from_tokens(argument.token_range)
        if variant_argument_specifiers_text == nil then  -- failed to read specifiers
          goto unknown_argument_specifiers  -- assume all specifiers with lower confidence
        end
        variant_argument_specifiers_list = lpeg.match(parsers.variant_argument_specifiers, variant_argument_specifiers_text)
        if variant_argument_specifiers_list == nil then  -- cound not parse specifiers, assume all possibilities with lower confidence
          goto unknown_argument_specifiers
        end
        variant_argument_specifiers = {}
        for _, argument_specifiers in ipairs(variant_argument_specifiers_list) do
          if #argument_specifiers ~= #base_argument_specifiers then
            if #argument_specifiers < #base_argument_specifiers then  -- variant argument specifiers are shorter than base specifiers
              argument_specifiers = string.format(
                "%s%s",  -- treat the variant specifiers as a prefix with the rest filled in with the base specifiers
                argument_specifiers, base_argument_specifiers:sub(#argument_specifiers + 1)
              )
            else  -- variant argument specifiers are longer than base specifiers
              issues:add("t403", "function variant of incompatible type", byte_range)
              return nil  -- give up
            end
          end
          assert(#argument_specifiers == #base_argument_specifiers)
          local any_specifiers_changed = false
          for i = 1, #argument_specifiers do
            local base_argument_specifier = base_argument_specifiers:sub(i, i)
            argument.specifier = argument_specifiers:sub(i, i)
            if base_argument_specifier == argument.specifier then  -- variant argument specifier is same as base argument specifier
              goto continue  -- skip further checks
            end
            any_specifiers_changed = true
            local any_compatible_specifier = false
            for _, compatible_specifier in ipairs(lpeg.match(parsers.compatible_argument_specifiers, base_argument_specifier)) do
              if argument.specifier == compatible_specifier then  -- variant argument specifier is compatible with base argument specifier
                any_compatible_specifier = true
                break  -- skip further checks
              end
            end
            if not any_compatible_specifier then
              local any_deprecated_specifier = false
              for _, deprecated_specifier in ipairs(lpeg.match(parsers.deprecated_argument_specifiers, base_argument_specifier)) do
                if argument.specifier == deprecated_specifier then  -- variant argument specifier is deprecated regarding the base specifier
                  any_deprecated_specifier = true
                  break  -- skip further checks
                end
              end
              if any_deprecated_specifier then
                issues:add("w410", "function variant of deprecated type", byte_range)
              else
                issues:add("t403", "function variant of incompatible type", byte_range)
                return nil  -- variant argument specifier is incompatible with base argument specifier, give up
              end
            end
            ::continue::
          end
          if not any_specifiers_changed then
            issues:add("w407", "multiply defined function variant", byte_range)
            return nil  -- variant argument specifiers are the same as base argument specifiers, give up
          end
          table.insert(variant_argument_specifiers, {argument_specifiers, DEFINITELY})
        end
        goto done_parsing

        ::unknown_argument_specifiers::
        -- assume all possible sets of variant argument specifiers with lower confidence
        variant_argument_specifiers_list = {""}
        for i = 1, #base_argument_specifiers do
          local base_argument_specifier = base_argument_specifiers:sub(i, i)
          local intermediate_result = {}
          for _, prefix in ipairs(variant_argument_specifiers_list) do
            for _, compatible_specifier in ipairs(lpeg.match(parsers.compatible_argument_specifiers, base_argument_specifier)) do
              table.insert(intermediate_result, prefix .. compatible_specifier)
            end
          end
          variant_argument_specifiers_list = intermediate_result
          if #intermediate_result > 10000 then  -- if there are too many possible variant argument specifiers
            return nil  -- give up to prevent a combinatorial explosion
            -- TODO: produce a special "wildcard" return value instead; this will complicate processing but should remain O(1)
          end
        end
        variant_argument_specifiers = {}
        for _, argument_specifiers in ipairs(variant_argument_specifiers_list) do
          if base_argument_specifiers ~= argument_specifiers then
            table.insert(variant_argument_specifiers, {argument_specifiers, MAYBE})
          end
        end

        ::done_parsing::
        return variant_argument_specifiers
      end

      if call.type == CALL then  -- a function call
        -- Ignore error S204 (Missing stylistic whitespaces) in Lua code.
        for _, arguments_number in ipairs(lpeg.match(parsers.expl3_function_call_with_lua_code_argument_csname, call.csname)) do
          local lua_code_argument = call.arguments[arguments_number]
          if #lua_code_argument.token_range > 0 then
            local lua_code_byte_range = lua_code_argument.token_range:new_range_from_subranges(get_token_byte_range, #content)
            issues:ignore('s204', lua_code_byte_range)
          end
        end

        local function_variant_definition = lpeg.match(parsers.expl3_function_variant_definition_csname, call.csname)
        local direct_function_definition = lpeg.match(parsers.expl3_direct_function_definition_csname, call.csname)
        local indirect_function_definition = lpeg.match(parsers.expl3_indirect_function_definition_csname, call.csname)

        -- Process a function variant definition.
        if function_variant_definition ~= nil then
          local is_conditional = table.unpack(function_variant_definition)
          -- determine the name of the defined function
          local base_csname_argument = call.arguments[1]
          assert(base_csname_argument.specifier == "N" and #base_csname_argument.token_range == 1)
          local base_csname_token = transformed_tokens[first_map_forward(base_csname_argument.token_range:start())]
          local base_csname = base_csname_token.payload
          if base_csname_token.type ~= CONTROL_SEQUENCE then  -- name is not a control sequence, give up
            goto other_statement
          end
          assert(base_csname ~= nil)
          -- determine the variant argument specifiers
          local variant_argument_specifiers = parse_variant_argument_specifiers(base_csname, call.arguments[2])
          if variant_argument_specifiers == nil then  -- we couldn't parse the variant argument specifiers, give up
            goto other_statement
          end
          -- determine all defined csnames
          local defined_csnames = {}
          for _, argument_specifier_table in ipairs(variant_argument_specifiers) do
            local argument_specifiers, argument_specifier_confidence = table.unpack(argument_specifier_table)
            local defined_csname = replace_argument_specifiers(base_csname, argument_specifiers)
            if defined_csname == nil then  -- we couldn't determine the defined csname, give up
              goto other_statement
            end
            if is_conditional then  -- conditional function
              -- determine the conditions
              local conditions = parse_conditions(call.arguments[#call.arguments])
              if conditions == nil then  -- we couldn't determine the conditions, give up
                goto other_statement
              end
              -- determine the defined csnames
              for _, condition_table in ipairs(conditions) do
                local condition, condition_confidence = table.unpack(condition_table)
                local base_conditional_csname = get_conditional_function_csname(base_csname, condition)
                local defined_conditional_csname = get_conditional_function_csname(defined_csname, condition)
                if defined_conditional_csname == nil then  -- we couldn't determine the defined csname, give up
                  goto other_statement
                end
                local confidence = math.min(argument_specifier_confidence, condition_confidence)
                table.insert(defined_csnames, {base_conditional_csname, defined_conditional_csname, confidence})
              end
            else  -- non-conditional function
              table.insert(defined_csnames, {base_csname, defined_csname, argument_specifier_confidence})
            end
          end
          -- record function variant definition statements for all effectively defined csnames
          for _, defined_csname_table in ipairs(defined_csnames) do  -- lua
            local effective_base_csname, defined_csname, confidence = table.unpack(defined_csname_table)
            local statement = {
              type = FUNCTION_VARIANT_DEFINITION,
              call_range = call_range,
              confidence = confidence,
              base_csname = effective_base_csname,
              defined_csname = defined_csname,
              is_conditional = is_conditional,
            }
            table.insert(statements, statement)
          end
          goto continue
        end

        -- Process a direct function definition.
        if direct_function_definition ~= nil then
          local is_conditional, is_protected, is_nopar = table.unpack(direct_function_definition)
          -- determine the replacement text
          local replacement_text_argument = call.arguments[#call.arguments]
          if replacement_text_argument.specifier ~= "n" then  -- replacement text is hidden behind expansion, give up
            goto other_statement
          end
          -- determine the name of the defined function
          local defined_csname_argument = call.arguments[1]
          assert(defined_csname_argument.specifier == "N" and #defined_csname_argument.token_range == 1)
          local defined_csname_token = transformed_tokens[first_map_forward(defined_csname_argument.token_range:start())]
          local defined_csname = defined_csname_token.payload
          if defined_csname_token.type ~= CONTROL_SEQUENCE then  -- name is not a control sequence, give up
            goto other_statement
          end
          assert(defined_csname ~= nil)
          -- determine the number of parameters of the defined function
          local num_parameters
          local _, argument_specifiers = parse_expl3_csname(defined_csname)
          if argument_specifiers ~= nil and lpeg.match(parsers.N_or_n_type_argument_specifiers, argument_specifiers) ~= nil then
            num_parameters = #argument_specifiers
          end
          for _, argument in ipairs(call.arguments) do  -- next, try to look for p-type "TeX parameter" argument specifiers
            if lpeg.match(parsers.parameter_argument_specifier, argument.specifier) and argument.num_parameters ~= nil then
              if num_parameters == nil or argument.num_parameters > num_parameters then  -- if one method gives a higher number, trust it
                num_parameters = argument.num_parameters
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
            first_map_forward(replacement_text_argument.token_range:start()),
            first_map_forward(replacement_text_argument.token_range:stop()),
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
          table.insert(replacement_text_tokens, {
            token_range = replacement_text_argument.token_range,
            transformed_tokens = doubly_transformed_tokens,
            map_back = map_back,
            map_forward = map_forward,
          })
          -- determine all effectively defined csnames
          local effectively_defined_csnames = {}
          if is_conditional then  -- conditional function
            -- determine the conditions
            local conditions = parse_conditions(call.arguments[#call.arguments - 1])
            if conditions == nil then  -- we couldn't determine the conditions, give up
              goto other_statement
            end
            -- determine the defined csnames
            for _, condition_table in ipairs(conditions) do
              local condition, confidence = table.unpack(condition_table)
              if condition == "p" and is_protected then
                issues:add("e404", "protected predicate function", byte_range)
              end
              local effectively_defined_csname = get_conditional_function_csname(defined_csname, condition)
              if effectively_defined_csname == nil then  -- we couldn't determine the defined csname, give up
                goto other_statement
              end
              table.insert(effectively_defined_csnames, {effectively_defined_csname, confidence})
            end
          else  -- non-conditional function
            effectively_defined_csnames = {{defined_csname, DEFINITELY}}
          end
          -- record function definition statements for all effectively defined csnames
          for _, effectively_defined_csname_table in ipairs(effectively_defined_csnames) do  -- lua
            local effectively_defined_csname, confidence = table.unpack(effectively_defined_csname_table)
            local statement = {
              type = FUNCTION_DEFINITION,
              subtype = FUNCTION_DEFINITION_DIRECT,
              call_range = call_range,
              confidence = confidence,
              defined_csname = effectively_defined_csname,
              -- The following attributes are specific to the subtype.
              is_conditional = is_conditional,
              is_protected = is_protected,
              is_nopar = is_nopar,
              replacement_text_number = #replacement_text_tokens,
            }
            table.insert(statements, statement)
          end
          goto continue
        end

        -- Process an indirect function definition.
        if indirect_function_definition ~= nil then
          local is_conditional = table.unpack(indirect_function_definition)
          -- determine the name of the defined function
          local defined_csname_argument = call.arguments[1]
          assert(defined_csname_argument.specifier == "N" and #defined_csname_argument.token_range == 1)
          local defined_csname_token = transformed_tokens[first_map_forward(defined_csname_argument.token_range:start())]
          local defined_csname = defined_csname_token.payload
          if defined_csname_token.type ~= CONTROL_SEQUENCE then  -- name is not a control sequence, give up
            goto other_statement
          end
          assert(defined_csname ~= nil)
          -- determine the name of the source function
          local source_csname_argument = call.arguments[2]
          assert(source_csname_argument.specifier == "N" and #source_csname_argument.token_range == 1)
          local source_csname_token = transformed_tokens[first_map_forward(source_csname_argument.token_range:start())]
          local source_csname = source_csname_token.payload
          if source_csname_token.type ~= CONTROL_SEQUENCE then  -- name is not a control sequence, give up
            goto other_statement
          end
          assert(source_csname ~= nil)
          -- determine all effectively defined csnames and effective source csnames
          local effective_defined_and_source_csnames = {}
          if is_conditional then  -- conditional function
            -- determine the conditions
            local conditions = parse_conditions(call.arguments[#call.arguments - 1])
            if conditions == nil then  -- we couldn't determine the conditions, give up
              goto other_statement
            end
            -- determine the defined and source csnames
            for _, condition_table in ipairs(conditions) do
              local condition, confidence = table.unpack(condition_table)
              local effectively_defined_csname = get_conditional_function_csname(defined_csname, condition)
              local effective_source_csname = get_conditional_function_csname(source_csname, condition)
              if effectively_defined_csname == nil or effective_source_csname == nil then  -- we couldn't determine a csname, give up
                goto other_statement
              end
              table.insert(effective_defined_and_source_csnames, {effectively_defined_csname, effective_source_csname, confidence})
            end
          else  -- non-conditional function
            effective_defined_and_source_csnames = {{defined_csname, source_csname, DEFINITELY}}
          end
          -- record function definition statements for all effectively defined csnames
          for _, effective_defined_and_source_csname_table in ipairs(effective_defined_and_source_csnames) do  -- lua
            local effectively_defined_csname, effective_source_csname, confidence = table.unpack(effective_defined_and_source_csname_table)
            local statement = {
              type = FUNCTION_DEFINITION,
              subtype = FUNCTION_DEFINITION_INDIRECT,
              call_range = call_range,
              confidence = confidence,
              defined_csname = effectively_defined_csname,
              -- The following attributes are specific to the subtype.
              source_csname = effective_source_csname,
              is_conditional = is_conditional,
            }
            table.insert(statements, statement)
          end
          goto continue
        end

        ::other_statement::
        local statement = {
          type = OTHER_STATEMENT,
          call_range = call_range,
        }
        table.insert(statements, statement)
      elseif call.type == OTHER_TOKENS then  -- other tokens
        local statement_type = classify_tokens(tokens, call.token_range)
        local statement = {
          type = statement_type,
          call_range = call_range,
        }
        table.insert(statements, statement)
      else
        error('Unexpected call type "' .. call.type .. '"')
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
        -- record the current nesting depth with the replacement text
        table.insert(replacement_texts.nesting_depth, current_nesting_depth)
        -- extract nested calls from the replacement text using syntactic analysis
        local nested_calls = get_calls(
          tokens,
          replacement_text_tokens.transformed_tokens,
          replacement_text_tokens.token_range,
          replacement_text_tokens.map_back,
          replacement_text_tokens.map_forward,
          issues,
          groupings
        )
        table.insert(replacement_texts.calls, nested_calls)
        -- extract nested statements and replacement texts from the nested calls using semactic analysis
        local nested_statements, nested_replacement_text_tokens = record_statements_and_replacement_texts(
          tokens,
          replacement_text_tokens.transformed_tokens,
          nested_calls,
          replacement_text_tokens.map_back,
          replacement_text_tokens.map_forward
        )
        for _, nested_statement in ipairs(nested_statements) do
          if nested_statement.type == FUNCTION_DEFINITION and nested_statement.subtype == FUNCTION_DEFINITION_DIRECT then
            -- make the reference to the replacement text absolute instead of relative
            nested_statement.replacement_text_number = nested_statement.replacement_text_number + current_num_replacement_texts
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
      local replacement_text_tokens = part_replacement_texts.tokens[replacement_text_number]
      table.insert(token_segments, {part_tokens, replacement_text_tokens.transformed_tokens, replacement_text_tokens.map_forward})
    end
  end

  -- Determine whether a function is private or public based on its name.
  local function is_function_private(csname)
    return csname:sub(1, 2) == "__"
  end

  --- Make a pass over the segments, building up information.
  local defined_private_functions, defined_private_function_variants = {}, {}
  local defined_function_variant_csnames, variant_base_csnames = {}, {}
  local maybe_defined_csnames, maybe_used_csnames = {}, {}
  for segment_number, segment_statements in ipairs(statement_segments) do
    local segment_calls = call_segments[segment_number]
    local segment_tokens, segment_transformed_tokens, map_forward = table.unpack(token_segments[segment_number])

    -- Get the token range for a given call.
    local function get_call_token_range(call_number)
      local token_range = segment_calls[call_number].token_range
      return token_range
    end

    -- Get the byte range for a given token.
    local function get_token_byte_range(token_number)
      local byte_range = segment_tokens[token_number].byte_range
      return byte_range
    end

    for _, statement in ipairs(segment_statements) do
      local token_range = statement.call_range:new_range_from_subranges(get_call_token_range, #segment_tokens)
      local byte_range = token_range:new_range_from_subranges(get_token_byte_range, #content)
      if statement.type == FUNCTION_VARIANT_DEFINITION then
        -- Record private function variant defitions.
        maybe_used_csnames[statement.base_csname] = true
        maybe_defined_csnames[statement.defined_csname] = true
        table.insert(variant_base_csnames, {statement.base_csname, byte_range})
        if statement.confidence == DEFINITELY then
          if defined_function_variant_csnames[statement.defined_csname] then
            issues:add("w407", "multiply defined function variant", byte_range)
          end
          defined_function_variant_csnames[statement.defined_csname] = true
          if is_function_private(statement.defined_csname) then
            table.insert(defined_private_function_variants, {statement.defined_csname, byte_range})
          end
        end
      elseif statement.type == FUNCTION_DEFINITION then
        -- Record private function defitions.
        maybe_defined_csnames[statement.defined_csname] = true
        if statement.confidence == DEFINITELY and is_function_private(statement.defined_csname) then
          table.insert(defined_private_functions, {statement.defined_csname, byte_range})
        end
      elseif statement.type == OTHER_STATEMENT then
        -- Record control sequences used in other statements.
        -- TODO: Also record partially-understood control sequences like `\use:c{__ccool_aux_prop:\g__ccool_option_expans_tl}` from line
        --       55 of file `ccool.sty` in TeX Live 2024, which, if understood as the wildcard `__ccool_aux_prop:*` should silence issue
        --       W401 on line 50 of the same file. There should likely be some minimum number of understood tokens to prevent statements
        --       like `\use:c{\foo}` from silencing all issues of this type.
        for _, call in statement.call_range:enumerate(segment_calls) do
          maybe_used_csnames[call.csname] = true
          for _, argument in ipairs(call.arguments) do
            if lpeg.match(parsers.N_or_n_type_argument_specifier, argument.specifier) ~= nil then
              for _, token in argument.token_range:enumerate(segment_transformed_tokens, map_forward) do
                if token.type == CONTROL_SEQUENCE then
                  maybe_used_csnames[token.payload] = true
                end
              end
            end
          end
        end
      elseif statement.type == OTHER_TOKENS_SIMPLE or statement.type == OTHER_TOKENS_COMPLEX then
        -- Record control sequence names in blocks of other unrecognized tokens.
        for _, token in token_range:enumerate(segment_transformed_tokens, map_forward) do
          if token.type == CONTROL_SEQUENCE then
            maybe_used_csnames[token.payload] = true
          end
        end
      else
        error('Unexpected statement type "' .. statement.type .. '"')
      end
    end
  end

  --- Report issues apparent from the collected information.
  for _, defined_private_function in ipairs(defined_private_functions) do
    local defined_csname, byte_range = table.unpack(defined_private_function)
    if not maybe_used_csnames[defined_csname] then
      issues:add('w401', 'unused private function', byte_range)
    end
  end
  for _, defined_private_function_variant in ipairs(defined_private_function_variants) do
    local defined_csname, byte_range = table.unpack(defined_private_function_variant)
    if not maybe_used_csnames[defined_csname] then
      issues:add('w402', 'unused private function variant', byte_range)
    end
  end
  for _, variant_base_csname in ipairs(variant_base_csnames) do
    local base_csname, byte_range = table.unpack(variant_base_csname)
    if not maybe_defined_csnames[base_csname] and lpeg.match(parsers.expl3_maybe_standard_library_csname, base_csname) == nil then
      issues:add('e405', 'function variant for an undefined function', byte_range)
    end
  end

  -- Store the intermediate results of the analysis.
  results.statements = statements
  results.replacement_texts = replacement_texts
end

return {
  process = semantic_analysis,
  statement_types = statement_types,
  statement_subtypes = statement_subtypes,
}
