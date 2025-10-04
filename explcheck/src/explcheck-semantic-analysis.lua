-- The semantic analysis step of static analysis determines the meaning of the different function calls.

local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local parsers = require("explcheck-parsers")

local get_token_range_to_byte_range = lexical_analysis.get_token_range_to_byte_range
local is_token_simple = lexical_analysis.is_token_simple
local token_types = lexical_analysis.token_types
local format_csname = lexical_analysis.format_csname

local extract_text_from_tokens = syntactic_analysis.extract_text_from_tokens

local CONTROL_SEQUENCE = token_types.CONTROL_SEQUENCE
local CHARACTER = token_types.CHARACTER

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

local call_types = syntactic_analysis.call_types
local segment_types = syntactic_analysis.segment_types
local get_calls = syntactic_analysis.get_calls
local get_call_range_to_token_range = syntactic_analysis.get_call_range_to_token_range
local transform_replacement_text_tokens = syntactic_analysis.transform_replacement_text_tokens

local CALL = call_types.CALL
local OTHER_TOKENS = call_types.OTHER_TOKENS

local REPLACEMENT_TEXT = segment_types.REPLACEMENT_TEXT

local lpeg = require("lpeg")

local statement_types = {
  FUNCTION_DEFINITION = "function definition",
  FUNCTION_VARIANT_DEFINITION = "function variant definition",
  VARIABLE_DECLARATION = "variable declaration",
  VARIABLE_DEFINITION = "variable or constant definition",
  VARIABLE_USE = "variable or constant use",
  MESSAGE_DEFINITION = "message definition",
  MESSAGE_USE = "message use",
  OTHER_STATEMENT = "other statement",
  OTHER_TOKENS_SIMPLE = "block of other simple tokens",
  OTHER_TOKENS_COMPLEX = "block of other complex tokens",
}

local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION

local VARIABLE_DECLARATION = statement_types.VARIABLE_DECLARATION
local VARIABLE_DEFINITION = statement_types.VARIABLE_DEFINITION
local VARIABLE_USE = statement_types.VARIABLE_USE

local MESSAGE_DEFINITION = statement_types.MESSAGE_DEFINITION
local MESSAGE_USE = statement_types.MESSAGE_USE

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

-- Determine the type of a span of tokens as either "simple text" [1, p. 383] with no expected side effects or
-- a more complex material that may have side effects and presents a boundary between chunks of well-understood
-- expl3 statements.
--
--  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
--
local function classify_tokens(tokens, token_range)
  for _, token in token_range:enumerate(tokens) do
    if not is_token_simple(token) then
      return OTHER_TOKENS_COMPLEX, NONE  -- context material
    end
  end
  return OTHER_TOKENS_SIMPLE, DEFINITELY  -- simple material
end

-- Determine whether the semantic analysis step is too confused by the results
-- of the previous steps to run.
local function is_confused(pathname, results, options)
  local format_percentage = require("explcheck-format").format_percentage
  local evaluation = require("explcheck-evaluation")
  local count_tokens = evaluation.count_tokens
  local num_tokens = count_tokens(results)
  assert(num_tokens ~= nil)
  assert(results.tokens ~= nil and results.segments ~= nil)
  local num_other_complex_tokens = 0
  for _, segment in ipairs(results.segments) do
    assert(segment.calls ~= nil)
    local part_tokens = results.tokens[segment.location.part_number]
    for _, call in ipairs(segment.calls) do
      if call.type == OTHER_TOKENS then
        for _, token in call.token_range:enumerate(part_tokens) do
          if not is_token_simple(token) then
            num_other_complex_tokens = num_other_complex_tokens + 1
          end
        end
      end
    end
  end
  if num_tokens > 0 then
    local other_complex_token_ratio = num_other_complex_tokens / num_tokens
    local min_other_complex_tokens_count = get_option('min_other_complex_tokens_count', options, pathname)
    local min_other_complex_tokens_ratio = get_option('min_other_complex_tokens_ratio', options, pathname)
    if num_other_complex_tokens >= min_other_complex_tokens_count and other_complex_token_ratio >= min_other_complex_tokens_ratio then
      local reason = string.format(
        "too much complex material (%s >= %s) wasn't recognized as calls",
        format_percentage(100.0 * other_complex_token_ratio),
        format_percentage(100.0 * min_other_complex_tokens_ratio)
      )
      return true, reason
    end
  end
  return false
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
local function _extract_name_from_tokens(options, pathname, token_range, transformed_tokens, map_forward)
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

