-- The semantic analysis step of static analysis determines the meaning of the different function calls.

local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local parsers = require("explcheck-parsers")
local identity = require("explcheck-utils").identity

local get_token_byte_range = lexical_analysis.get_token_byte_range
local is_token_simple = lexical_analysis.is_token_simple
local token_types = lexical_analysis.token_types
local format_csname = lexical_analysis.format_csname

local extract_text_from_tokens = syntactic_analysis.extract_text_from_tokens

local CONTROL_SEQUENCE = token_types.CONTROL_SEQUENCE

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

local call_types = syntactic_analysis.call_types
local get_calls = syntactic_analysis.get_calls
local get_call_token_range = syntactic_analysis.get_call_token_range
local transform_replacement_text_tokens = syntactic_analysis.transform_replacement_text_tokens

local CALL = call_types.CALL
local OTHER_TOKENS = call_types.OTHER_TOKENS

local lpeg = require("lpeg")

local statement_types = {
  FUNCTION_DEFINITION = "function definition",
  FUNCTION_VARIANT_DEFINITION = "function variant definition",
  VARIABLE_DECLARATION = "variable declaration",
  VARIABLE_DEFINITION = "variable or constant definition",
  VARIABLE_USE = "variable or constant use",
  OTHER_STATEMENT = "other statement",
  OTHER_TOKENS_SIMPLE = "block of other simple tokens",
  OTHER_TOKENS_COMPLEX = "block of other complex tokens",
}

local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION

local VARIABLE_DECLARATION = statement_types.VARIABLE_DECLARATION
local VARIABLE_DEFINITION = statement_types.VARIABLE_DEFINITION
local VARIABLE_USE = statement_types.VARIABLE_USE

local OTHER_STATEMENT = statement_types.OTHER_STATEMENT
local OTHER_TOKENS_SIMPLE = statement_types.OTHER_TOKENS_SIMPLE
local OTHER_TOKENS_COMPLEX = statement_types.OTHER_TOKENS_COMPLEX

local statement_subtypes = {
  FUNCTION_DEFINITION = {
    DIRECT = "direct " .. FUNCTION_DEFINITION,
    INDIRECT = "indirect " .. FUNCTION_DEFINITION,
  },
  VARIABLE_DEFINITION = {
    DIRECT = "direct " .. VARIABLE_DEFINITION,
    INDIRECT = "indirect " .. VARIABLE_DEFINITION,
  },
}

local FUNCTION_DEFINITION_DIRECT = statement_subtypes.FUNCTION_DEFINITION.DIRECT
local FUNCTION_DEFINITION_INDIRECT = statement_subtypes.FUNCTION_DEFINITION.INDIRECT

local VARIABLE_DEFINITION_DIRECT = statement_subtypes.VARIABLE_DEFINITION.DIRECT
local VARIABLE_DEFINITION_INDIRECT = statement_subtypes.VARIABLE_DEFINITION.INDIRECT

local statement_confidences = {
  DEFINITELY = 1,
  MAYBE = 0.5,
  NONE = 0,
}

local DEFINITELY = statement_confidences.DEFINITELY
local MAYBE = statement_confidences.MAYBE
local NONE = statement_confidences.NONE

local csname_types = {
  TEXT = "direct text representation of a control sequence name or its part, usually paired with confidence DEFINITELY",
  PATTERN = "a PEG pattern that recognizes different control sequences or their parts, usually paired with confidence MAYBE"
}

local TEXT = csname_types.TEXT
local PATTERN = csname_types.PATTERN

