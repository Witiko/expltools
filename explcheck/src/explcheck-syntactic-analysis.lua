-- The syntactic analysis step of static analysis converts TeX tokens into a tree of function calls.

local get_option = require("explcheck-config").get_option
local lexical_analysis = require("explcheck-lexical-analysis")
local ranges = require("explcheck-ranges")
local parsers = require("explcheck-parsers")
local identity = require("explcheck-utils").identity

local get_token_byte_range = lexical_analysis.get_token_byte_range
local is_token_simple = lexical_analysis.is_token_simple
local token_types = lexical_analysis.token_types
local format_token = lexical_analysis.format_token
local format_tokens = lexical_analysis.format_tokens

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

local CONTROL_SEQUENCE = token_types.CONTROL_SEQUENCE
local CHARACTER = token_types.CHARACTER
local ARGUMENT = token_types.ARGUMENT

local lpeg = require("lpeg")

local call_types = {
  CALL = "expl3 call",
  OTHER_TOKENS = "block of other tokens",
}

local CALL = call_types.CALL
local OTHER_TOKENS = call_types.OTHER_TOKENS

local segment_types = {
  PART = "expl3 part",
  REPLACEMENT_TEXT = "function definition replacement text",
  TF_TYPE_ARGUMENTS = "T-type or F-type argument",
}

local PART = segment_types.PART
local TF_TYPE_ARGUMENTS = segment_types.TF_TYPE_ARGUMENTS

-- Get the token range for a given call.
local function get_call_token_range(calls)
  return function(call_number)
    local token_range = calls[call_number].token_range
    return token_range
  end
end

-- Convert a call range to a corresponding token range.
local function get_call_range_to_token_range(calls, num_tokens)
  local token_range_getter = get_call_token_range(calls)
  local function call_range_to_token_range(call_range)
    return call_range:new_range_from_subranges(token_range_getter, num_tokens)
  end
  return call_range_to_token_range
end

-- Try and convert tokens from a range into a text.
local function extract_text_from_tokens(token_range, tokens, map_forward)
  local texts = {}
  for _, token in token_range:enumerate(tokens, map_forward or identity) do
    if not is_token_simple(token) then  -- complex material, give up
      return nil
    else  -- simple material
      table.insert(texts, token.payload)
    end
  end
  local text = table.concat(texts)
  return text
end