-- Determine the meaning of function calls.
local function analyze(states, file_number, options)

  local state = states[file_number]

  local pathname = state.pathname
  local content = state.content
  local issues = state.issues
  local results = state.results

  -- Extract statements from function calls and record them. For all identified function definitions, also record replacement texts.
  local function get_statements(segment)
    assert(segment.location.file_number == file_number)
    local part_number = segment.location.part_number

    local tokens = results.tokens[part_number]

    local calls = segment.calls

    local transformed_tokens = segment.transformed_tokens.tokens
    local first_map_back = segment.transformed_tokens.map_back
    local first_map_forward = segment.transformed_tokens.map_forward

    local statements = {}
    local token_range_to_byte_range = get_token_range_to_byte_range(tokens, #content)

    -- Extract all parameter tokens that appear within a given range of tokens.
    local function extract_parameter_tokens(token_range)
      local parameters = {}
      if #token_range == 0 then  -- empty token range
        return parameters
      end
      local token_number = first_map_forward(token_range:start())
      local transformed_token_range_end = first_map_forward(token_range:stop())
      while token_number <= transformed_token_range_end do
        local token = transformed_tokens[token_number]
        local next_token_number = token_number + 1
        if token.type == CHARACTER and token.catcode == 6 then  -- parameter
          if next_token_number > transformed_token_range_end then  -- not followed by anything, the replacement text is invalid
            break
          end
          local next_token = transformed_tokens[next_token_number]
          if next_token.type == CHARACTER and next_token.catcode == 6 then  -- followed by another parameter
            next_token_number = next_token_number + 1
          elseif next_token.type == CHARACTER and lpeg.match(parsers.decimal_digit, next_token.payload) then  -- followed by a digit
            local parameter_number = tonumber(next_token.payload)
            assert(parameter_number ~= nil)
            local parameter = {
              token_range = new_range(token_number, next_token_number, INCLUSIVE, #transformed_tokens, first_map_back, #tokens),
              number = parameter_number,
            }
            table.insert(parameters, parameter)
            next_token_number = next_token_number + 1
          end
        end
        token_number = next_token_number
      end
      return parameters
    end

    -- Map a token range from the tokens to the transformed tokens.
    local function transform_token_range(token_range)
      return new_range(
        first_map_forward(token_range:start()),
        first_map_forward(token_range:stop()),
        INCLUSIVE + MAYBE_EMPTY,
        #transformed_tokens
      )
    end

    -- Try and convert tokens from an argument into a text.
    local function extract_text_from_argument(argument)
      assert(lpeg.match(parsers.n_type_argument_specifier, argument.specifier) ~= nil)
      return extract_text_from_tokens(argument.token_range, transformed_tokens, first_map_forward)
    end

    -- Try and convert tokens from a range into a csname.
    local function extract_name_from_tokens(token_range)
      return _extract_name_from_tokens(options, pathname, token_range, transformed_tokens, first_map_forward)
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
        csname = extract_name_from_tokens(argument.token_range)
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

      local specifiers_token_range = argument.outer_token_range or argument.token_range
      local specifiers_byte_range = token_range_to_byte_range(specifiers_token_range)

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
            issues:add("t403", "function variant of incompatible type", specifiers_byte_range, context)
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
              issues:add("w410", "function variant of deprecated type", specifiers_byte_range, context)
            else
              issues:add("t403", "function variant of incompatible type", specifiers_byte_range, context)
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
      variant_argument_specifiers = {}
      do
        local compatible_specifier_pattern, compatible_specifier_transcripts = parsers.success, {}
        local any_other_compatible_specifiers = false
        for i = 1, #base_argument_specifiers do
          local base_argument_specifier = base_argument_specifiers:sub(i, i)
          local compatible_specifiers = table.concat(lpeg.match(parsers.compatible_argument_specifiers, base_argument_specifier))
          if #compatible_specifiers == 0 then  -- no compatible specifiers
            return nil  -- give up
          end
          if compatible_specifiers ~= base_argument_specifier then
            any_other_compatible_specifiers = true
          end
          compatible_specifier_pattern = compatible_specifier_pattern * lpeg.S(compatible_specifiers)
          local compatible_specifier_transcript = string.format('[%s]', compatible_specifiers)
          table.insert(compatible_specifier_transcripts, compatible_specifier_transcript)
        end
        if not any_other_compatible_specifiers then  -- no compatible specifiers other than base
          return nil  -- give up
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

    for call_number, call in ipairs(calls) do
      local call_range = new_range(call_number, call_number, INCLUSIVE, #calls)
      local token_range = call.token_range

      if call.type == CALL then  -- a function call

        -- Ignore error S204 (Missing stylistic whitespaces) in Lua code.
        for _, arguments_number in ipairs(lpeg.match(parsers.expl3_function_call_with_lua_code_argument_csname, call.csname)) do
          local lua_code_argument = call.arguments[arguments_number]
          if #lua_code_argument.token_range > 0 then
            local lua_code_byte_range = token_range_to_byte_range(lua_code_argument.token_range)
            issues:ignore({identifier_prefix = 's204', range = lua_code_byte_range, seen = true})
          end
        end

        -- Report using a comparison conditional without the signature `:nnTF`.
        if call.csname == 'tl_sort:nN' and #call.arguments == 2 then
          -- determine the name of the comparison conditional
          local csname_argument = call.arguments[2]
          local csname = extract_csname_from_argument(csname_argument)
          if csname ~= nil then
            local _, argument_specifiers = parse_expl3_csname(csname)
            if argument_specifiers ~= nil and argument_specifiers.type == TEXT and argument_specifiers.payload ~= 'nnTF' then
              local csname_byte_range = token_range_to_byte_range(csname_argument.token_range)
              issues:add('e427', 'comparison conditional without signature `:nnTF`', csname_byte_range, argument_specifiers.payload)
            end
          end
        end

        local function_variant_definition = lpeg.match(parsers.expl3_function_variant_definition_csname, call.csname)
        local function_definition = lpeg.match(parsers.expl3_function_definition_csname, call.csname)

        local variable_declaration = lpeg.match(parsers.expl3_variable_declaration_csname, call.csname)
        local variable_definition = lpeg.match(parsers.expl3_variable_definition_csname, call.csname)
        local variable_use = lpeg.match(parsers.expl3_variable_use_csname, call.csname)

        local message_definition = lpeg.match(parsers.expl3_message_definition, call.csname)
        local message_use = lpeg.match(parsers.expl3_message_use, call.csname)

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
              base_csname_argument = base_csname_argument,
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
              local doubly_transformed_tokens, second_map_back, second_map_forward = transform_replacement_text_tokens(
                content,
                transformed_tokens,
                issues,
                num_parameters,
                transform_token_range(replacement_text_argument.token_range)
              )
              if doubly_transformed_tokens == nil then  -- we couldn't parse the replacement text
                goto skip_replacement_text  -- record partial information
              end
              local function map_back(...) return first_map_back(second_map_back(...)) end
              local function map_forward(...) return second_map_forward(first_map_forward(...)) end
              local nested_segment = {
                type = REPLACEMENT_TEXT,
                location = segment.location,
                nesting_depth = segment.nesting_depth + 1,
                transformed_tokens = {
                  tokens = doubly_transformed_tokens,
                  token_range = replacement_text_argument.token_range,
                  map_back = map_back,
                  map_forward = map_forward,
                },
              }
              table.insert(results.segments, nested_segment)
              nested_segment.calls = get_calls(results, part_number, nested_segment, issues, content)
              replacement_text_argument.segment_number = #results.segments
            end
            ::skip_replacement_text::
            -- determine the token range of the definition excluding the replacement text
            local replacement_text_token_range = replacement_text_argument.outer_token_range or replacement_text_argument.token_range
            local definition_token_range = new_range(token_range:start(), replacement_text_token_range:start(), EXCLUSIVE, #tokens)
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
                  local definition_byte_range = token_range_to_byte_range(definition_token_range)
                  issues:add("e404", "protected predicate function", definition_byte_range, format_csname(effectively_defined_csname))
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
                defined_csname_argument = defined_csname_argument,
                definition_token_range = definition_token_range,
                -- The following attributes are specific to the subtype.
                is_conditional = is_conditional,
                is_protected = is_protected,
                is_nopar = is_nopar,
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
                defined_csname_argument = defined_csname_argument,
                definition_token_range = token_range,
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
            declared_csname_argument = declared_csname_argument,
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
            local defined_csname_byte_range = token_range_to_byte_range(defined_csname_argument.token_range)
            if is_constant and (defined_csname_scope == "g" or defined_csname_scope == "l") then
              issues:add('e417', 'setting a variable as a constant', defined_csname_byte_range, format_csname(defined_csname.transcript))
            end
            if not is_constant and defined_csname_scope == "c" then
              issues:add('e418', 'setting a constant', defined_csname_byte_range, format_csname(defined_csname.transcript))
            end
            if segment.nesting_depth > 1 then
              if not is_global and defined_csname_scope == "g" then
                issues:add('e420', 'locally setting a global variable', defined_csname_byte_range, format_csname(defined_csname.transcript))
              end
              if is_global and defined_csname_scope == "l" then
                issues:add('e421', 'globally setting a local variable', defined_csname_byte_range, format_csname(defined_csname.transcript))
              end
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
            -- determine the token range of the definition excluding the definition text
            local definition_text_token_range = definition_text_argument.outer_token_range or definition_text_argument.token_range
            local definition_token_range = new_range(token_range:start(), definition_text_token_range:start(), EXCLUSIVE, #tokens)
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
              defined_csname_argument = defined_csname_argument,
              definition_token_range = definition_token_range,
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
              defined_csname_argument = defined_csname_argument,
              definition_token_range = token_range,
              -- The following attributes are specific to the subtype.
              base_csname = base_csname,
              base_csname_argument = base_csname_argument,
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
          -- determine the token range of the use excluding any arguments following the used variable name
          local used_csname_token_range = used_csname_argument.outer_token_range or used_csname_argument.token_range
          local use_token_range = new_range(token_range:start(), used_csname_token_range:stop(), INCLUSIVE, #tokens)

          local confidence = used_csname.type == TEXT and DEFINITELY or MAYBE
          local statement = {
            type = VARIABLE_USE,
            call_range = call_range,
            confidence = confidence,
            -- The following attributes are specific to the type.
            used_csname = used_csname,
            used_csname_argument = used_csname_argument,
            variable_type = variable_type,
            use_token_range = use_token_range,
          }
          table.insert(statements, statement)
          goto continue
        end

        -- Process a message definition.
        if message_definition ~= nil then
          if #call.arguments < 3 or #call.arguments > 4 then  -- we couldn't find the expected number of arguments, give up
            goto other_statement
          end
          local module_argument, message_argument, text_argument, more_text_argument = table.unpack(call.arguments)
          -- determine the number of parameters in the message text

          local function count_parameters_in_message_text(argument)
            local max_parameter_number = 0
            for _, parameter in ipairs(extract_parameter_tokens(argument.token_range)) do
              if parameter.number > 4 then  -- too many parameters, register an error
                local parameter_byte_range = token_range_to_byte_range(parameter.token_range)
                issues:add('e425', 'incorrect parameter in message text', parameter_byte_range, string.format('#%d', parameter.number))
              end
              max_parameter_number = math.max(max_parameter_number, parameter.number)
            end
            return max_parameter_number
          end

          local num_text_parameters = count_parameters_in_message_text(text_argument)
          if more_text_argument ~= nil then
            num_text_parameters = math.max(num_text_parameters, count_parameters_in_message_text(more_text_argument))
          end
          -- parse the module and message names
          local module_name = extract_name_from_tokens(module_argument.token_range)
          if module_name == nil then  -- we couldn't parse the module name, give up
            goto other_statement
          end
          local message_name = extract_name_from_tokens(message_argument.token_range)
          if message_name == nil then  -- we couldn't parse the message name, give up
            goto other_statement
          end
          -- determine the token range of the definition excluding the message text
          local text_token_range = text_argument.outer_token_range or text_argument.token_range
          local definition_token_range = new_range(token_range:start(), text_token_range:start(), EXCLUSIVE, #tokens)

          local confidence = module_name.type == TEXT and message_name.type == TEXT and DEFINITELY or MAYBE
          local statement = {
            type = MESSAGE_DEFINITION,
            call_range = call_range,
            confidence = confidence,
            -- The following attributes are specific to the type.
            module_name = module_name,
            module_argument = module_argument,
            message_name = message_name,
            message_argument = message_argument,
            text_argument = text_argument,
            more_text_argument = more_text_argument,
            num_text_parameters = num_text_parameters,
            definition_token_range = definition_token_range,
          }
          table.insert(statements, statement)
          goto continue
        end

        if message_use ~= nil then
          if #call.arguments < 2 or #call.arguments > 6 then  -- we couldn't find the expected number of arguments, give up
            goto other_statement
          end
          -- parse the module and message names
          local module_argument, message_argument = table.unpack(call.arguments)
          local module_name = extract_name_from_tokens(module_argument.token_range)
          if module_name == nil then  -- we couldn't parse the module name, give up
            goto other_statement
          end
          local message_name = extract_name_from_tokens(message_argument.token_range)
          if message_name == nil then  -- we couldn't parse the message name, give up
            goto other_statement
          end
          -- collect the text arguments
          local text_arguments = {}
          for i = 3, #call.arguments do
            table.insert(text_arguments, call.arguments[i])
          end
          -- determine the token range of the use excluding any text arguments
          local use_token_range
          if #text_arguments > 0 then
            local first_text_argument_token_range = text_arguments[1].outer_token_range or text_arguments[1].token_range
            use_token_range = new_range(token_range:start(), first_text_argument_token_range:start(), EXCLUSIVE, #tokens)
          else
            use_token_range = token_range
          end

          local confidence = module_name.type == TEXT and message_name.type == TEXT and DEFINITELY or MAYBE
          local statement = {
            type = MESSAGE_USE,
            call_range = call_range,
            confidence = confidence,
            -- The following attributes are specific to the type.
            module_name = module_name,
            module_argument = module_argument,
            message_name = message_name,
            message_argument = message_argument,
            text_arguments = text_arguments,
            use_token_range = use_token_range,
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
        local statement_type, confidence = classify_tokens(tokens, call.token_range)
        local statement = {
          type = statement_type,
          call_range = call_range,
          confidence = confidence,
        }
        table.insert(statements, statement)
      else
        error('Unexpected call type "' .. call.type .. '"')
      end
      ::continue::
    end
    return statements
  end

  -- Extract statements from function calls.
  local segment_number = 1
  while segment_number <= #results.segments do
    local segment = results.segments[segment_number]
    segment.statements = get_statements(segment)  -- may produce new segments in `results.segments`
    segment_number = segment_number + 1
  end
end

-- Report any issues.
local function report_issues(states, main_file_number, options)

  local main_state = states[main_file_number]

  local main_pathname = main_state.pathname
  local issues = main_state.issues

  -- Report issues that are apparent after the semantic analysis.
  --- Collect all segments of top-level and nested tokens, calls, and statements from all files within the group.
  local all_segments = {}
  for _, state in ipairs(states) do
    local results = state.results
    for _, segment in ipairs(results.segments or {}) do
      table.insert(all_segments, segment)
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
  local declared_variable_csname_texts, declared_variable_csname_transcripts = {}, {}
  local defined_variable_csname_texts = {}
  local defined_variable_csname_transcripts, defined_variable_base_csname_transcripts = {}, {}
  local used_variable_csname_texts, used_variable_csname_transcripts = {}, {}

  local defined_message_name_texts, defined_message_nums_text_parameters = {}, {}
  local used_message_name_texts, used_message_nums_text_arguments = {}, {}

  ---- Collect information about symbols that may have been defined.
  local maybe_defined_private_function_variant_pattern = parsers.fail
  local maybe_defined_csname_texts, maybe_defined_csname_pattern = {}, parsers.fail
  local maybe_used_csname_texts, maybe_used_csname_pattern = {}, parsers.fail

  local maybe_declared_variable_csname_texts = {}
  local maybe_declared_variable_csname_pattern = parsers.fail
  local maybe_used_variable_csname_texts = {}
  local maybe_used_variable_csname_pattern = parsers.fail

  local maybe_defined_message_name_texts, maybe_defined_message_name_pattern = {}, parsers.fail
  local maybe_used_message_name_texts, maybe_used_message_name_pattern = {}, parsers.fail

  for _, segment in ipairs(all_segments) do
    local file_number = segment.location.file_number
    local is_main_file = file_number == main_file_number

    local state = states[file_number]
    local pathname = state.pathname
    local content = state.content
    local results = state.results

    local part_number = segment.location.part_number

    local groupings = results.groupings[part_number]
    local tokens = results.tokens[part_number]

    local transformed_tokens = segment.transformed_tokens.tokens
    local map_forward = segment.transformed_tokens.map_forward
    local map_back = segment.transformed_tokens.map_back

    -- Merge a module name and a message name into a combined fully qualified name.
    local function combine_module_and_message_names(module_name, message_name)
      local transcript = string.format("%s/%s", module_name.transcript, message_name.transcript)
      if module_name.type == TEXT and message_name.type == TEXT then
        return {
          payload = string.format("%s/%s", module_name.payload, message_name.payload),
          transcript = transcript,
          type = TEXT,
        }
      else
        local message_name_pattern
        if module_name.type == TEXT then
          message_name_pattern = lpeg.P(module_name.payload)
        elseif module_name.type == PATTERN then
          message_name_pattern = module_name.payload
        else
          error('Unexpected message name type "' .. module_name.type .. '"')
        end
        message_name_pattern = message_name_pattern * lpeg.P("/")
        if message_name.type == TEXT then
          message_name_pattern = message_name_pattern * lpeg.P(message_name.payload)
        elseif message_name.type == PATTERN then
          message_name_pattern = message_name_pattern * message_name.payload
        else
          error('Unexpected message name type "' .. message_name.type .. '"')
        end
        return {
          payload = message_name_pattern,
          transcript = transcript,
          type = PATTERN,
        }
      end
    end

    -- Try and convert tokens from a range into a csname.
    local function extract_name_from_tokens(token_range)
      return _extract_name_from_tokens(options, pathname, token_range, transformed_tokens, map_forward)
    end

    -- Process an argument and record control sequence name usage and definitions.
    local function process_argument_tokens(argument)
      -- Record control sequence name usage.
      --- Extract text from tokens within c- and v-type arguments.
      if argument.specifier == "c" or argument.specifier == "v" then
        local csname = extract_name_from_tokens(argument.token_range)
        if csname ~= nil then
          if csname.type == TEXT then
            maybe_used_csname_texts[csname.payload] = true
          elseif csname.type == PATTERN then
            maybe_used_csname_pattern = (
              maybe_used_csname_pattern
              + #(csname.payload * parsers.eof)
              * lpeg.Cc(true)
            )
          else
            error('Unexpected csname type "' .. csname.type .. '"')
          end
        end
      end
      --- Scan control sequence tokens within N- and n-type arguments.
      if lpeg.match(parsers.N_or_n_type_argument_specifier, argument.specifier) ~= nil then
        for _, token in argument.token_range:enumerate(transformed_tokens, map_forward) do
          if token.type == CONTROL_SEQUENCE then
            maybe_used_csname_texts[token.payload] = true
          end
        end
      end
      -- Record control sequence name definitions and message name definitions and uses.
      --- Scan control sequence tokens within N- and n-type arguments.
      if lpeg.match(parsers.N_or_n_type_argument_specifier, argument.specifier) ~= nil then
        for token_number, token in argument.token_range:enumerate(transformed_tokens, map_forward) do
          if token.type == CONTROL_SEQUENCE then  -- control sequence, process it directly
            local next_token_number = token_number + 1
            if next_token_number <= #transformed_tokens then
              local next_token = transformed_tokens[next_token_number]
              -- Record control sequence name definitions.
              if next_token.type == CONTROL_SEQUENCE then
                -- Record potential function definitions.
                if lpeg.match(parsers.expl3_function_definition_csname, token.payload) ~= nil then
                  maybe_defined_csname_texts[next_token.payload] = true
                end
                -- Record potential variable declarations and definitions.
                if lpeg.match(parsers.expl3_variable_declaration_csname, token.payload) ~= nil then
                  maybe_declared_variable_csname_texts[next_token.payload] = true
                  maybe_defined_csname_texts[next_token.payload] = true
                end
                local variable_definition = lpeg.match(parsers.expl3_variable_definition_csname, token.payload)
                if variable_definition ~= nil then
                  local _, is_constant = table.unpack(variable_definition)
                  if is_constant then
                    maybe_declared_variable_csname_texts[next_token.payload] = true
                  end
                  maybe_defined_csname_texts[next_token.payload] = true
                end
              -- Record message name definitions and uses.
              elseif next_token.type == CHARACTER and next_token.catcode == 1 then  -- begin grouping, try to collect the module name
                local message_definition = lpeg.match(parsers.expl3_message_definition, token.payload)
                local message_use = lpeg.match(parsers.expl3_message_use, token.payload)
                if message_definition ~= nil or message_use ~= nil then
                  local next_grouping = groupings[map_back(next_token_number)]
                  assert(next_grouping ~= nil)
                  assert(map_forward(next_grouping.start) == next_token_number)
                  if next_grouping.stop ~= nil then  -- balanced text
                    local module_name_token_range = new_range(
                      next_grouping.start + 1,
                      next_grouping.stop - 1,
                      INCLUSIVE + MAYBE_EMPTY,
                      #tokens
                    )
                    local next_next_token_number = map_forward(next_grouping.stop) + 1
                    if next_next_token_number <= #transformed_tokens then
                      local next_next_token = transformed_tokens[next_next_token_number]
                      if next_next_token.type == CHARACTER  -- begin grouping, try to collect the message name
                          and next_next_token.catcode == 1 then
                        local next_next_grouping = groupings[map_back(next_next_token_number)]
                        assert(next_next_grouping ~= nil)
                        assert(map_forward(next_next_grouping.start) == next_next_token_number)
                        if next_next_grouping.stop ~= nil then  -- balanced text
                          local message_name_token_range = new_range(
                            next_next_grouping.start + 1,
                            next_next_grouping.stop - 1,
                            INCLUSIVE + MAYBE_EMPTY,
                            #tokens
                          )
                          local module_name = extract_name_from_tokens(module_name_token_range)
                          local message_name = extract_name_from_tokens(message_name_token_range)
                          if module_name ~= nil and message_name ~= nil then
                            local combined_name = combine_module_and_message_names(module_name, message_name)
                            -- Record potential message definitions.
                            if message_definition ~= nil then
                              if combined_name.type == TEXT then
                                maybe_defined_message_name_texts[combined_name.payload] = true
                              elseif combined_name.type == PATTERN then
                                maybe_defined_message_name_pattern = (
                                  maybe_defined_message_name_pattern
                                  + #(combined_name.payload * parsers.eof)
                                  * lpeg.Cc(true)
                                )
                              else
                                error('Unexpected message name type "' .. combined_name.type .. '"')
                              end
                            end
                            -- Record potential message uses.
                            if message_use ~= nil then
                              if combined_name.type == TEXT then
                                maybe_used_message_name_texts[combined_name.payload] = true
                              elseif combined_name.type == PATTERN then
                                maybe_used_message_name_pattern = (
                                  maybe_used_message_name_pattern
                                  + #(combined_name.payload * parsers.eof)
                                  * lpeg.Cc(true)
                                )
                              else
                                error('Unexpected message name type "' .. combined_name.type .. '"')
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    local call_range_to_token_range = get_call_range_to_token_range(segment.calls, #tokens)
    local token_range_to_byte_range = get_token_range_to_byte_range(tokens, #content)
    for _, statement in ipairs(segment.statements or {}) do
      local token_range = call_range_to_token_range(statement.call_range)
      local byte_range = token_range_to_byte_range(token_range)
      -- Process a function variant definition.
      if statement.type == FUNCTION_VARIANT_DEFINITION then
        local base_csname_byte_range = token_range_to_byte_range(statement.base_csname_argument.token_range)
        -- Record base control sequence names of variants, both as control sequence name usage and separately.
        if statement.base_csname.type == TEXT then
          if is_main_file then
            table.insert(variant_base_csname_texts, {statement.base_csname.payload, base_csname_byte_range})
          end
          maybe_used_csname_texts[statement.base_csname.payload] = true
        elseif statement.base_csname.type == PATTERN then
          maybe_used_csname_pattern = (
            maybe_used_csname_pattern
            + #(statement.base_csname.payload * parsers.eof)
            * lpeg.Cc(true)
          )
        else
          error('Unexpected csname type "' .. statement.base_csname.type .. '"')
        end
        -- Record control sequence name definitions.
        if statement.defined_csname.type == TEXT then
          if is_main_file then
            table.insert(defined_csname_texts, {statement.defined_csname.payload, base_csname_byte_range})
          end
          maybe_defined_csname_texts[statement.defined_csname.payload] = true
        elseif statement.defined_csname.type == PATTERN then
          maybe_defined_csname_pattern = (
            maybe_defined_csname_pattern
            + #(statement.defined_csname.payload * parsers.eof)
            * lpeg.Cc(true)
          )
        else
          error('Unexpected csname type "' .. statement.defined_csname.type .. '"')
        end
        -- Record private function variant definitions.
        if statement.defined_csname.type == TEXT and statement.is_private and is_main_file then
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
            if is_main_file then
              table.insert(indirect_definition_base_csname_texts, {statement.base_csname.payload, byte_range})
            end
          elseif statement.base_csname.type == PATTERN then
            maybe_used_csname_pattern = (
              maybe_used_csname_pattern
              + #(statement.base_csname.payload * parsers.eof)
              * lpeg.Cc(true)
            )
          else
            error('Unexpected csname type "' .. statement.base_csname.type .. '"')
          end
        end
        -- Record control sequence name usage and definitions.
        if statement.defined_csname.type == TEXT then
          maybe_defined_csname_texts[statement.defined_csname.payload] = true
          if is_main_file then
            local defined_csname_byte_range = token_range_to_byte_range(statement.defined_csname_argument.token_range)
            table.insert(defined_csname_texts, {statement.defined_csname.payload, defined_csname_byte_range})
          end
        end
        if statement.subtype == FUNCTION_DEFINITION_DIRECT and statement.replacement_text_argument.segment_number == nil then
          process_argument_tokens(statement.replacement_text_argument)
        end
        -- Record private function defition.
        if statement.defined_csname.type == TEXT and statement.is_private then
          if is_main_file then
            local definition_byte_range = token_range_to_byte_range(statement.definition_token_range)
            table.insert(defined_private_function_texts, {statement.defined_csname.payload, definition_byte_range})
          end
        end
      -- Process a variable declaration.
      elseif statement.type == VARIABLE_DECLARATION then
        -- Record variable names.
        if is_main_file then
          table.insert(
            declared_variable_csname_transcripts,
            {statement.variable_type, statement.declared_csname.transcript, byte_range}
          )
        end
        if statement.declared_csname.type == TEXT then
          if is_main_file then
            local declared_csname_byte_range = token_range_to_byte_range(statement.declared_csname_argument.token_range)
            table.insert(
              declared_defined_and_used_variable_csname_texts,
              {statement.variable_type, statement.declared_csname.payload, declared_csname_byte_range}
            )
            table.insert(declared_variable_csname_texts, {statement.declared_csname.payload, declared_csname_byte_range})
          end
          maybe_declared_variable_csname_texts[statement.declared_csname.payload] = true
        elseif statement.declared_csname.type == PATTERN then
          maybe_declared_variable_csname_pattern = (
            maybe_declared_variable_csname_pattern
            + #(statement.declared_csname.payload * parsers.eof)
            * lpeg.Cc(true)
          )
        else
          error('Unexpected csname type "' .. statement.base_csname.type .. '"')
        end
      -- Process a variable or constant definition.
      elseif statement.type == VARIABLE_DEFINITION then
        -- Record variable names.
        if is_main_file then
          local definition_byte_range = token_range_to_byte_range(statement.definition_token_range)
          if statement.is_constant then
            table.insert(
              declared_variable_csname_transcripts,
              {statement.variable_type, statement.defined_csname.transcript, definition_byte_range}
            )
          else
            table.insert(
              defined_variable_csname_transcripts,
              {statement.variable_type, statement.defined_csname.transcript, definition_byte_range}
            )
            if statement.subtype == VARIABLE_DEFINITION_INDIRECT then
              table.insert(
                defined_variable_base_csname_transcripts,
                {statement.base_variable_type, statement.base_csname.transcript, definition_byte_range}
              )
            end
          end
        end
        if statement.defined_csname.type == TEXT then
          if is_main_file then
            local defined_csname_byte_range = token_range_to_byte_range(statement.defined_csname_argument.token_range)
            table.insert(
              declared_defined_and_used_variable_csname_texts,
              {statement.variable_type, statement.defined_csname.payload, defined_csname_byte_range})
            table.insert(
              defined_variable_csname_texts,
              {statement.defined_csname.payload, defined_csname_byte_range}
            )
          end
          if statement.is_constant then
            maybe_declared_variable_csname_texts[statement.defined_csname.payload] = true
            if is_main_file then
              local defined_csname_byte_range = token_range_to_byte_range(statement.defined_csname_argument.token_range)
              table.insert(
                declared_variable_csname_texts,
                {statement.defined_csname.payload, defined_csname_byte_range}
              )
            end
          end
        end
        -- Record control sequence name usage and definitions.
        if statement.subtype == VARIABLE_DEFINITION_DIRECT then
          process_argument_tokens(statement.definition_text_argument)
        end
      -- Process a variable or constant use.
      elseif statement.type == VARIABLE_USE then
        -- Record variable names.
        if is_main_file then
          local use_byte_range = token_range_to_byte_range(statement.use_token_range)
          table.insert(
            used_variable_csname_transcripts,
            {statement.variable_type, statement.used_csname.transcript, use_byte_range}
          )
        end
        if statement.used_csname.type == TEXT then
          if is_main_file then
            local used_csname_byte_range = token_range_to_byte_range(statement.used_csname_argument.token_range)
            table.insert(
              declared_defined_and_used_variable_csname_texts,
              {statement.variable_type, statement.used_csname.payload, used_csname_byte_range}
            )
            table.insert(used_variable_csname_texts, {statement.used_csname.payload, used_csname_byte_range})
          end
          maybe_used_variable_csname_texts[statement.used_csname.payload] = true
        elseif statement.used_csname.type == PATTERN then
          maybe_used_variable_csname_pattern = (
            maybe_used_variable_csname_pattern
            + #(statement.used_csname.payload * parsers.eof)
            * lpeg.Cc(true)
          )
        else
          error('Unexpected csname type "' .. statement.defined_csname.type .. '"')
        end
      -- Process a message definition.
      elseif statement.type == MESSAGE_DEFINITION then
        -- Record message names.
        local message_name = combine_module_and_message_names(statement.module_name, statement.message_name)
        if message_name.type == TEXT then
          maybe_defined_message_name_texts[message_name.payload] = true
          if is_main_file then
            local definition_byte_range = token_range_to_byte_range(statement.definition_token_range)
            table.insert(defined_message_name_texts, {message_name.payload, definition_byte_range})
          end
        elseif message_name.type == PATTERN then
          maybe_defined_message_name_pattern = (
            maybe_defined_message_name_pattern
            + #(message_name.payload * parsers.eof)
            * lpeg.Cc(true)
          )
        else
          error('Unexpected message name type "' .. message_name.type .. '"')
        end
        -- Record numbers of text parameters.
        if message_name.type == TEXT then
          if defined_message_nums_text_parameters[message_name.payload] == nil then
            defined_message_nums_text_parameters[message_name.payload] = {
              min = statement.num_text_parameters,
              max = statement.num_text_parameters,
            }
          else
            defined_message_nums_text_parameters[message_name.payload].min = math.min(
              defined_message_nums_text_parameters[message_name.payload].min,
              statement.num_text_parameters
            )
            defined_message_nums_text_parameters[message_name.payload].max = math.max(
              defined_message_nums_text_parameters[message_name.payload].max,
              statement.num_text_parameters
            )
          end
        end
        -- Record control sequence name usage and definitions.
        process_argument_tokens(statement.text_argument)
        if statement.more_text_argument ~= nil then
          process_argument_tokens(statement.more_text_argument)
        end
      -- Process a message use.
      elseif statement.type == MESSAGE_USE then
        -- Record message names.
        local message_name = combine_module_and_message_names(statement.module_name, statement.message_name)
        if message_name.type == TEXT then
          maybe_used_message_name_texts[message_name.payload] = true
          if is_main_file then
            local use_byte_range = token_range_to_byte_range(statement.use_token_range)
            table.insert(used_message_name_texts, {message_name.payload, use_byte_range})
          end
        elseif message_name.type == PATTERN then
          maybe_used_message_name_pattern = (
            maybe_used_message_name_pattern
            + #(message_name.payload * parsers.eof)
            * lpeg.Cc(true)
          )
        else
          error('Unexpected message name type "' .. message_name.type .. '"')
        end
        -- Record numbers of text parameters.
        if message_name.type == TEXT then
          if is_main_file then
            table.insert(used_message_nums_text_arguments, {message_name.payload, #statement.text_arguments, byte_range})
          end
        end
        -- Record control sequence name usage and definitions.
        for _, argument in ipairs(statement.text_arguments) do
          process_argument_tokens(argument)
        end
      -- Process an unrecognized statement.
      elseif statement.type == OTHER_STATEMENT then
        -- Record control sequence name usage and definitions.
        for _, call in statement.call_range:enumerate(segment.calls) do
          maybe_used_csname_texts[call.csname] = true
          if is_main_file then
            local csname_byte_range = token_range_to_byte_range(call.csname_token_range)
            table.insert(called_functions_and_variants, {call.csname, csname_byte_range})
          end
          for _, argument in ipairs(call.arguments) do
            process_argument_tokens(argument)
          end
        end
      -- Process a block of unrecognized tokens.
      elseif statement.type == OTHER_TOKENS_SIMPLE or statement.type == OTHER_TOKENS_COMPLEX then
        -- Record control sequence name usage by scanning all control sequence tokens.
        for _, token in token_range:enumerate(transformed_tokens, map_forward) do
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
  local imported_prefixes = get_option('imported_prefixes', options, main_pathname)
  local expl3_well_known_csname = parsers.expl3_well_known_csname(imported_prefixes)
  local expl3_well_known_message_name = parsers.expl3_well_known_message_name(imported_prefixes)

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
        issues:add('s413', 'malformed variable or constant name', byte_range, format_csname(variable_csname))
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
  for _, declared_variable_csname_transcript in ipairs(declared_variable_csname_transcripts) do
    local declaration_type, csname_transcript, byte_range = table.unpack(declared_variable_csname_transcript)
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
  for _, defined_variable_csname_transcript in ipairs(defined_variable_csname_transcripts) do
    local definition_type, csname_transcript, byte_range = table.unpack(defined_variable_csname_transcript)
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
  for _, defined_variable_base_csname_transcript in ipairs(defined_variable_base_csname_transcripts) do
    local definition_type, csname_transcript, byte_range = table.unpack(defined_variable_base_csname_transcript)
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
  for _, used_variable_csname_transcript in ipairs(used_variable_csname_transcripts) do
    local use_type, csname_transcript, byte_range = table.unpack(used_variable_csname_transcript)
    local csname_type = lpeg.match(parsers.expl3_variable_or_constant_csname_type, csname_transcript)
    -- For uses, we require a potential compatibility between the use type and the variable type.
    -- For example, both `\str_count:N \g_example_tl` and `\tl_count:N \g_example_str` are OK.
    if csname_type ~= nil and not is_maybe_compatible_type(use_type, csname_type) then
      local context = string.format("!(%s ~= %s)", use_type, csname_type)
      issues:add('t422', 'using a variable of an incompatible type', byte_range, context)
    end
  end

  -- Report unused messages.
  for _, defined_message_name_text in ipairs(defined_message_name_texts) do
    local message_name_text, byte_range = table.unpack(defined_message_name_text)
    if (
          not maybe_used_message_name_texts[message_name_text]
          and lpeg.match(maybe_used_message_name_pattern, message_name_text) == nil
        ) then
      issues:add('w423', 'unused message', byte_range, message_name_text)
    end
  end

  -- Report using an undefined message.
  for _, used_message_name_text in ipairs(used_message_name_texts) do
    local message_name_text, byte_range = table.unpack(used_message_name_text)
    if (
          lpeg.match(expl3_well_known_message_name, message_name_text) == nil
          and not maybe_defined_message_name_texts[message_name_text]
          and lpeg.match(maybe_defined_message_name_pattern, message_name_text) == nil
        ) then
      issues:add('e424', 'using an undefined message', byte_range, message_name_text)
    end
  end

  -- Report supplying incorrect numbers of arguments to a message.
  for _, used_message_num_text_arguments in ipairs(used_message_nums_text_arguments) do
    local message_name_text, num_arguments, byte_range = table.unpack(used_message_num_text_arguments)
    local num_parameters = defined_message_nums_text_parameters[message_name_text]
    if num_parameters ~= nil and (num_arguments < num_parameters.min or num_arguments > num_parameters.max) then
      local context
      if num_arguments < num_parameters.min then
        context = string.format('%d < %d', num_arguments, num_parameters.min)
      else
        context = string.format('%d > %d', num_arguments, num_parameters.max)
      end
      issues:add('w426', 'incorrect number of arguments supplied to message', byte_range, context)
    end
  end
end

local substeps = {
  analyze,
  report_issues,
}

return {
  csname_types = csname_types,
  is_confused = is_confused,
  name = "semantic analysis",
  statement_types = statement_types,
  statement_confidences = statement_confidences,
  statement_subtypes = statement_subtypes,
  substeps = substeps,
}