-- Determine whether an expl3 type is a subtype of another type.
local function is_subtype(subtype, supertype)
  if subtype == supertype then
    return true
  elseif (subtype == "str" or subtype == "clist") and supertype == "tl" then
    return true
  elseif (subtype == "ior" or subtype == "iow") and supertype == "int" then
    return true
  -- Without tracking the data flow, we can't distinguish between h?box and v?box, we just know !(hbox <= vbox) and !(vbox <= hbox).
  elseif subtype:sub(-3) == "box" and supertype:sub(-3) == "box" and math.min(#subtype, #supertype) == 3 then
    return true
  -- Without tracking the data flow, we can't distinguish between h?coffin and v?coffin, we just know !(hcoffin <= vcoffin)
  -- and !(vcoffin <= hcoffin).
  elseif subtype:sub(-6) == "coffin" and supertype:sub(-6) == "coffin" and math.min(#subtype, #supertype) == 6 then
    return true
  else
    return false
  end
end

-- Determine whether an expl3 type can perhaps be used by a function of another type.
local function is_maybe_compatible_type(first_type, second_type)
  return is_subtype(first_type, second_type) or is_subtype(second_type, first_type)
end

-- Determine the meaning of function calls and register any issues.
local function semantic_analysis(pathname, content, issues, results, options)

  -- Determine the type of a span of tokens as either "simple text" [1, p. 383] with no expected side effects or
  -- a more complex material that may have side effects and presents a boundary between chunks of well-understood
  -- expl3 statements.
  --
  --  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
  --
  local function classify_tokens(tokens, token_range)
    for _, token in token_range:enumerate(tokens) do
      if not is_token_simple(token) then  -- complex material
        return OTHER_TOKENS_COMPLEX
      end
    end
    return OTHER_TOKENS_SIMPLE  -- simple material
  end

  -- Convert tokens from a range into a PEG pattern.
  local function extract_pattern_from_tokens(token_range, transformed_tokens, map_forward)
    -- First, extract subpatterns and text transcripts for the simple material.
    local subpatterns, subpattern, transcripts, num_simple_tokens = {}, parsers.success, {}, 0
    local previous_token_was_simple = true
    for _, token in token_range:enumerate(transformed_tokens, map_forward) do
      if is_token_simple(token) then  -- simple material
        subpattern = subpattern * lpeg.P(token.payload)
        table.insert(transcripts, token.payload)
        num_simple_tokens = num_simple_tokens + 1
        previous_token_was_simple = true
      else  -- complex material
        if previous_token_was_simple then
          table.insert(subpatterns, subpattern)
          subpattern = parsers.success
          table.insert(transcripts, "*")
        end
        previous_token_was_simple = false
      end
    end
    if previous_token_was_simple then
      table.insert(subpatterns, subpattern)
    end
    local transcript = table.concat(transcripts)
    -- Next, build up the pattern from the back, simulating lazy `.*?` using negative lookaheads.
    local subpattern_separators = {}
    for subpattern_number = #subpatterns, 2, -1 do
      local rest = subpatterns[subpattern_number]
      for separator_number = 1, #subpattern_separators do
        rest = rest * subpattern_separators[#subpattern_separators - separator_number + 1]
        rest = rest * subpatterns[subpattern_number + separator_number]
      end
      local separator = (parsers.any - #rest)^0
      table.insert(subpattern_separators, separator)
    end
    local pattern = parsers.success
    for subpattern_number = 1, #subpatterns do
      pattern = pattern * subpatterns[subpattern_number]
      if subpattern_number < #subpatterns then
        pattern = pattern * subpattern_separators[#subpattern_separators - subpattern_number + 1]
      elseif not previous_token_was_simple then
        pattern = pattern * parsers.any^0
      end
    end
    return pattern, transcript, num_simple_tokens
  end

  -- Try and convert tokens from a range into a csname.
  local function _extract_csname_from_tokens(token_range, transformed_tokens, map_forward)
    local text = extract_text_from_tokens(token_range, transformed_tokens, map_forward)
    local csname
    if text ~= nil then  -- simple material
      csname = {
        payload = text,
        transcript = text,
        type = TEXT
      }
    else  -- complex material
      local pattern, transcript, num_simple_tokens = extract_pattern_from_tokens(token_range, transformed_tokens, map_forward)
      if num_simple_tokens < get_option("min_simple_tokens_in_csname_pattern", options, pathname) then  -- too few simple tokens, give up
        return nil
      end
      csname = {
        payload = pattern,
        transcript = transcript,
        type = PATTERN
      }
    end
    return csname
  end

  -- Extract statements from function calls and record them. For all identified function definitions, also record replacement texts.
  local function record_statements_and_replacement_texts(tokens, transformed_tokens, calls, first_map_back, first_map_forward)
    local statements = {}
    local replacement_text_tokens = {}
    for call_number, call in ipairs(calls) do

      local call_range = new_range(call_number, call_number, INCLUSIVE, #calls)
      local byte_range = call.token_range:new_range_from_subranges(get_token_byte_range(tokens), #content)

      -- Try and convert tokens from an argument into a text.
      local function extract_text_from_argument(argument)
        assert(lpeg.match(parsers.n_type_argument_specifier, argument.specifier) ~= nil)
        return extract_text_from_tokens(argument.token_range, transformed_tokens, first_map_forward)
      end

      -- Try and convert tokens from a range into a csname.
      local function extract_csname_from_tokens(token_range)
        return _extract_csname_from_tokens(token_range, transformed_tokens, first_map_forward)
      end

      -- Extract the name of a control sequence from a call argument.
      local function extract_csname_from_argument(argument)
        local csname
        if argument.specifier == "N" then
          local csname_token = transformed_tokens[first_map_forward(argument.token_range:start())]
          if csname_token.type ~= CONTROL_SEQUENCE then  -- the N-type argument is not a control sequence, give up
            return nil
          end
          csname = {
            payload = csname_token.payload,
            transcript = csname_token.payload,
            type = TEXT
          }
        elseif argument.specifier == "c" then
          csname = extract_csname_from_tokens(argument.token_range)
          if csname == nil then  -- the c-type argument contains complex material, give up
            return nil
          end
        else
          return nil
        end
        assert(csname ~= nil)
        return csname
      end

      -- Split an expl3 control sequence name to a stem and the argument specifiers.
      local function parse_expl3_csname(csname)
        if csname.type == TEXT then
          local _, _, csname_stem, argument_specifiers = csname.payload:find("([^:]*):([^:]*)")
          if csname_stem == nil then
            return nil
          else
            return csname_stem, {
              payload = argument_specifiers,
              transcript = argument_specifiers,
              type = TEXT
            }
          end
        elseif csname.type == PATTERN then
          return nil
        else
          error('Unexpected csname type "' .. csname.type .. '"')
        end
      end

      -- Determine whether a function is private or public based on its name.
      local function is_function_private(csname)
        if csname.type == TEXT then
          return csname.payload:sub(1, 2) == "__"
        elseif csname.type == PATTERN then
          return csname.transcript:sub(1, 2) == "__"
        else
          error('Unexpected csname type "' .. csname.type .. '"')
        end
      end

      -- Replace the argument specifiers in an expl3 control sequence name.
      local function replace_argument_specifiers(csname_stem, argument_specifiers)
        local csname
        local transcript = string.format("%s:%s", csname_stem, argument_specifiers.transcript)
        if argument_specifiers.type == TEXT then
          csname = {
            payload = string.format("%s:%s", csname_stem, argument_specifiers.payload),
            transcript = transcript,
            type = TEXT
          }
        elseif argument_specifiers.type == PATTERN then
          csname = {
            payload = lpeg.P(csname_stem) * lpeg.P(":") * argument_specifiers.payload,
            transcript = transcript,
            type = PATTERN
          }
        else
          error('Unexpected argument specifiers type "' .. argument_specifiers.type .. '"')
        end
        return csname
      end

      -- Determine the control sequence name of a conditional function given a base control sequence name and a condition.
      local function get_conditional_function_csname(csname_stem, argument_specifiers, condition)
        local csname
        if condition == "p" then  -- predicate function
          local format = "%s_p:%s"
          local transcript = string.format(format, csname_stem, argument_specifiers.transcript)
          if argument_specifiers.type == TEXT then
            csname = {
              payload = string.format(format, csname_stem, argument_specifiers.payload),
              transcript = transcript,
              type = TEXT
            }
          elseif argument_specifiers.type == PATTERN then
            csname = {
              payload = lpeg.P(csname_stem) * lpeg.P("_p:") * argument_specifiers.payload,
              transcript = transcript,
              type = PATTERN
            }
          else
            error('Unexpected argument specifiers type "' .. argument_specifiers.type .. '"')
          end
        elseif condition == "T" then  -- true-branch conditional function
          local format = "%s:%sT"
          local transcript = string.format(format, csname_stem, argument_specifiers.transcript)
          if argument_specifiers.type == TEXT then
            csname = {
              payload = string.format(format, csname_stem, argument_specifiers.payload),
              transcript = transcript,
              type = TEXT
            }
          elseif argument_specifiers.type == PATTERN then
            csname = {
              payload = lpeg.P(csname_stem) * lpeg.P(":") * argument_specifiers.payload * lpeg.P("T"),
              transcript = transcript,
              type = PATTERN
            }
          else
            error('Unexpected argument specifiers type "' .. argument_specifiers.type .. '"')
          end
        elseif condition == "F" then  -- false-branch conditional function
          local format = "%s:%sF"
          local transcript = string.format(format, csname_stem, argument_specifiers.transcript)
          if argument_specifiers.type == TEXT then
            csname = {
              payload = string.format(format, csname_stem, argument_specifiers.payload),
              transcript = transcript,
              type = TEXT
            }
          elseif argument_specifiers.type == PATTERN then
            csname = {
              payload = lpeg.P(csname_stem) * lpeg.P(":") * argument_specifiers.payload * lpeg.P("F"),
              transcript = transcript,
              type = PATTERN
            }
          else
            error('Unexpected argument specifiers type "' .. argument_specifiers.type .. '"')
          end
        elseif condition == "TF" then  -- true-and-false-branch conditional function
          local format = "%s:%sTF"
          local transcript = string.format(format, csname_stem, argument_specifiers.transcript)
          if argument_specifiers.type == TEXT then
            csname = {
              payload = string.format(format, csname_stem, argument_specifiers.payload),
              transcript = transcript,
              type = TEXT
            }
          elseif argument_specifiers.type == PATTERN then
            csname = {
              payload = lpeg.P(csname_stem) * lpeg.P(":") * argument_specifiers.payload * lpeg.P("TF"),
              transcript = transcript,
              type = PATTERN,
            }
          else
            error('Unexpected argument specifiers type "' .. argument_specifiers.type .. '"')
          end
        else
          error('Unexpected condition "' .. condition .. '"')
        end
        return csname
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
        conditions_text = extract_text_from_argument(argument)
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
        if base_argument_specifiers == nil or base_argument_specifiers.type ~= TEXT then
          return nil  -- we couldn't parse the csname, give up
        end
        base_argument_specifiers = base_argument_specifiers.payload

        local variant_argument_specifiers

        -- try to determine all sets of variant argument specifiers
        local variant_argument_specifiers_text, variant_argument_specifiers_list
        if argument.specifier ~= "n" then  -- specifiers are hidden behind expansion, assume all possibilities with lower confidence
          goto unknown_argument_specifiers
        end
        variant_argument_specifiers_text = extract_text_from_argument(argument)
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
              local context = string.format("%s -> %s", base_argument_specifiers, argument_specifiers)
              issues:add("t403", "function variant of incompatible type", byte_range, context)
              return nil  -- give up
            end
          end
          assert(#argument_specifiers == #base_argument_specifiers)
          for i = 1, #argument_specifiers do
            local base_argument_specifier = base_argument_specifiers:sub(i, i)
            local argument_specifier = argument_specifiers:sub(i, i)
            if base_argument_specifier == argument_specifier then  -- variant argument specifier is same as base argument specifier
              goto continue  -- skip further checks
            end
            local any_compatible_specifier = false
            for _, compatible_specifier in ipairs(lpeg.match(parsers.compatible_argument_specifiers, base_argument_specifier)) do
              if argument_specifier == compatible_specifier then  -- variant argument specifier is compatible with base argument specifier
                any_compatible_specifier = true
                break  -- skip further checks
              end
            end
            if not any_compatible_specifier then
              local any_deprecated_specifier = false
              for _, deprecated_specifier in ipairs(lpeg.match(parsers.deprecated_argument_specifiers, base_argument_specifier)) do
                if argument_specifier == deprecated_specifier then  -- variant argument specifier is deprecated regarding the base specifier
                  any_deprecated_specifier = true
                  break  -- skip further checks
                end
              end
              local context = string.format("%s -> %s", base_argument_specifiers, argument_specifiers)
              if any_deprecated_specifier then
                issues:add("w410", "function variant of deprecated type", byte_range, context)
              else
                issues:add("t403", "function variant of incompatible type", byte_range, context)
                return nil  -- variant argument specifier is incompatible with base argument specifier, give up
              end
            end
            ::continue::
          end
          table.insert(variant_argument_specifiers, {
            payload = argument_specifiers,
            transcript = argument_specifiers,
            type = TEXT,
            confidence = DEFINITELY
          })
        end
        goto done_parsing

        ::unknown_argument_specifiers::
        -- assume all possible sets of variant argument specifiers with lower confidence
        do
          variant_argument_specifiers = {}
          local compatible_specifier_pattern, compatible_specifier_transcripts = parsers.success, {}
          for i = 1, #base_argument_specifiers do
            local base_argument_specifier = base_argument_specifiers:sub(i, i)
            local compatible_specifiers = table.concat(lpeg.match(parsers.compatible_argument_specifiers, base_argument_specifier))
            compatible_specifier_pattern = compatible_specifier_pattern * lpeg.S(compatible_specifiers)
            local compatible_specifier_transcript = string.format('[%s]', compatible_specifiers)
            table.insert(compatible_specifier_transcripts, compatible_specifier_transcript)
          end
          local compatible_specifiers_transcript = table.concat(compatible_specifier_transcripts)
          table.insert(variant_argument_specifiers, {
            payload = compatible_specifier_pattern,
            transcript = compatible_specifiers_transcript,
            type = PATTERN,
            confidence = MAYBE
          })
        end

        ::done_parsing::
        return variant_argument_specifiers
      end

      if call.type == CALL then  -- a function call
        -- Ignore error S204 (Missing stylistic whitespaces) in Lua code.
        for _, arguments_number in ipairs(lpeg.match(parsers.expl3_function_call_with_lua_code_argument_csname, call.csname)) do
          local lua_code_argument = call.arguments[arguments_number]
          if #lua_code_argument.token_range > 0 then
            local lua_code_byte_range = lua_code_argument.token_range:new_range_from_subranges(get_token_byte_range(tokens), #content)
            issues:ignore('s204', lua_code_byte_range)
          end
        end

        local function_variant_definition = lpeg.match(parsers.expl3_function_variant_definition_csname, call.csname)
        local function_definition = lpeg.match(parsers.expl3_function_definition_csname, call.csname)

        local variable_declaration = lpeg.match(parsers.expl3_variable_declaration, call.csname)
        local variable_definition = lpeg.match(parsers.expl3_variable_definition, call.csname)
        local variable_use = lpeg.match(parsers.expl3_variable_use, call.csname)

        -- Process a function variant definition.
        if function_variant_definition ~= nil then
          local is_conditional = table.unpack(function_variant_definition)
          -- determine the name of the defined function
          local base_csname_argument = call.arguments[1]
          local base_csname = extract_csname_from_argument(base_csname_argument)
          if base_csname == nil then  -- we couldn't extract the csname, give up
            goto other_statement
          end
          local base_csname_stem, base_argument_specifiers = parse_expl3_csname(base_csname)
          if base_csname_stem == nil then  -- we couldn't parse the csname, give up
            goto other_statement
          end
          -- determine the variant argument specifiers
          local variant_argument_specifiers = parse_variant_argument_specifiers(base_csname, call.arguments[2])
          if variant_argument_specifiers == nil then  -- we couldn't parse the variant argument specifiers, give up
            goto other_statement
          end
          -- determine all defined csnames
          local defined_csnames = {}
          for _, argument_specifiers in ipairs(variant_argument_specifiers) do
            if is_conditional then  -- conditional function
              -- determine the conditions
              local conditions = parse_conditions(call.arguments[#call.arguments])
              if conditions == nil then  -- we couldn't determine the conditions, give up
                goto other_statement
              end
              -- determine the defined csnames
              for _, condition_table in ipairs(conditions) do
                local condition, condition_confidence = table.unpack(condition_table)
                local base_conditional_csname = get_conditional_function_csname(base_csname_stem, base_argument_specifiers, condition)
                local defined_conditional_csname = get_conditional_function_csname(base_csname_stem, argument_specifiers, condition)
                local confidence = math.min(argument_specifiers.confidence, condition_confidence)
                if base_conditional_csname ~= defined_conditional_csname then
                  table.insert(defined_csnames, {base_conditional_csname, defined_conditional_csname, confidence})
                end
              end
            else  -- non-conditional function
              local defined_csname = replace_argument_specifiers(base_csname_stem, argument_specifiers)
              if base_csname ~= defined_csname then
                table.insert(defined_csnames, {base_csname, defined_csname, argument_specifiers.confidence})
              end
            end
          end
          -- record function variant definition statements for all effectively defined csnames
          for _, defined_csname_table in ipairs(defined_csnames) do  -- lua
            local effective_base_csname, defined_csname, confidence = table.unpack(defined_csname_table)
            local statement = {
              type = FUNCTION_VARIANT_DEFINITION,
              call_range = call_range,
              confidence = confidence,
              -- The following attributes are specific to the type.
              base_csname = effective_base_csname,
              defined_csname = defined_csname,
              is_private = is_function_private(base_csname),
              is_conditional = is_conditional,
            }
            table.insert(statements, statement)
          end
          goto continue
        end

        -- Process a function definition.
        if function_definition ~= nil then
          local is_direct = table.unpack(function_definition)
          -- Process a direct function definition.
          if is_direct then
            -- determine the properties of the defined function
            local defined_csname_argument = call.arguments[1]
            local _, _, is_creator_function = table.unpack(function_definition)
            local is_conditional, maybe_redefinition, is_global, is_protected, is_nopar
            local num_parameters
            if is_creator_function == true then  -- direct application of a creator function
              _, is_conditional, _, maybe_redefinition, is_global, is_protected, is_nopar = table.unpack(function_definition)
            else  -- indirect application of a creator function
              local num_parameter_argument = call.arguments[3]
              if num_parameter_argument ~= nil and num_parameter_argument.specifier == "n" then
                local num_parameters_text = extract_text_from_argument(num_parameter_argument)
                if num_parameters_text ~= nil then
                  num_parameters = tonumber(num_parameters_text)
                end
              end
              local creator_function_csname = extract_csname_from_argument(call.arguments[2])
              if (  -- couldn't determine the name of the creator function, give up
                    creator_function_csname == nil
                    or creator_function_csname.type ~= TEXT
                  ) then
                goto other_statement
              end
              local actual_function_definition = lpeg.match(parsers.expl3_function_definition_csname, creator_function_csname.payload)
              if actual_function_definition == nil then  -- couldn't understand the creator function, give up
                goto other_statement
              end
              _, is_conditional, _, maybe_redefinition, is_global, is_protected, is_nopar = table.unpack(actual_function_definition)
            end
            -- determine the name of the defined function
            local defined_csname = extract_csname_from_argument(defined_csname_argument)
            if defined_csname == nil then  -- we couldn't extract the csname, give up
              goto other_statement
            end
            local defined_csname_stem, argument_specifiers = parse_expl3_csname(defined_csname)
            -- determine the replacement text
            local replacement_text_number
            local replacement_text_argument = call.arguments[#call.arguments]
            do
              if replacement_text_argument.specifier ~= "n" then  -- replacement text is hidden behind expansion
                goto skip_replacement_text  -- record partial information
              end
              -- determine the number of parameters of the defined function
              local function update_num_parameters(updated_num_parameters)
                assert(updated_num_parameters ~= nil)
                if num_parameters == nil or updated_num_parameters > num_parameters then  -- trust the highest guess
                  num_parameters = updated_num_parameters
                end
              end
              if (
                    argument_specifiers ~= nil
                    and argument_specifiers.type == TEXT
                    and lpeg.match(parsers.N_or_n_type_argument_specifiers, argument_specifiers.payload) ~= nil
                  ) then
                update_num_parameters(#argument_specifiers.payload)
              end
              for _, argument in ipairs(call.arguments) do  -- next, try to look for p-type "TeX parameter" argument specifiers
                if argument.specifier == "p" and argument.num_parameters ~= nil then
                  update_num_parameters(argument.num_parameters)
                  break
                end
              end
              if num_parameters == nil then  -- we couldn't determine the number of parameters
                goto skip_replacement_text  -- record partial information
              end
              -- parse the replacement text and record the function definition
              local mapped_replacement_text_token_range = new_range(
                first_map_forward(replacement_text_argument.token_range:start()),
                first_map_forward(replacement_text_argument.token_range:stop()),
                INCLUSIVE + MAYBE_EMPTY,
                #transformed_tokens
              )
              local doubly_transformed_tokens, second_map_back, second_map_forward = transform_replacement_text_tokens(
                content,
                transformed_tokens,
                issues,
                num_parameters,
                mapped_replacement_text_token_range
              )
              if doubly_transformed_tokens == nil then  -- we couldn't parse the replacement text
                goto skip_replacement_text  -- record partial information
              end
              local function map_back(...) return first_map_back(second_map_back(...)) end
              local function map_forward(...) return second_map_forward(first_map_forward(...)) end
              table.insert(replacement_text_tokens, {
                token_range = replacement_text_argument.token_range,
                transformed_tokens = doubly_transformed_tokens,
                map_back = map_back,
                map_forward = map_forward,
              })
              replacement_text_number = #replacement_text_tokens
            end
            ::skip_replacement_text::
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
                if defined_csname_stem == nil or argument_specifiers == nil then  -- we couldn't parse the csname, give up
                  goto other_statement
                end
                local effectively_defined_csname = get_conditional_function_csname(defined_csname_stem, argument_specifiers, condition)
                if condition == "p" and is_protected then
                  issues:add("e404", "protected predicate function", byte_range, format_csname(effectively_defined_csname))
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
                call_range = call_range,
                confidence = confidence,
                -- The following attributes are specific to the type.
                subtype = FUNCTION_DEFINITION_DIRECT,
                maybe_redefinition = maybe_redefinition,
                is_private = is_function_private(defined_csname),
                is_global = is_global,
                defined_csname = effectively_defined_csname,
                -- The following attributes are specific to the subtype.
                is_conditional = is_conditional,
                is_protected = is_protected,
                is_nopar = is_nopar,
                replacement_text_number = replacement_text_number,
                replacement_text_argument = replacement_text_argument,
              }
              table.insert(statements, statement)
            end
          else
            -- Process an indirect function definition.
            local _, is_conditional, maybe_redefinition, is_global = table.unpack(function_definition)
            -- determine the name of the defined function
            local defined_csname_argument = call.arguments[1]
            local defined_csname = extract_csname_from_argument(defined_csname_argument)
            if defined_csname == nil then  -- we couldn't extract the csname, give up
              goto other_statement
            end
            -- determine the name of the base function
            local base_csname_argument = call.arguments[2]
            local base_csname = extract_csname_from_argument(base_csname_argument)
            if base_csname == nil then  -- we couldn't extract the csname, give up
              goto other_statement
            end
            -- determine all effectively defined csnames and effective base csnames
            local effective_defined_and_base_csnames = {}
            if is_conditional then  -- conditional function
              -- parse the base and defined csnames
              local defined_csname_stem, defined_argument_specifiers = parse_expl3_csname(defined_csname)
              if defined_csname_stem == nil then  -- we couldn't parse the defined csname, give up
                goto other_statement
              end
              local base_csname_stem, base_argument_specifiers = parse_expl3_csname(base_csname)
              if base_csname_stem == nil then  -- we couldn't parse the base csname, give up
                goto other_statement
              end
              -- determine the conditions
              local conditions = parse_conditions(call.arguments[#call.arguments - 1])
              if conditions == nil then  -- we couldn't determine the conditions, give up
                goto other_statement
              end
              -- determine the defined and base csnames
              for _, condition_table in ipairs(conditions) do
                local condition, confidence = table.unpack(condition_table)
                local effectively_defined_csname
                  = get_conditional_function_csname(defined_csname_stem, defined_argument_specifiers, condition)
                local effective_base_csname
                  = get_conditional_function_csname(base_csname_stem, base_argument_specifiers, condition)
                table.insert(effective_defined_and_base_csnames, {effectively_defined_csname, effective_base_csname, confidence})
              end
            else  -- non-conditional function
              effective_defined_and_base_csnames = {{defined_csname, base_csname, DEFINITELY}}
            end
            -- record function definition statements for all effectively defined csnames
            for _, effective_defined_and_base_csname_table in ipairs(effective_defined_and_base_csnames) do  -- lua
              local effectively_defined_csname, effective_base_csname, confidence
                = table.unpack(effective_defined_and_base_csname_table)
              local statement = {
                type = FUNCTION_DEFINITION,
                call_range = call_range,
                confidence = confidence,
                -- The following attributes are specific to the type.
                subtype = FUNCTION_DEFINITION_INDIRECT,
                maybe_redefinition = maybe_redefinition,
                is_private = is_function_private(defined_csname),
                is_global = is_global,
                defined_csname = effectively_defined_csname,
                -- The following attributes are specific to the subtype.
                base_csname = effective_base_csname,
                is_conditional = is_conditional,
              }
              table.insert(statements, statement)
            end
          end
          goto continue
        end

        -- Process a variable declaration.
        if variable_declaration ~= nil then
          local variable_type = table.unpack(variable_declaration)
          -- determine the name of the declared variable
          local declared_csname_argument = call.arguments[1]
          local declared_csname = extract_csname_from_argument(declared_csname_argument)
          if declared_csname == nil then  -- we couldn't extract the csname, give up
            goto other_statement
          end
          if (
                declared_csname.type == TEXT
                and lpeg.match(parsers.expl3_expansion_csname, declared_csname.payload) ~= nil  -- there appear to be expansion, give up
              ) then
            goto other_statement
          end
          local confidence = declared_csname.type == TEXT and DEFINITELY or MAYBE
          local statement = {
            type = VARIABLE_DECLARATION,
            call_range = call_range,
            confidence = confidence,
            -- The following attributes are specific to the type.
            declared_csname = declared_csname,
            variable_type = variable_type,
          }
          table.insert(statements, statement)
          goto continue
        end

        -- Process a variable or constant definition.
        if variable_definition ~= nil then
          local variable_type, is_constant, is_global, is_direct = table.unpack(variable_definition)
          -- determine the name of the declared variable
          local defined_csname_argument = call.arguments[1]
          local defined_csname = extract_csname_from_argument(defined_csname_argument)
          if defined_csname == nil then  -- we couldn't extract the csname, give up
            goto other_statement
          end
          if (
                defined_csname.type == TEXT
                and lpeg.match(parsers.expl3_expansion_csname, defined_csname.payload) ~= nil  -- there appear to be expansion, give up
              ) then
            goto other_statement
          end
          -- detect mutability mismatches
          local defined_csname_scope = lpeg.match(parsers.expl3_variable_or_constant_csname_scope, defined_csname.transcript)
          if defined_csname_scope ~= nil then
            if is_constant and (defined_csname_scope == "g" or defined_csname_scope == "l") then
              issues:add('e417', 'setting a variable as a constant', byte_range, format_csname(defined_csname.transcript))
            end
            if not is_constant and defined_csname_scope == "c" then
              issues:add('e418', 'setting a constant', byte_range, format_csname(defined_csname.transcript))
            end
            if not is_global and defined_csname_scope == "g" then
              issues:add('e420', 'locally setting a global variable', byte_range, format_csname(defined_csname.transcript))
            end
            if is_global and defined_csname_scope == "l" then
              issues:add('e421', 'globally setting a local variable', byte_range, format_csname(defined_csname.transcript))
            end
          end
          local confidence = defined_csname.type == TEXT and DEFINITELY or MAYBE
          local statement
          if is_direct then
            -- determine the definition text
            local definition_text_argument = call.arguments[2]
            if definition_text_argument == nil then  -- we couldn't extract the definition text, give up
              goto other_statement
            end
            statement = {
              type = VARIABLE_DEFINITION,
              call_range = call_range,
              confidence = confidence,
              -- The following attributes are specific to the type.
              subtype = VARIABLE_DEFINITION_DIRECT,
              variable_type = variable_type,
              is_constant = is_constant,
              is_global = is_global,
              defined_csname = defined_csname,
              -- The following attributes are specific to the subtype.
              definition_text_argument = definition_text_argument,
            }
          else
            local base_variable_type = variable_definition[5] or variable_type
            -- determine the name of the base variable or constant
            local base_csname_argument = call.arguments[2]
            local base_csname = extract_csname_from_argument(base_csname_argument)
            if base_csname == nil then  -- we couldn't extract the csname, give up
              goto other_statement
            end
            statement = {
              type = VARIABLE_DEFINITION,
              call_range = call_range,
              confidence = confidence,
              -- The following attributes are specific to the type.
              subtype = VARIABLE_DEFINITION_INDIRECT,
              variable_type = variable_type,
              is_constant = is_constant,
              is_global = is_global,
              defined_csname = defined_csname,
              -- The following attributes are specific to the subtype.
              base_csname = base_csname,
              base_variable_type = base_variable_type,
            }
          end
          table.insert(statements, statement)
          goto continue
        end

        -- Process a variable declaration.
        if variable_use ~= nil then
          local variable_type = table.unpack(variable_use)
          -- determine the name of the used variable
          local used_csname_argument = call.arguments[1]
          local used_csname = extract_csname_from_argument(used_csname_argument)
          if used_csname == nil then  -- we couldn't extract the csname, give up
            goto other_statement
          end
          if (
                used_csname.type == TEXT
                and lpeg.match(parsers.expl3_expansion_csname, used_csname.payload) ~= nil  -- there appear to be expansion, give up
              ) then
            goto other_statement
          end
          local confidence = used_csname.type == TEXT and DEFINITELY or MAYBE
          local statement = {
            type = VARIABLE_USE,
            call_range = call_range,
            confidence = confidence,
            -- The following attributes are specific to the type.
            used_csname = used_csname,
            variable_type = variable_type,
          }
          table.insert(statements, statement)
          goto continue
        end

        ::other_statement::
        local statement = {
          type = OTHER_STATEMENT,
          call_range = call_range,
          confidence = NONE,
        }
        table.insert(statements, statement)
      elseif call.type == OTHER_TOKENS then  -- other tokens
        local statement_type = classify_tokens(tokens, call.token_range)
        local statement = {
          type = statement_type,
          call_range = call_range,
          confidence = NONE,
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
          groupings,
          content
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
          if nested_statement.type == FUNCTION_DEFINITION
              and nested_statement.subtype == FUNCTION_DEFINITION_DIRECT
              and nested_statement.replacement_text_number ~= nil then
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

  --- Make a pass over the segments, building up information.

  ---- Collect information about symbols that were definitely defined.
  local defined_private_function_texts = {}
  local called_functions_and_variants = {}
  local defined_csname_texts = {}
  local defined_private_function_variant_texts = {}
  local defined_private_function_variant_byte_ranges, defined_private_function_variant_csnames = {}, {}
  local variant_base_csname_texts, indirect_definition_base_csname_texts = {}, {}

  local declared_defined_and_used_variable_csname_texts = {}
  local declared_variable_csname_texts = {}
  local defined_variable_csname_texts = {}
  local used_variable_csname_texts = {}

  ---- Collect information about symbols that may have been defined.
  local maybe_defined_private_function_variant_pattern = parsers.fail
  local maybe_defined_csname_texts, maybe_defined_csname_pattern = {}, parsers.fail
  local maybe_used_csname_texts, maybe_used_csname_pattern = {}, parsers.fail

  local maybe_declared_variable_csname_texts, maybe_declared_variable_csname_transcripts = {}, {}
  local maybe_declared_variable_csname_pattern, maybe_defined_variable_csname_pattern = parsers.fail, parsers.fail
  local maybe_used_variable_csname_transcripts = {}
  local maybe_defined_variable_csname_transcripts, maybe_defined_variable_base_csname_transcripts = {}, {}
  local maybe_used_variable_csname_texts = {}
  local maybe_used_variable_csname_pattern = parsers.fail

  for segment_number, segment_statements in ipairs(statement_segments) do
    local segment_calls = call_segments[segment_number]
    local segment_tokens, segment_transformed_tokens, map_forward = table.unpack(token_segments[segment_number])

    -- Try and convert tokens from a range into a csname.
    local function extract_csname_from_tokens(token_range)
      return _extract_csname_from_tokens(token_range, segment_transformed_tokens, map_forward)
    end

    -- Process an argument and record control sequence name usage and definitions.
    local function process_argument_tokens(argument)
      -- Record control sequence name usage.
      --- Extract text from tokens within c- and v-type arguments.
      if argument.specifier == "c" or argument.specifier == "v" then
        local csname = extract_csname_from_tokens(argument.token_range)
        if csname ~= nil then
          if csname.type == TEXT then
            maybe_used_csname_texts[csname.payload] = true
          elseif csname.type == PATTERN then
            maybe_used_csname_pattern = (
              maybe_used_csname_pattern
              + #(csname.payload * parsers.eof)
              * csname.payload
            )
          else
            error('Unexpected csname type "' .. csname.type .. '"')
          end
        end
      end
      --- Scan control sequence tokens within N- and n-type arguments.
      if lpeg.match(parsers.N_or_n_type_argument_specifier, argument.specifier) ~= nil then
        for _, token in argument.token_range:enumerate(segment_transformed_tokens, map_forward) do
          if token.type == CONTROL_SEQUENCE then
            maybe_used_csname_texts[token.payload] = true
          end
        end
      end
      -- Record control sequence name definitions.
      --- Scan control sequence tokens within N- and n-type arguments.
      if lpeg.match(parsers.N_or_n_type_argument_specifier, argument.specifier) ~= nil then
        for token_number, token in argument.token_range:enumerate(segment_transformed_tokens, map_forward) do
          if token.type == CONTROL_SEQUENCE then
            if token_number + 1 <= #segment_transformed_tokens then
              local next_token = segment_transformed_tokens[token_number + 1]
              if (
                    next_token.type == CONTROL_SEQUENCE
                    and lpeg.match(parsers.expl3_function_definition_csname, token.payload) ~= nil
                  ) then
                maybe_defined_csname_texts[next_token.payload] = true
              end
            end
          end
        end
      end
    end

    for _, statement in ipairs(segment_statements) do
      local token_range = statement.call_range:new_range_from_subranges(get_call_token_range(segment_calls), #segment_tokens)
      local byte_range = token_range:new_range_from_subranges(get_token_byte_range(segment_tokens), #content)
      -- Process a function variant definition.
      if statement.type == FUNCTION_VARIANT_DEFINITION then
        -- Record base control sequence names of variants, both as control sequence name usage and separately.
        if statement.base_csname.type == TEXT then
          table.insert(variant_base_csname_texts, {statement.base_csname.payload, byte_range})
          maybe_used_csname_texts[statement.base_csname.payload] = true
        elseif statement.base_csname.type == PATTERN then
          maybe_used_csname_pattern = (
            maybe_used_csname_pattern
            + #(statement.base_csname.payload * parsers.eof)
            * statement.base_csname.payload
          )
        else
          error('Unexpected csname type "' .. statement.base_csname.type .. '"')
        end
        -- Record control sequence name definitions.
        if statement.defined_csname.type == TEXT then
          table.insert(defined_csname_texts, {statement.defined_csname.payload, byte_range})
          maybe_defined_csname_texts[statement.defined_csname.payload] = true
        elseif statement.defined_csname.type == PATTERN then
          maybe_defined_csname_pattern = (
            maybe_defined_csname_pattern
            + #(statement.defined_csname.payload * parsers.eof)
            * statement.defined_csname.payload
          )
        else
          error('Unexpected csname type "' .. statement.defined_csname.type .. '"')
        end
        -- Record private function variant definitions.
        if statement.defined_csname.type == TEXT and statement.is_private then
          table.insert(defined_private_function_variant_byte_ranges, byte_range)
          table.insert(defined_private_function_variant_csnames, statement.defined_csname)
          local private_function_variant_number = #defined_private_function_variant_byte_ranges
          table.insert(defined_private_function_variant_texts, private_function_variant_number)
        end
      -- Process a function definition.
      elseif statement.type == FUNCTION_DEFINITION then
        -- Record the base control sequences used in indirect function definitions.
        if statement.subtype == FUNCTION_DEFINITION_INDIRECT then
          if statement.base_csname.type == TEXT then
            maybe_used_csname_texts[statement.base_csname.payload] = true
            table.insert(indirect_definition_base_csname_texts, {statement.base_csname.payload, byte_range})
          elseif statement.base_csname.type == PATTERN then
            maybe_used_csname_pattern = (
              maybe_used_csname_pattern
              + #(statement.base_csname.payload * parsers.eof)
              * statement.base_csname.payload
            )
          else
            error('Unexpected csname type "' .. statement.base_csname.type .. '"')
          end
        end
        -- Record control sequence name usage and definitions.
        if statement.defined_csname.type == TEXT then
          maybe_defined_csname_texts[statement.defined_csname.payload] = true
          table.insert(defined_csname_texts, {statement.defined_csname.payload, byte_range})
        end
        if statement.subtype == FUNCTION_DEFINITION_DIRECT and statement.replacement_text_number == nil then
          process_argument_tokens(statement.replacement_text_argument)
        end
        -- Record private function defition.
        if statement.defined_csname.type == TEXT and statement.is_private then
          table.insert(defined_private_function_texts, {statement.defined_csname.payload, byte_range})
        end
      -- Process a variable declaration.
      elseif statement.type == VARIABLE_DECLARATION then
        -- Record variable names.
        table.insert(
          maybe_declared_variable_csname_transcripts,
          {statement.variable_type, statement.declared_csname.transcript, byte_range}
        )
        if statement.declared_csname.type == TEXT then
          table.insert(
            declared_defined_and_used_variable_csname_texts,
            {statement.variable_type, statement.declared_csname.payload, byte_range}
          )
          table.insert(declared_variable_csname_texts, {statement.declared_csname.payload, byte_range})
          maybe_declared_variable_csname_texts[statement.declared_csname.payload] = true
        elseif statement.declared_csname.type == PATTERN then
          maybe_declared_variable_csname_pattern = (
            maybe_declared_variable_csname_pattern
            + #(statement.declared_csname.payload * parsers.eof)
            * statement.declared_csname.payload
          )
        else
          error('Unexpected csname type "' .. statement.base_csname.type .. '"')
        end
      -- Process a variable or constant definition.
      elseif statement.type == VARIABLE_DEFINITION then
        -- Record variable names.
        if statement.is_constant then
          table.insert(
            maybe_declared_variable_csname_transcripts,
            {statement.variable_type, statement.defined_csname.transcript, byte_range}
          )
        else
          table.insert(
            maybe_defined_variable_csname_transcripts,
            {statement.variable_type, statement.defined_csname.transcript, byte_range}
          )
          if statement.subtype == VARIABLE_DEFINITION_INDIRECT then
            table.insert(
              maybe_defined_variable_base_csname_transcripts,
              {statement.base_variable_type, statement.base_csname.transcript, byte_range}
            )
          end
        end
        if statement.defined_csname.type == TEXT then
          table.insert(
            declared_defined_and_used_variable_csname_texts,
            {statement.variable_type, statement.defined_csname.payload, byte_range})
          table.insert(
            defined_variable_csname_texts,
            {statement.defined_csname.payload, byte_range}
          )
          if statement.is_constant then
            maybe_declared_variable_csname_texts[statement.defined_csname.payload] = true
            table.insert(
              declared_variable_csname_texts,
              {statement.defined_csname.payload, byte_range}
            )
          end
        elseif statement.declared_csname.type == PATTERN then
          maybe_defined_variable_csname_pattern = (
            maybe_defined_variable_csname_pattern
            + #(statement.declared_csname.payload * parsers.eof)
            * statement.declared_csname.payload
          )
        else
          error('Unexpected csname type "' .. statement.base_csname.type .. '"')
        end
        -- Record control sequence name usage and definitions.
        if statement.subtype == VARIABLE_DEFINITION_DIRECT then
          process_argument_tokens(statement.definition_text_argument)
        end
      -- Process a variable or constant use.
      elseif statement.type == VARIABLE_USE then
        -- Record variable names.
        table.insert(
          maybe_used_variable_csname_transcripts,
          {statement.variable_type, statement.used_csname.transcript, byte_range}
        )
        if statement.used_csname.type == TEXT then
          table.insert(
            declared_defined_and_used_variable_csname_texts,
            {statement.variable_type, statement.used_csname.payload, byte_range}
          )
          table.insert(used_variable_csname_texts, {statement.used_csname.payload, byte_range})
          maybe_used_variable_csname_texts[statement.used_csname.payload] = true
        elseif statement.used_csname.type == PATTERN then
          maybe_used_variable_csname_pattern = (
            maybe_used_variable_csname_pattern
            + #(statement.used_csname.payload * parsers.eof)
            * statement.used_csname.payload
          )
        else
          error('Unexpected csname type "' .. statement.defined_csname.type .. '"')
        end
      -- Process an unrecognized statement.
      elseif statement.type == OTHER_STATEMENT then
        -- Record control sequence name usage and definitions.
        for _, call in statement.call_range:enumerate(segment_calls) do
          maybe_used_csname_texts[call.csname] = true
          table.insert(called_functions_and_variants, {call.csname, byte_range})
          for _, argument in ipairs(call.arguments) do
            process_argument_tokens(argument)
          end
        end
      -- Process a block of unrecognized tokens.
      elseif statement.type == OTHER_TOKENS_SIMPLE or statement.type == OTHER_TOKENS_COMPLEX then
        -- Record control sequence name usage by scanning all control sequence tokens.
        for _, token in token_range:enumerate(segment_transformed_tokens, map_forward) do
          if token.type == CONTROL_SEQUENCE then
            maybe_used_csname_texts[token.payload] = true
          end
        end
      else
        error('Unexpected statement type "' .. statement.type .. '"')
      end
    end
  end

  --- Report issues apparent from the collected information.
  local imported_prefixes = get_option('imported_prefixes', options, pathname)
  local expl3_well_known_csname = parsers.expl3_well_known_csname(imported_prefixes)

  ---- Report unused private functions.
  for _, defined_private_function_text in ipairs(defined_private_function_texts) do
    local defined_csname, byte_range = table.unpack(defined_private_function_text)
    if lpeg.match(expl3_well_known_csname, defined_csname) == nil
        and not maybe_used_csname_texts[defined_csname]
        and lpeg.match(maybe_used_csname_pattern, defined_csname) == nil then
      issues:add('w401', 'unused private function', byte_range, format_csname(defined_csname))
    end
  end

  ---- Report unused private function variants.
  local used_private_function_variants = {}
  for private_function_variant_number, _ in ipairs(defined_private_function_variant_byte_ranges) do
    used_private_function_variants[private_function_variant_number] = false
  end
  for _, private_function_variant_number in ipairs(defined_private_function_variant_texts) do
    local csname = defined_private_function_variant_csnames[private_function_variant_number]
    assert(csname.type == TEXT)
    if maybe_used_csname_texts[csname.payload] or lpeg.match(maybe_used_csname_pattern, csname.payload) ~= nil then
      used_private_function_variants[private_function_variant_number] = true
    end
  end
  for maybe_used_csname, _ in pairs(maybe_used_csname_texts) do
    -- NOTE: Although we might want to also test whether "maybe_defined_private_function_variant_pattern" and
    -- "maybe_used_csname_pattern" overlap, intersection is undecideable for parsing expression languages (PELs). In
    -- theory, we could use regular expressions instead of PEG patterns, since intersection is decideable for regular
    -- languages. In practice, there are no Lua libraries that would implement the required algorithms. Therefore, it
    -- seems more practical to just accept that low-confidence function variant definitions and function uses don't
    -- interact, not just because the technical difficulty but also because the combined confidence is just too low.
    local private_function_variant_number = lpeg.match(maybe_defined_private_function_variant_pattern, maybe_used_csname)
    if private_function_variant_number ~= nil then
      local csname = defined_private_function_variant_csnames[private_function_variant_number]
      assert(csname.type == PATTERN)
      used_private_function_variants[private_function_variant_number] = true
    end
  end
  for private_function_variant_number, byte_range in ipairs(defined_private_function_variant_byte_ranges) do
    local csname = defined_private_function_variant_csnames[private_function_variant_number]
    assert(csname.type == TEXT or csname.type == PATTERN)
    if not used_private_function_variants[private_function_variant_number] then
      issues:add('w402', 'unused private function variant', byte_range, format_csname(csname.transcript))
    end
  end

  ---- Report function variants for undefined functions.
  for _, variant_base_csname_text in ipairs(variant_base_csname_texts) do
    local base_csname, byte_range = table.unpack(variant_base_csname_text)
    if lpeg.match(expl3_well_known_csname, base_csname) == nil
        and not maybe_defined_csname_texts[base_csname]
        and lpeg.match(maybe_defined_csname_pattern, base_csname) == nil then
      issues:add('e405', 'function variant for an undefined function', byte_range, format_csname(base_csname))
    end
  end

  ---- Report calls to undefined functions and function variants.
  for _, called_function_or_variant in ipairs(called_functions_and_variants) do
    local csname, byte_range = table.unpack(called_function_or_variant)
    if lpeg.match(parsers.expl3like_function_csname, csname) ~= nil
        and lpeg.match(expl3_well_known_csname, csname) == nil
        and not maybe_defined_csname_texts[csname]
        and lpeg.match(maybe_defined_csname_pattern, csname) == nil then
      issues:add('e408', 'calling an undefined function', byte_range, format_csname(csname))
    end
  end

  ---- Report indirect function definitions from undefined base functions.
  for _, indirect_definition_base_csname_text in ipairs(indirect_definition_base_csname_texts) do
    local csname, byte_range = table.unpack(indirect_definition_base_csname_text)
    if lpeg.match(parsers.expl3like_function_csname, csname) ~= nil
        and lpeg.match(expl3_well_known_csname, csname) == nil
        and not maybe_defined_csname_texts[csname]
        and lpeg.match(maybe_defined_csname_pattern, csname) == nil then
      issues:add('e411', 'indirect function definition from an undefined function', byte_range, format_csname(csname))
    end
  end

  ---- Report malformed function names.
  for _, defined_csname_text in ipairs(defined_csname_texts) do
    local defined_csname, byte_range = table.unpack(defined_csname_text)
    if (
          lpeg.match(parsers.expl3like_csname, defined_csname) ~= nil
          and lpeg.match(expl3_well_known_csname, defined_csname) == nil
          and lpeg.match(parsers.expl3_function_csname, defined_csname) == nil
        ) then
      issues:add('s412', 'malformed function name', byte_range, format_csname(defined_csname))
    end
  end

  ---- Report malformed variable and constant names.
  for _, declared_defined_and_used_variable_csname_text in ipairs(declared_defined_and_used_variable_csname_texts) do
    local variable_type, variable_csname, byte_range = table.unpack(declared_defined_and_used_variable_csname_text)
    if variable_type == "quark" or variable_type == "scan" then
      if lpeg.match(parsers.expl3_quark_or_scan_mark_csname, variable_csname) == nil then
        issues:add('s414', 'malformed quark or scan mark name', byte_range, format_csname(variable_csname))
      end
    else
      if (
            lpeg.match(parsers.expl3like_csname, variable_csname) ~= nil
            and lpeg.match(parsers.expl3_scratch_variable_csname, variable_csname) == nil
            and lpeg.match(parsers.expl3_variable_or_constant_csname, variable_csname) == nil
          ) then
        issues:add('s413', 'malformed variable or constant', byte_range, format_csname(variable_csname))
      end
    end
  end

  ---- Report unused variables and constants.
  for _, declared_variable_csname_text in ipairs(declared_variable_csname_texts) do
    local variable_csname, byte_range = table.unpack(declared_variable_csname_text)
    if (
          lpeg.match(parsers.expl3like_csname, variable_csname) ~= nil
          and not maybe_used_variable_csname_texts[variable_csname]
          and lpeg.match(maybe_used_variable_csname_pattern, variable_csname) == nil
          and not maybe_used_csname_texts[variable_csname]
          and lpeg.match(maybe_used_csname_pattern, variable_csname) == nil
        ) then
      issues:add('w415', 'unused variable or constant', byte_range, format_csname(variable_csname))
    end
  end

  ---- Report undeclared variables.
  for _, defined_variable_csname_text in ipairs(defined_variable_csname_texts) do
    local variable_csname, byte_range = table.unpack(defined_variable_csname_text)
    if (
          lpeg.match(parsers.expl3like_csname, variable_csname) ~= nil
          and lpeg.match(expl3_well_known_csname, variable_csname) == nil
          and lpeg.match(parsers.expl3_scratch_variable_csname, variable_csname) == nil
          and not maybe_declared_variable_csname_texts[variable_csname]
          and lpeg.match(maybe_declared_variable_csname_pattern, variable_csname) == nil
        ) then
      issues:add('w416', 'setting an undeclared variable', byte_range, format_csname(variable_csname))
    end
  end

  ---- Report using undefined variables or constants.
  for _, used_variable_csname_text in ipairs(used_variable_csname_texts) do
    local variable_csname, byte_range = table.unpack(used_variable_csname_text)
    if (
          lpeg.match(parsers.expl3like_csname, variable_csname) ~= nil
          and lpeg.match(expl3_well_known_csname, variable_csname) == nil
          and lpeg.match(parsers.expl3_scratch_variable_csname, variable_csname) == nil
          and not maybe_declared_variable_csname_texts[variable_csname]
          and lpeg.match(maybe_declared_variable_csname_pattern, variable_csname) == nil
        ) then
      issues:add('w419', 'using an undeclared variable or constant', byte_range, format_csname(variable_csname))
    end
  end

  ---- Report using variables and constants of incompatible types.
  for _, maybe_declared_variable_csname_transcript in ipairs(maybe_declared_variable_csname_transcripts) do
    local declaration_type, csname_transcript, byte_range = table.unpack(maybe_declared_variable_csname_transcript)
    local csname_type = lpeg.match(parsers.expl3_variable_or_constant_csname_type, csname_transcript)
    if csname_type ~= nil then
      -- For declarations, we require that the the declaration type <= the variable type.
      -- For example, `\str_new:N \g_example_tl` is OK but `\tl_new:N \g_example_str` is not.
      local subtype, supertype = declaration_type, csname_type
      if not is_subtype(subtype, supertype) then
        local context = string.format("!(%s <= %s)", subtype, supertype)
        issues:add('t422', 'using a variable of an incompatible type', byte_range, context)
      end
    end
  end
  for _, maybe_defined_variable_csname_transcript in ipairs(maybe_defined_variable_csname_transcripts) do
    local definition_type, csname_transcript, byte_range = table.unpack(maybe_defined_variable_csname_transcript)
    local csname_type = lpeg.match(parsers.expl3_variable_or_constant_csname_type, csname_transcript)
    if csname_type ~= nil then
      -- For definitions, we require that the definition type <= the defined variable type.
      -- For example, `\clist_gset:Nn \g_example_tl ...` is OK but `\tl_gset:Nn \g_example_clist ...` is not.
      local subtype, supertype = definition_type, csname_type
      if not is_subtype(subtype, supertype) then
        local context = string.format("!(%s <= %s)", subtype, supertype)
        issues:add('t422', 'using a variable of an incompatible type', byte_range, context)
      end
    end
  end
  for _, maybe_defined_variable_base_csname_transcript in ipairs(maybe_defined_variable_base_csname_transcripts) do
    local definition_type, csname_transcript, byte_range = table.unpack(maybe_defined_variable_base_csname_transcript)
    local csname_type = lpeg.match(parsers.expl3_variable_or_constant_csname_type, csname_transcript)
    if csname_type ~= nil then
      -- Additionally, for indirect definitions, we also require that the base variable type <= the definition type.
      -- For example, `\tl_gset_eq:NN ... \g_example_str` is OK but `\str_gset_eq:NN ... \g_example_tl` is not.
      local subtype, supertype = csname_type, definition_type
      if not is_subtype(subtype, supertype) then
        local context = string.format("!(%s <= %s)", subtype, supertype)
        issues:add('t422', 'using a variable of an incompatible type', byte_range, context)
      end
    end
  end
  for _, maybe_used_variable_csname_transcript in ipairs(maybe_used_variable_csname_transcripts) do
    local use_type, csname_transcript, byte_range = table.unpack(maybe_used_variable_csname_transcript)
    local csname_type = lpeg.match(parsers.expl3_variable_or_constant_csname_type, csname_transcript)
    -- For uses, we require a potential compatibility between the use type and the variable type.
    -- For example, both `\str_count:N \g_example_tl` and `\tl_count:N \g_example_str` are OK.
    if csname_type ~= nil and not is_maybe_compatible_type(use_type, csname_type) then
      local context = string.format("!(%s ~= %s)", use_type, csname_type)
      issues:add('t422', 'using a variable of an incompatible type', byte_range, context)
    end
  end

  -- Store the intermediate results of the analysis.
  results.statements = statements
  results.replacement_texts = replacement_texts
end

return {
  csname_types = csname_types,
  process = semantic_analysis,
  statement_types = statement_types,
  statement_confidences = statement_confidences,
  statement_subtypes = statement_subtypes,
}