-- Transform parameter tokens in a replacement text.
local function transform_replacement_text_tokens(content, tokens, issues, num_parameters, replacement_text_token_range)
  local deleted_token_numbers, transformed_tokens = {}, {}
  if #replacement_text_token_range == 0 then
    return transformed_tokens, identity, identity
  end

  local token_number = replacement_text_token_range:start()
  while token_number <= replacement_text_token_range:stop() do
    local token = tokens[token_number]
    local next_token_number = token_number + 1
    if token.type == CHARACTER and token.catcode == 6 then  -- parameter
      if next_token_number > replacement_text_token_range:stop() then  -- not followed by anything, the replacement text is invalid
        return nil
      end
      local next_token = tokens[next_token_number]
      if next_token.type == CHARACTER and next_token.catcode == 6 then  -- followed by another parameter, remove one of the tokens
        local transformed_token = {
          type = CHARACTER,
          payload = next_token.payload,
          catcode = 6,
          byte_range = new_range(token.byte_range:start(), next_token.byte_range:stop(), INCLUSIVE, #content),
        }
        table.insert(transformed_tokens, transformed_token)
        table.insert(deleted_token_numbers, next_token_number)
        next_token_number = next_token_number + 1
      elseif next_token.type == CHARACTER and lpeg.match(parsers.decimal_digit, next_token.payload) then  -- followed by a digit
        local next_digit = tonumber(next_token.payload)
        assert(next_digit ~= nil)
        if next_digit <= num_parameters then  -- a correct digit, remove it and replace the parameter with a function call argument
          local transformed_token = {
            type = ARGUMENT,
            byte_range = new_range(token.byte_range:start(), next_token.byte_range:stop(), INCLUSIVE, #content),
          }
          table.insert(transformed_tokens, transformed_token)
          table.insert(deleted_token_numbers, next_token_number)
          next_token_number = next_token_number + 1
        else  -- an incorrect digit, the replacement text is invalid
          issues:add('e304', 'unexpected parameter number', next_token.byte_range, format_token(next_token, content))
          return nil
        end
      elseif next_token.type == ARGUMENT then  -- followed by a function call argument
        -- the argument could be a correct digit, so let's remove it and replace it with another function call argument
        local transformed_token = {
          type = ARGUMENT,
          byte_range = new_range(token.byte_range:start(), next_token.byte_range:stop(), INCLUSIVE, #content),
        }
        table.insert(transformed_tokens, transformed_token)
        table.insert(deleted_token_numbers, next_token_number)
        next_token_number = next_token_number + 1
      else  -- followed by some other token, the replacement text is invalid
        return nil
      end
    else  -- not a parameter, copy it unchanged
      table.insert(transformed_tokens, token)
    end
    token_number = next_token_number
  end

  -- Transform indexes in the transformed tokens to indexes in the original tokens.
  local token_number_offset = replacement_text_token_range:start() - 1

  local function map_back(transformed_token_number)
    assert(transformed_token_number >= 1)
    assert(transformed_token_number <= #transformed_tokens)
    local original_token_number = transformed_token_number + token_number_offset
    for _, deleted_token_number in ipairs(deleted_token_numbers) do
      if deleted_token_number > original_token_number then
        break
      end
      original_token_number = original_token_number + 1
    end
    return original_token_number
  end

  -- Transform indexes in the original tokens to indexes in the transformed tokens.
  local function map_forward(original_token_number)
    assert(original_token_number >= 1)
    assert(original_token_number <= #tokens)
    local transformed_token_number = original_token_number
    for _, deleted_token_number in ipairs(deleted_token_numbers) do
      if deleted_token_number > original_token_number then
        break
      end
      transformed_token_number = transformed_token_number - 1
    end
    return transformed_token_number - token_number_offset
  end

  return transformed_tokens, map_back, map_forward
end

-- Determine whether the syntactic analysis step is too confused by the results
-- of the previous steps to run.
local function is_confused(pathname, results, options)
  local format_percentage = require("explcheck-format").format_percentage
  local evaluation = require("explcheck-evaluation")
  local count_groupings = evaluation.count_groupings
  local num_groupings, num_unclosed_groupings = count_groupings(results)
  assert(num_groupings ~= nil and num_unclosed_groupings ~= nil)
  if num_groupings > 0 then
    local unclosed_grouping_ratio = num_unclosed_groupings / num_groupings
    local min_unclosed_grouping_count = get_option('min_unclosed_grouping_count', options, pathname)
    local min_unclosed_grouping_ratio = get_option('min_unclosed_grouping_ratio', options, pathname)
    if num_unclosed_groupings >= min_unclosed_grouping_count and unclosed_grouping_ratio >= min_unclosed_grouping_ratio then
      local reason = string.format(
        "there were too many unclosed groupings (%s >= %s)",
        format_percentage(100.0 * unclosed_grouping_ratio),
        format_percentage(100.0 * min_unclosed_grouping_ratio)
      )
      return true, reason
    end
  end
  local count_expl3_bytes = evaluation.count_expl3_bytes
  local num_characters, num_invalid_characters = count_expl3_bytes(results), results.num_invalid_characters
  assert(num_characters ~= nil and num_invalid_characters ~= nil)
  if num_characters > 0 then
    local invalid_character_ratio = num_invalid_characters / num_characters
    local min_invalid_character_count = get_option('min_invalid_character_count', options, pathname)
    local min_invalid_character_ratio = get_option('min_invalid_character_ratio', options, pathname)
    if num_invalid_characters >= min_invalid_character_count and invalid_character_ratio >= min_invalid_character_ratio then
      local reason = string.format(
        "there were too many invalid characters (%s >= %s)",
        format_percentage(100.0 * invalid_character_ratio),
        format_percentage(100.0 * min_invalid_character_ratio)
      )
      return true, reason
    end
  end
  return false
end

-- Extract function calls from TeX tokens and groupings.
local function get_calls(results, part_number, segment, issues, content)

  local tokens = results.tokens[part_number]
  local groupings = results.groupings[part_number]

  local transformed_tokens = segment.transformed_tokens.tokens
  local token_range = segment.transformed_tokens.token_range
  local map_back = segment.transformed_tokens.map_back
  local map_forward = segment.transformed_tokens.map_forward

  local calls = {}
  if #token_range == 0 then
    return calls
  end

  local token_number = map_forward(token_range:start())
  local transformed_token_range_end = map_forward(token_range:stop())

  -- Record a range of unrecognized tokens.
  local function record_other_tokens(other_token_range)  -- the range is in tokens, not transformed_tokens
    local previous_call = #calls > 0 and calls[#calls] or nil
    if previous_call == nil or previous_call.type ~= OTHER_TOKENS then  -- record a new span of other tokens between calls
      table.insert(calls, {
        type = OTHER_TOKENS,
        token_range = other_token_range,
      })
    else  -- extend the previous span of other tokens
      assert(previous_call.type == OTHER_TOKENS)
      previous_call.token_range = new_range(previous_call.token_range:start(), other_token_range:stop(), INCLUSIVE, #tokens)
    end
  end

  -- Count the number of parameters in a parameter text.
  local function count_parameters_in_parameter_text(parameter_text_token_range)
    local num_parameters = 0
    local parameter_token_range_end = map_forward(parameter_text_token_range:stop())
    for token_number, token in parameter_text_token_range:enumerate(transformed_tokens, map_forward) do  -- luacheck: ignore token_number
      if token.type == CHARACTER and token.catcode == 6 then  -- parameter
        local next_token_number = token_number + 1
        if next_token_number > parameter_token_range_end then  -- not followed by anything, the parameter text is invalid
          return nil
        end
        local next_token = transformed_tokens[next_token_number]
        if next_token.type == CHARACTER and next_token.catcode == 6 then  -- followed by another parameter (unrecognized nesting?)
          return nil  -- the text is invalid
        elseif next_token.type == CHARACTER and lpeg.match(parsers.decimal_digit, next_token.payload) then  -- followed by a digit
          local next_digit = tonumber(next_token.payload)
          assert(next_digit ~= nil)
          if next_digit == num_parameters + 1 then  -- a correct digit, increment the number of parameters
            num_parameters = num_parameters + 1
          else  -- an incorrect digit, the parameter text is invalid
            issues:add('e304', 'unexpected parameter number', next_token.byte_range, format_token(next_token, content))
            return nil
          end
        elseif next_token.type == ARGUMENT then  -- followed by a function call argument
          -- the argument could be a correct digit, so let's increment the number of parameters
          num_parameters = num_parameters + 1
        else  -- followed by some other token, the parameter text is invalid
          return nil
        end
      end
    end
    return num_parameters
  end

  -- Normalize common non-expl3 commands to expl3 equivalents.
  local function normalize_csname(csname)
    local next_token_number = token_number + 1
    local normalized_csname = csname
    local ignored_token_number

    if csname == "directlua" then  -- \directlua
      normalized_csname = "lua_now:e"
    elseif csname == "let" then  -- \let
      if token_number + 1 <= transformed_token_range_end then
        if transformed_tokens[token_number + 1].type == CONTROL_SEQUENCE then  -- followed by a control sequence
          if token_number + 2 <= transformed_token_range_end then
            if transformed_tokens[token_number + 2].type == CONTROL_SEQUENCE then  -- followed by another control sequence
              normalized_csname = "cs_set_eq:NN"  -- \let \csname \csname
            elseif transformed_tokens[token_number + 2].type == CHARACTER then  -- followed by a character
              if transformed_tokens[token_number + 2].payload == "=" then  -- that is an equal sign
                if token_number + 3 <= transformed_token_range_end then
                  if transformed_tokens[token_number + 3].type == CONTROL_SEQUENCE then  -- followed by another control sequence
                    ignored_token_number = token_number + 2
                    normalized_csname = "cs_set_eq:NN"  -- \let \csname = \csname
                  end
                end
              end
            end
          end
        end
      end
    elseif csname == "def" or csname == "gdef" or csname == "edef" or csname == "xdef" then  -- \?def
      if token_number + 1 <= transformed_token_range_end then
        if transformed_tokens[token_number + 1].type == CONTROL_SEQUENCE then  -- followed by a control sequence
          if csname == "def" then  -- \def \csname
            normalized_csname = "cs_set:Npn"
          elseif csname == "gdef" then  -- \gdef \csname
            normalized_csname = "cs_gset:Npn"
          elseif csname == "edef" then  -- \edef \csname
            normalized_csname = "cs_set:Npe"
          elseif csname == "xdef" then  -- \xdef \csname
            normalized_csname = "cs_set:Npx"
          else
            assert(false, csname)
          end
        end
      end
    elseif csname == "global" then  -- \global
      next_token_number = next_token_number + 1
      assert(next_token_number == token_number + 2)
      if token_number + 1 <= transformed_token_range_end then
        if transformed_tokens[token_number + 1].type == CONTROL_SEQUENCE then  -- followed by a control sequence
          csname = transformed_tokens[token_number + 1].payload
          if csname == "let" then  -- \global \let
            if token_number + 2 <= transformed_token_range_end then
              if transformed_tokens[token_number + 2].type == CONTROL_SEQUENCE then  -- followed by another control sequence
                if token_number + 3 <= transformed_token_range_end then
                  if transformed_tokens[token_number + 3].type == CONTROL_SEQUENCE then  -- followed by another control sequence
                    normalized_csname = "cs_gset_eq:NN"  -- \global \let \csname \csname
                    goto skip_decrement
                  elseif transformed_tokens[token_number + 3].type == CHARACTER then  -- followed by a character
                    if transformed_tokens[token_number + 3].payload == "=" then  -- that is an equal sign
                      if token_number + 4 <= transformed_token_range_end then
                        if transformed_tokens[token_number + 4].type == CONTROL_SEQUENCE then  -- followed by another control sequence
                          ignored_token_number = token_number + 3
                          normalized_csname = "cs_gset_eq:NN"  -- \global \let \csname = \csname
                          goto skip_decrement
                        end
                      end
                    end
                  end
                end
              end
            end
          elseif csname == "def" or csname == "gdef" or csname == "edef" or csname == "xdef" then  -- \global \?def
            if token_number + 2 <= transformed_token_range_end then
              if transformed_tokens[token_number + 2].type == CONTROL_SEQUENCE then  -- followed by another control sequence
                if csname == "def" then  -- \global \def \csname
                  normalized_csname = "cs_gset:Npn"
                elseif csname == "gdef" then  -- \global \gdef \csname
                  normalized_csname = "cs_gset:Npn"
                elseif csname == "edef" then  -- \global \edef \csname
                  normalized_csname = "cs_gset:Npe"
                elseif csname == "xdef" then  -- \global \xdef \csname
                  normalized_csname = "cs_gset:Npx"
                else
                  assert(false)
                end
                goto skip_decrement
              end
            end
          end
        end
      end
      next_token_number = next_token_number - 1
      assert(next_token_number == token_number + 1)
      ::skip_decrement::
    end
    return normalized_csname, next_token_number, ignored_token_number
  end

  while token_number <= transformed_token_range_end do
    local token = transformed_tokens[token_number]
    local next_token, next_next_token, next_token_range, context
    if token.type == CONTROL_SEQUENCE then  -- a control sequence
      local original_csname = token.payload
      local csname, next_token_number, ignored_token_number = normalize_csname(original_csname)
      ::retry_control_sequence::
      local csname_token_range = new_range(token_number, next_token_number, EXCLUSIVE, #transformed_tokens, map_back, #tokens)
      local _, _, argument_specifiers = csname:find(":([^:]*)")  -- try to extract a call
      if argument_specifiers ~= nil and lpeg.match(parsers.argument_specifiers, argument_specifiers) ~= nil then
        local arguments = {}

        local function record_argument(argument)
          if argument.specifier == "V" then
            for _, argument_token in argument.token_range:enumerate(transformed_tokens, map_forward) do
              if argument_token.type == CONTROL_SEQUENCE and
                  lpeg.match(parsers.expl3_maybe_unexpandable_csname, argument_token.payload) ~= nil then
                issues:add(
                  't305',
                  'expanding an unexpandable variable or constant',
                  argument_token.byte_range,
                  format_token(argument_token, content)
                )
              end
            end
          elseif argument.specifier == "v" then
            local argument_text = extract_text_from_tokens(argument.token_range, transformed_tokens, map_forward)
            if argument_text ~= nil and lpeg.match(parsers.expl3_maybe_unexpandable_csname, argument_text) ~= nil then
              local argument_byte_range = argument.token_range:new_range_from_subranges(get_token_byte_range(tokens), #content)
              issues:add(
                't305',
                'expanding an unexpandable variable or constant',
                argument_byte_range,
                format_tokens(argument.outer_token_range or argument.token_range, tokens, content)
              )
            end
          end
          table.insert(arguments, argument)
        end

        local argument
        local next_grouping, parameter_text_start_token_number
        local num_parameters
        for argument_specifier in argument_specifiers:gmatch(".") do  -- an expl3 control sequence, try to collect the arguments
          if argument_specifier == "w" then
            goto skip_other_token  -- a "weird" argument specifier, skip the control sequence
          elseif argument_specifier == "D" then
            goto skip_other_token  -- a "do not use" argument specifier, skip the control sequence
          end
          ::check_token::
          if next_token_number > transformed_token_range_end then  -- missing argument (partial application?), skip all remaining tokens
            if token_range:stop() == #tokens then
              if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                goto retry_control_sequence
              else
                issues:add('e301', 'end of expl3 part within function call', token.byte_range)
              end
            end
            next_token_range = new_range(token_number, transformed_token_range_end, INCLUSIVE, #transformed_tokens, map_back, #tokens)
            record_other_tokens(next_token_range)
            token_number = next_token_number
            goto continue
          end
          next_token = transformed_tokens[next_token_number]
          if ignored_token_number ~= nil and next_token_number == ignored_token_number then
            next_token_number = next_token_number + 1
            goto check_token
          end
          if argument_specifier == "p" then
            parameter_text_start_token_number = next_token_number  -- a "TeX parameter" argument specifier, try to collect parameter text
            while next_token_number <= transformed_token_range_end do
              next_token = transformed_tokens[next_token_number]
              if next_token.type == CHARACTER and next_token.catcode == 2 then  -- end grouping, missing argument (partial application?)
                if csname ~= original_csname then  -- first, retry without trying to understand non-expl3
                  csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                  goto retry_control_sequence
                else  -- if this doesn't help, skip all remaining tokens
                  next_token_range = new_range(token_number, next_token_number, EXCLUSIVE, #transformed_tokens, map_back, #tokens)
                  record_other_tokens(next_token_range)
                  token_number = next_token_number
                  goto continue
                end
              elseif next_token.type == CHARACTER and next_token.catcode == 1 then  -- begin grouping, validate and record parameter text
                next_token_number = next_token_number - 1
                next_token_range = new_range(
                  parameter_text_start_token_number,
                  next_token_number,
                  INCLUSIVE + MAYBE_EMPTY,
                  #transformed_tokens,
                  map_back,
                  #tokens
                )
                num_parameters = count_parameters_in_parameter_text(next_token_range)
                argument = {
                  specifier = argument_specifier,
                  token_range = next_token_range,
                  num_parameters = num_parameters,
                }
                record_argument(argument)
                break
              end
              next_token_number = next_token_number + 1
            end
            if next_token_number > transformed_token_range_end then  -- missing begin grouping (partial application?)
              if token_range:stop() == #tokens then  -- skip all remaining tokens
                if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                  csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                  goto retry_control_sequence
                else
                  issues:add('e301', 'end of expl3 part within function call', next_token.byte_range)
                end
              end
              next_token_range = new_range(token_number, transformed_token_range_end, INCLUSIVE, #transformed_tokens, map_back, #tokens)
              record_other_tokens(next_token_range)
              token_number = next_token_number
              goto continue
            end
          elseif lpeg.match(parsers.N_type_argument_specifier, argument_specifier) then  -- an N-type argument specifier
            if next_token.type == CHARACTER and next_token.catcode == 1 then  -- begin grouping, try to collect the balanced text
              next_grouping = groupings[map_back(next_token_number)]
              assert(next_grouping ~= nil)
              assert(map_forward(next_grouping.start) == next_token_number)
              if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                if token_range:stop() == #tokens then
                  if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                    csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                    goto retry_control_sequence
                  else
                    issues:add('e301', 'end of expl3 part within function call', next_token.byte_range)
                  end
                end
                goto skip_other_token
              else  -- a balanced text
                next_token_range = new_range(
                  map_forward(next_grouping.start + 1),
                  map_forward(next_grouping.stop - 1),
                  INCLUSIVE + MAYBE_EMPTY,
                  #transformed_tokens
                )
                if #next_token_range == 1 then  -- a single token, record it
                  context = format_tokens(new_range(next_grouping.start, next_grouping.stop, INCLUSIVE, #tokens), tokens, content)
                  issues:add('w303', 'braced N-type function call argument', next_token.byte_range, context)
                  argument = {
                    specifier = argument_specifier,
                    token_range = new_range(next_grouping.start + 1, next_grouping.stop - 1, INCLUSIVE, #tokens),
                    outer_token_range = new_range(next_grouping.start, next_grouping.stop, INCLUSIVE, #tokens),
                  }
                  record_argument(argument)
                  next_token_number = map_forward(next_grouping.stop)
                elseif #next_token_range == 2 and  -- two tokens
                    transformed_tokens[next_token_range:start()].type == CHARACTER and
                    transformed_tokens[next_token_range:start()].catcode == 6 and  -- a parameter
                    (transformed_tokens[next_token_range:stop()].type == ARGUMENT or  -- followed by a function call argument (maybe digit)
                     transformed_tokens[next_token_range:stop()].type == CHARACTER and  -- digit (unrecognized parameter/replacement text?)
                     lpeg.match(parsers.decimal_digit, transformed_tokens[next_token_range:stop()].payload)) then  -- skip all tokens
                  next_token_range
                    = new_range(token_number, map_forward(next_grouping.stop), INCLUSIVE, #transformed_tokens, map_back, #tokens)
                  record_other_tokens(next_token_range)
                  token_number = map_forward(next_grouping.stop + 1)
                  goto continue
                else  -- no token / more than one token, skip the control sequence
                  if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                    csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                    goto retry_control_sequence
                  else
                    context = format_tokens(new_range(next_grouping.start, next_grouping.stop, INCLUSIVE, #tokens), tokens, content)
                    issues:add('e300', 'unexpected function call argument', next_token.byte_range, context)
                    goto skip_other_token
                  end
                end
              end
            elseif next_token.type == CHARACTER and next_token.catcode == 2 then  -- end grouping (partial application?), skip all tokens
              next_token_range = new_range(token_number, next_token_number, EXCLUSIVE, #transformed_tokens, map_back, #tokens)
              record_other_tokens(next_token_range)
              token_number = next_token_number
              goto continue
            else
              if next_token.type == CHARACTER and next_token.catcode == 6 then  -- a parameter
                if next_token_number + 1 <= transformed_token_range_end then  -- followed by one other token
                  next_next_token = transformed_tokens[next_token_number + 1]
                  if next_next_token.type == ARGUMENT or  -- that is either a function call argument (could be a digit)
                      next_next_token.type == CHARACTER and  -- or an actual digit (unrecognized parameter/replacement text?)
                      lpeg.match(parsers.decimal_digit, next_next_token.payload) then  -- skip all tokens
                    next_token_range = new_range(token_number, next_token_number + 1, INCLUSIVE, #transformed_tokens, map_back, #tokens)
                    record_other_tokens(next_token_range)
                    token_number = next_token_number + 2
                    goto continue
                  end
                end
              end
              -- an N-type argument, record it
              next_token_range = new_range(next_token_number, next_token_number, INCLUSIVE, #transformed_tokens, map_back, #tokens)
              argument = {
                specifier = argument_specifier,
                token_range = next_token_range,
              }
              record_argument(argument)
            end
          elseif lpeg.match(parsers.n_type_argument_specifier, argument_specifier) then  -- an n-type argument specifier
            if next_token.type == CHARACTER and next_token.catcode == 1 then  -- begin grouping, try to collect the balanced text
              next_grouping = groupings[map_back(next_token_number)]
              assert(next_grouping ~= nil)
              assert(map_forward(next_grouping.start) == next_token_number)
              if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                if token_range:stop() == #tokens then
                  if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                    csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                    goto retry_control_sequence
                  else
                    issues:add('e301', 'end of expl3 part within function call', next_token.byte_range)
                  end
                end
                goto skip_other_token
              else  -- a balanced text, record it
                argument = {
                  specifier = argument_specifier,
                  token_range = new_range(next_grouping.start + 1, next_grouping.stop - 1, INCLUSIVE + MAYBE_EMPTY, #tokens),
                  outer_token_range = new_range(next_grouping.start, next_grouping.stop, INCLUSIVE, #tokens),
                }
                if argument_specifier == "T" or argument_specifier == "F" then
                  local nested_segment = {
                    type = TF_TYPE_ARGUMENTS,
                    location = segment.location,
                    nesting_depth = segment.nesting_depth + 1,
                    transformed_tokens = {
                      tokens = transformed_tokens,
                      token_range = argument.token_range,
                      map_back = map_back,
                      map_forward = map_forward,
                    },
                  }
                  table.insert(results.segments, nested_segment)
                  nested_segment.calls = get_calls(results, part_number, nested_segment, issues, content)
                  argument.segment_number = #results.segments
                end
                record_argument(argument)
                next_token_number = map_forward(next_grouping.stop)
              end
            elseif next_token.type == CHARACTER and next_token.catcode == 2 then  -- end grouping (partial application?), skip all tokens
              next_token_range = new_range(token_number, next_token_number, EXCLUSIVE, #transformed_tokens, map_back, #tokens)
              record_other_tokens(next_token_range)
              token_number = next_token_number
              goto continue
            else  -- not begin grouping
              if next_token.type == CHARACTER and next_token.catcode == 6 then  -- a parameter
                if next_token_number + 1 <= transformed_token_range_end then  -- followed by one other token
                  next_next_token = transformed_tokens[next_token_number + 1]
                  if next_next_token.type == ARGUMENT or  -- that is either a function call argument (could be a digit)
                      next_next_token.type == CHARACTER and  -- or an actual digit (unrecognized parameter/replacement text?)
                      lpeg.match(parsers.decimal_digit, next_next_token.payload) then  -- skip all tokens
                    next_token_range = new_range(token_number, next_token_number + 1, INCLUSIVE, #transformed_tokens, map_back, #tokens)
                    record_other_tokens(next_token_range)
                    token_number = next_token_number + 2
                    goto continue
                  end
                end
              end
              -- an unbraced n-type argument, record it
              issues:add('w302', 'unbraced n-type function call argument', next_token.byte_range, format_token(next_token, content))
              next_token_range = new_range(next_token_number, next_token_number, INCLUSIVE, #transformed_tokens, map_back, #tokens)
              argument = {
                specifier = argument_specifier,
                token_range = next_token_range,
              }
              record_argument(argument)
            end
          else
            error('Unexpected argument specifier "' .. argument_specifier .. '"')
          end
          next_token_number = next_token_number + 1
        end
        next_token_range = new_range(token_number, next_token_number, EXCLUSIVE, #transformed_tokens, map_back, #tokens)
        table.insert(calls, {
          type = CALL,
          token_range = next_token_range,
          csname = csname,
          csname_token_range = csname_token_range,
          arguments = arguments,
        })
        token_number = next_token_number
        goto continue
      else  -- a non-expl3 control sequence, skip it
        goto skip_other_token
      end
    elseif token.type == CHARACTER then  -- an ordinary character
      if token.payload == "=" then  -- an equal sign
        if token_number + 2 <= transformed_token_range_end then  -- followed by two other tokens
          next_token = transformed_tokens[token_number + 1]
          if next_token.type == CONTROL_SEQUENCE then  -- the first being a control sequence
            next_next_token = transformed_tokens[token_number + 2]
            if next_next_token.type == CHARACTER and next_next_token.payload == "," then  -- and the second being a comma
              -- (probably l3keys definition?), skip all three tokens
              next_token_range = new_range(token_number, token_number + 2, INCLUSIVE, #transformed_tokens, map_back, #tokens)
              record_other_tokens(next_token_range)
              token_number = token_number + 3
              goto continue
            end
          end
        end
      end
      -- an ordinary character, skip it
      goto skip_other_token
    elseif token.type == ARGUMENT then  -- a function call argument, skip it
      goto skip_other_token
    else
      error('Unexpected token type "' .. token.type .. '"')
    end
    ::skip_other_token::
    next_token_range = new_range(token_number, token_number, INCLUSIVE, #transformed_tokens, map_back, #tokens)
    record_other_tokens(next_token_range)
    token_number = token_number + 1
    ::continue::
  end
  return calls
end

-- Convert the tokens to top-level and nested segments of function calls and report any issues.
local function analyze_and_report_issues(states, file_number, options)  -- luacheck: ignore options

  local state = states[file_number]

  local content = state.content
  local issues = state.issues
  local results = state.results

  results.segments = {}
  for part_number, part_tokens in ipairs(results.tokens) do
    local segment = {
      type = PART,
      location = {
        file_number = file_number,
        part_number = part_number,
      },
      nesting_depth = 1,
      transformed_tokens = {
        tokens = part_tokens,
        token_range = new_range(1, #part_tokens, INCLUSIVE, #part_tokens),
        map_back = identity,
        map_forward = identity,
      },
    }
    table.insert(results.segments, segment)
    segment.calls = get_calls(results, part_number, segment, issues, content)
  end
end

local substeps = {
  analyze_and_report_issues,
}

return {
  call_types = call_types,
  extract_text_from_tokens = extract_text_from_tokens,
  get_calls = get_calls,
  get_call_range_to_token_range = get_call_range_to_token_range,
  get_call_token_range = get_call_token_range,
  is_confused = is_confused,
  name = "syntactic analysis",
  segment_types = segment_types,
  substeps = substeps,
  transform_replacement_text_tokens = transform_replacement_text_tokens,
}
