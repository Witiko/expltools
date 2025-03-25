-- The syntactic analysis step of static analysis converts TeX tokens into a tree of function calls.

local ranges = require("explcheck-ranges")
local parsers = require("explcheck-parsers")

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

local lpeg = require("lpeg")

local call_types = {
  CALL = "call",
  OTHER_TOKENS = "other tokens",
}

local CALL = call_types.CALL
local OTHER_TOKENS = call_types.OTHER_TOKENS

-- Convert the content to a tree of function calls an register any issues.
local function syntactic_analysis(pathname, content, issues, results, options)  -- luacheck: ignore pathname content options

  local token_types = require("explcheck-lexical-analysis").token_types

  local CONTROL_SEQUENCE = token_types.CONTROL_SEQUENCE
  local CHARACTER = token_types.CHARACTER

  -- Extract function calls from TeX tokens and groupings.
  local function get_calls(transformed_tokens, original_tokens, original_token_range, map_forward, map_back, groupings)
    local calls = {}
    if #original_token_range == 0 then
      return calls
    end

    local token_number = map_forward(original_token_range:start())
    local transformed_token_range_end = map_forward(original_token_range:stop())

    local function record_other_tokens(other_token_range)
      local previous_call = #calls > 0 and calls[#calls] or nil
      if previous_call == nil or previous_call[1] ~= OTHER_TOKENS then  -- record a new span of other tokens between calls
        table.insert(calls, {OTHER_TOKENS, other_token_range})
      else  -- extend the previous span of other tokens
        assert(previous_call[1] == OTHER_TOKENS)
        assert(previous_call[2]:stop() == other_token_range:start() - 1)
        previous_call[2] = new_range(previous_call[2]:start(), other_token_range:stop(), INCLUSIVE, #original_tokens)
      end
    end

    local token_range
    while token_number <= transformed_token_range_end do
      local token = transformed_tokens[token_number]
      local token_type, payload, catcode, byte_range = table.unpack(token)  -- luacheck: ignore catcode byte_range
      if token_type == CONTROL_SEQUENCE then  -- a control sequence, try to extract a call
        local csname = payload
        local _, _, argument_specifiers = csname:find(":([^:]*)")
        if argument_specifiers ~= nil and lpeg.match(parsers.argument_specifiers, argument_specifiers) ~= nil then
          local arguments = {}
          local next_token_number = token_number + 1
          local next_token, next_token_type, next_payload, next_catcode, next_byte_range  -- luacheck: ignore next_payload
          local next_grouping, parameter_text_start_token_number
          for argument_specifier in argument_specifiers:gmatch(".") do  -- an expl3 control sequence, try to collect the arguments
            if lpeg.match(parsers.weird_argument_specifier, argument_specifier) then
              goto skip_other_token  -- a "weird" argument specifier, skip the control sequence
            elseif lpeg.match(parsers.do_not_use_argument_specifier, argument_specifier) then
              goto skip_other_token  -- a "do not use" argument specifier, skip the control sequence
            end
            if next_token_number > transformed_token_range_end then  -- missing argument (partial application?), skip all remaining tokens
              if transformed_token_range_end == #transformed_tokens then
                issues:add('e301', 'end of expl3 part within function call', byte_range)
              end
              token_range = new_range(
                token_number, transformed_token_range_end, INCLUSIVE,
                #transformed_tokens, map_back, #original_tokens
              )
              record_other_tokens(token_range)
              token_number = next_token_number
              goto continue
            end
            next_token = transformed_tokens[next_token_number]
            next_token_type, next_payload, next_catcode, next_byte_range = table.unpack(next_token)
            if lpeg.match(parsers.parameter_argument_specifier, argument_specifier) then
              parameter_text_start_token_number = next_token_number  -- a "TeX parameter" argument specifier, try to collect parameter text
              while next_token_number <= transformed_token_range_end do
                next_token = transformed_tokens[next_token_number]
                next_token_type, next_payload, next_catcode, next_byte_range = table.unpack(next_token)
                if next_token_type == CHARACTER and next_catcode == 2 then  -- end grouping, skip the control sequence
                  issues:add('e300', 'unexpected function call argument', next_byte_range)
                  goto skip_other_token
                elseif next_token_type == CHARACTER and next_catcode == 1 then  -- begin grouping, record the parameter text
                  next_token_number = next_token_number - 1
                  token_range = new_range(
                    parameter_text_start_token_number, next_token_number, INCLUSIVE + MAYBE_EMPTY,
                    #transformed_tokens, map_back, #original_tokens
                  )
                  table.insert(arguments, token_range)
                  break
                end
                next_token_number = next_token_number + 1
              end
              if next_token_number > transformed_token_range_end then  -- missing begin grouping (partial application?)
                if transformed_token_range_end == #transformed_tokens then  -- skip all remaining tokens
                  issues:add('e301', 'end of expl3 part within function call', next_byte_range)
                end
                record_other_tokens(
                  new_range(
                    token_number, transformed_token_range_end, INCLUSIVE,
                    #transformed_tokens, map_back, #original_tokens
                  )
                )
                token_number = next_token_number
                goto continue
              end
            elseif lpeg.match(parsers.N_type_argument_specifier, argument_specifier) then  -- an N-type argument specifier
              if next_token_type == CHARACTER and next_catcode == 1 then  -- begin grouping, try to collect the balanced text
                next_grouping = groupings[next_token_number]
                assert(next_grouping ~= nil)
                assert(map_forward(next_grouping.start) == next_token_number)
                if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                  if transformed_token_range_end == #transformed_tokens then
                    issues:add('e301', 'end of expl3 part within function call', next_byte_range)
                  end
                  goto skip_other_token
                else  -- a balanced text
                  token_range = new_range(
                    next_grouping.start + 1, next_grouping.stop - 1, INCLUSIVE + MAYBE_EMPTY,
                    #original_tokens
                  )
                  if #token_range == 1 then  -- a single token, record it
                      issues:add('w303', 'braced N-type function call argument', next_byte_range)
                      table.insert(arguments, token_range)
                      next_token_number = map_forward(next_grouping.stop)
                  else  -- no token / more than one token, skip the control sequence
                    issues:add('e300', 'unexpected function call argument', next_byte_range)
                    goto skip_other_token
                  end
                end
              elseif next_token_type == CHARACTER and next_catcode == 2 then  -- end grouping (partial application?), skip all tokens
                token_range = new_range(
                  token_number, next_token_number, EXCLUSIVE,
                  #transformed_tokens, map_back, #original_tokens
                )
                record_other_tokens(token_range)
                token_number = next_token_number
                goto continue
              else
                if next_token_type == CHARACTER and next_catcode == 6 then  -- a parameter
                  if next_token_number + 1 <= transformed_token_range_end then  -- followed by one other token
                    -- that is a digit (unrecognized parameter/replacement text?)
                    if transformed_tokens[next_token_number + 1][1] == CHARACTER and
                        lpeg.match(parsers.decimal_digit, transformed_tokens[next_token_number + 1][2]) then  -- skip all tokens
                      token_range = new_range(
                        token_number, next_token_number + 1, INCLUSIVE,
                        #transformed_tokens, map_back, #original_tokens
                      )
                      record_other_tokens(token_range)
                      token_number = next_token_number + 2
                      goto continue
                    end
                  end
                end
                -- an N-type argument, record it
                token_range = new_range(
                  next_token_number, next_token_number, INCLUSIVE,
                  #transformed_tokens, map_back, #original_tokens
                )
                table.insert(arguments, token_range)
              end
            elseif lpeg.match(parsers.n_type_argument_specifier, argument_specifier) then  -- an n-type argument specifier
              if next_token_type == CHARACTER and next_catcode == 1 then  -- begin grouping, try to collect the balanced text
                next_grouping = groupings[next_token_number]
                assert(next_grouping ~= nil)
                assert(map_forward(next_grouping.start) == next_token_number)
                if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                  if transformed_token_range_end == #transformed_tokens then
                    issues:add('e301', 'end of expl3 part within function call', next_byte_range)
                  end
                  goto skip_other_token
                else  -- a balanced text, record it
                  token_range = new_range(
                    next_grouping.start + 1, next_grouping.stop - 1, INCLUSIVE + MAYBE_EMPTY,
                    #transformed_tokens
                  )
                  table.insert(arguments, token_range)
                  next_token_number = next_grouping.stop
                end
              elseif next_token_type == CHARACTER and next_catcode == 2 then  -- end grouping (partial application?), skip all tokens
                token_range = new_range(
                  token_number, next_token_number, EXCLUSIVE,
                  #transformed_tokens, map_back, #original_tokens
                )
                record_other_tokens(token_range)
                token_number = next_token_number
                goto continue
              else  -- not begin grouping
                if next_token_type == CHARACTER and next_catcode == 6 then  -- a parameter
                  if next_token_number + 1 <= transformed_token_range_end then  -- followed by one other token
                    -- that is a digit (unrecognized parameter/replacement text?)
                    if transformed_tokens[next_token_number + 1][1] == CHARACTER and
                        lpeg.match(parsers.decimal_digit, transformed_tokens[next_token_number + 1][2]) then  -- skip all tokens
                      token_range = new_range(
                        token_number, next_token_number + 1, INCLUSIVE,
                        #transformed_tokens, map_back, #original_tokens
                      )
                      record_other_tokens(token_range)
                      token_number = next_token_number + 2
                      goto continue
                    end
                  end
                end
                -- an unbraced n-type argument, record it
                issues:add('w302', 'unbraced n-type function call argument', next_byte_range)
                token_range = new_range(
                  next_token_number, next_token_number, INCLUSIVE,
                  #transformed_tokens, map_back, #original_tokens
                )
                table.insert(arguments, token_range)
              end
            else
              error('Unexpected argument specifier "' .. argument_specifier .. '"')
            end
            next_token_number = next_token_number + 1
          end
          token_range = new_range(
            token_number, next_token_number, EXCLUSIVE,
            #transformed_tokens, map_back, #original_tokens
          )
          table.insert(calls, {CALL, token_range, csname, arguments})
          token_number = next_token_number
          goto continue
        else  -- a non-expl3 control sequence, skip it
          goto skip_other_token
        end
      elseif token_type == CHARACTER then  -- an ordinary character
        if payload == "=" then  -- an equal sign
          if token_number + 2 <= transformed_token_range_end then  -- followed by two other tokens
            if transformed_tokens[token_number + 1][1] == CONTROL_SEQUENCE then  -- the first being a control sequence
              if transformed_tokens[token_number + 2][1] == CHARACTER and  -- and the second being a comma
                  transformed_tokens[token_number + 2][2] == "," then
                -- (probably l3keys definition?), skip all three tokens
                token_range = new_range(
                  token_number, token_number + 2, INCLUSIVE,
                  #transformed_tokens, map_back, #original_tokens
                )
                record_other_tokens(token_range)
                token_number = token_number + 3
                goto continue
              end
            end
          end
        end
        -- an ordinary character, skip it
        goto skip_other_token
      else
        error('Unexpected token type "' .. token_type .. '"')
      end
      ::skip_other_token::
      token_range = new_range(
        token_number, token_number, INCLUSIVE,
        #transformed_tokens, map_back, #original_tokens
      )
      record_other_tokens(token_range)
      token_number = token_number + 1
      ::continue::
    end
    return calls
  end

  local calls = {}
  for part_number, part_tokens in ipairs(results.tokens) do
    local part_groupings = results.groupings[part_number]
    local part_token_range = new_range(1, #part_tokens, INCLUSIVE, #part_tokens)
    local function identity(index) return index end
    local part_calls = get_calls(part_tokens, part_tokens, part_token_range, identity, identity, part_groupings)
    table.insert(calls, part_calls)
  end

  -- Store the intermediate results of the analysis.
  results.calls = calls
end

return {
  process = syntactic_analysis,
  call_types = call_types
}
