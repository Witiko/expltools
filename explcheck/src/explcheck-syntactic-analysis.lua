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
  local function get_calls(tokens, token_range, groupings)
    local calls = {}
    if #token_range == 0 then
      return calls
    end

    local token_number = token_range:start()

    -- Record a range of unrecognized tokens.
    local function record_other_tokens(other_token_range)
      local previous_call = #calls > 0 and calls[#calls] or nil
      if previous_call == nil or previous_call[1] ~= OTHER_TOKENS then  -- record a new span of other tokens between calls
        table.insert(calls, {OTHER_TOKENS, other_token_range})
      else  -- extend the previous span of other tokens
        assert(previous_call[1] == OTHER_TOKENS)
        assert(previous_call[2]:stop() == other_token_range:start() - 1)
        previous_call[2] = new_range(previous_call[2]:start(), other_token_range:stop(), INCLUSIVE, #tokens)
      end
    end

    -- Normalize common non-expl3 commands to expl3 equivalents.
    local function normalize_csname(csname)
      local next_token_number = token_number + 1
      local normalized_csname = csname
      local ignored_token_number

      if csname == "let" then  -- \let
        if token_number + 1 <= token_range:stop() then
          if tokens[token_number + 1][1] == CONTROL_SEQUENCE then  -- followed by a control sequence
            if token_number + 2 <= token_range:stop() then
              if tokens[token_number + 2][1] == CONTROL_SEQUENCE then  -- followed by another control sequence
                normalized_csname = "cs_set_eq:NN"  -- \let \csname \csname
              elseif tokens[token_number + 2][1] == CHARACTER then  -- followed by a character
                if tokens[token_number + 2][2] == "=" then  -- that is an equal sign
                  if token_number + 3 <= token_range:stop() then
                    if tokens[token_number + 3][1] == CONTROL_SEQUENCE then  -- followed by another control sequence
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
        if token_number + 1 <= token_range:stop() then
          if tokens[token_number + 1][1] == CONTROL_SEQUENCE then  -- followed by a control sequence
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
        if token_number + 1 <= token_range:stop() then
          if tokens[token_number + 1][1] == CONTROL_SEQUENCE then  -- followed by a control sequence
            csname = tokens[token_number + 1][2]
            if csname == "let" then  -- \global \let
              if token_number + 2 <= token_range:stop() then
                if tokens[token_number + 2][1] == CONTROL_SEQUENCE then  -- followed by another control sequence
                  if token_number + 3 <= token_range:stop() then
                    if tokens[token_number + 3][1] == CONTROL_SEQUENCE then  -- followed by another control sequence
                      normalized_csname = "cs_gset_eq:NN"  -- \global \let \csname \csname
                      goto skip_decrement
                    elseif tokens[token_number + 3][1] == CHARACTER then  -- followed by a character
                      if tokens[token_number + 3][2] == "=" then  -- that is an equal sign
                        if token_number + 4 <= token_range:stop() then
                          if tokens[token_number + 4][1] == CONTROL_SEQUENCE then  -- followed by another control sequence
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
              if token_number + 2 <= token_range:stop() then
                if tokens[token_number + 2][1] == CONTROL_SEQUENCE then  -- followed by another control sequence
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

    while token_number <= token_range:stop() do
      local token = tokens[token_number]
      local token_type, payload, _, byte_range = table.unpack(token)
      if token_type == CONTROL_SEQUENCE then  -- a control sequence
        local original_csname = payload
        local csname, next_token_number, ignored_token_number = normalize_csname(original_csname)
        ::retry_control_sequence::
        local _, _, argument_specifiers = csname:find(":([^:]*)")  -- try to extract a call
        if argument_specifiers ~= nil and lpeg.match(parsers.argument_specifiers, argument_specifiers) ~= nil then
          local arguments = {}
          local next_token, next_token_range
          local next_token_type, _, next_catcode, next_byte_range
          local next_grouping, parameter_text_start_token_number
          for argument_specifier in argument_specifiers:gmatch(".") do  -- an expl3 control sequence, try to collect the arguments
            if lpeg.match(parsers.weird_argument_specifier, argument_specifier) then
              goto skip_other_token  -- a "weird" argument specifier, skip the control sequence
            elseif lpeg.match(parsers.do_not_use_argument_specifier, argument_specifier) then
              goto skip_other_token  -- a "do not use" argument specifier, skip the control sequence
            end
            ::check_token::
            if next_token_number > token_range:stop() then  -- missing argument (partial application?), skip all remaining tokens
              if token_range:stop() == #tokens then
                if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                  csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                  goto retry_control_sequence
                else
                  issues:add('e301', 'end of expl3 part within function call', byte_range)
                end
              end
              record_other_tokens(new_range(token_number, token_range:stop(), INCLUSIVE, #tokens))
              token_number = next_token_number
              goto continue
            end
            next_token = tokens[next_token_number]
            next_token_type, _, next_catcode, next_byte_range = table.unpack(next_token)
            if ignored_token_number ~= nil and next_token_number == ignored_token_number then
              next_token_number = next_token_number + 1
              goto check_token
            end
            if lpeg.match(parsers.parameter_argument_specifier, argument_specifier) then
              parameter_text_start_token_number = next_token_number  -- a "TeX parameter" argument specifier, try to collect parameter text
              while next_token_number <= token_range:stop() do
                next_token = tokens[next_token_number]
                next_token_type, _, next_catcode, next_byte_range = table.unpack(next_token)
                if next_token_type == CHARACTER and next_catcode == 2 then  -- end grouping, skip the control sequence
                  if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                    csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                    goto retry_control_sequence
                  else
                    issues:add('e300', 'unexpected function call argument', next_byte_range)
                    goto skip_other_token
                  end
                elseif next_token_type == CHARACTER and next_catcode == 1 then  -- begin grouping, record the parameter text
                  next_token_number = next_token_number - 1
                  table.insert(arguments, new_range(parameter_text_start_token_number, next_token_number, INCLUSIVE + MAYBE_EMPTY, #tokens))
                  break
                end
                next_token_number = next_token_number + 1
              end
              if next_token_number > token_range:stop() then  -- missing begin grouping (partial application?), skip all remaining tokens
                if token_range:stop() == #tokens then
                  if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                    csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                    goto retry_control_sequence
                  else
                    issues:add('e301', 'end of expl3 part within function call', next_byte_range)
                  end
                end
                record_other_tokens(new_range(token_number, token_range:stop(), INCLUSIVE, #tokens))
                token_number = next_token_number
                goto continue
              end
            elseif lpeg.match(parsers.N_type_argument_specifier, argument_specifier) then  -- an N-type argument specifier
              if next_token_type == CHARACTER and next_catcode == 1 then  -- begin grouping, try to collect the balanced text
                next_grouping = groupings[next_token_number]
                assert(next_grouping ~= nil)
                assert(next_grouping.start == next_token_number)
                if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                  if token_range:stop() == #tokens then
                    if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                      csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                      goto retry_control_sequence
                    else
                      issues:add('e301', 'end of expl3 part within function call', next_byte_range)
                    end
                  end
                  goto skip_other_token
                else  -- a balanced text
                  next_token_range = new_range(next_grouping.start + 1, next_grouping.stop - 1, INCLUSIVE + MAYBE_EMPTY, #tokens)
                  if #next_token_range == 1 then  -- a single token, record it
                      issues:add('w303', 'braced N-type function call argument', next_byte_range)
                      table.insert(arguments, next_token_range)
                      next_token_number = next_grouping.stop
                  elseif #next_token_range == 2 and  -- two tokens
                      tokens[next_token_range:start()][1] == CHARACTER and tokens[next_token_range:start()][3] == 6 and  -- a parameter
                      tokens[next_token_range:stop()][1] == CHARACTER and  -- followed by a digit (unrecognized parameter/replacement text?)
                      lpeg.match(parsers.decimal_digit, tokens[next_token_range:stop()][2]) then
                    record_other_tokens(new_range(token_number, next_grouping.stop, INCLUSIVE, #tokens))
                    token_number = next_grouping.stop + 1
                    goto continue
                  else  -- no token / more than one token, skip the control sequence
                    if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                      csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                      goto retry_control_sequence
                    else
                      issues:add('e300', 'unexpected function call argument', next_byte_range)
                      goto skip_other_token
                    end
                  end
                end
              elseif next_token_type == CHARACTER and next_catcode == 2 then  -- end grouping (partial application?), skip all tokens
                record_other_tokens(new_range(token_number, next_token_number, EXCLUSIVE, #tokens))
                token_number = next_token_number
                goto continue
              else
                if next_token_type == CHARACTER and next_catcode == 6 then  -- a parameter
                  if next_token_number + 1 <= token_range:stop() then  -- followed by one other token
                    if tokens[next_token_number + 1][1] == CHARACTER and  -- that is a digit (unrecognized parameter/replacement text?)
                        lpeg.match(parsers.decimal_digit, tokens[next_token_number + 1][2]) then  -- skip all tokens
                      record_other_tokens(new_range(token_number, next_token_number + 1, INCLUSIVE, #tokens))
                      token_number = next_token_number + 2
                      goto continue
                    end
                  end
                end
                -- an N-type argument, record it
                table.insert(arguments, new_range(next_token_number, next_token_number, INCLUSIVE, #tokens))
              end
            elseif lpeg.match(parsers.n_type_argument_specifier, argument_specifier) then  -- an n-type argument specifier
              if next_token_type == CHARACTER and next_catcode == 1 then  -- begin grouping, try to collect the balanced text
                next_grouping = groupings[next_token_number]
                assert(next_grouping ~= nil)
                assert(next_grouping.start == next_token_number)
                if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                  if token_range:stop() == #tokens then
                    if csname ~= original_csname then  -- before recording an error, retry without trying to understand non-expl3
                      csname, next_token_number, ignored_token_number = original_csname, token_number + 1, nil
                      goto retry_control_sequence
                    else
                      issues:add('e301', 'end of expl3 part within function call', next_byte_range)
                    end
                  end
                  goto skip_other_token
                else  -- a balanced text, record it
                  table.insert(arguments, new_range(next_grouping.start + 1, next_grouping.stop - 1, INCLUSIVE + MAYBE_EMPTY, #tokens))
                  next_token_number = next_grouping.stop
                end
              elseif next_token_type == CHARACTER and next_catcode == 2 then  -- end grouping (partial application?), skip all tokens
                record_other_tokens(new_range(token_number, next_token_number, EXCLUSIVE, #tokens))
                token_number = next_token_number
                goto continue
              else  -- not begin grouping
                if next_token_type == CHARACTER and next_catcode == 6 then  -- a parameter
                  if next_token_number + 1 <= token_range:stop() then  -- followed by one other token
                    if tokens[next_token_number + 1][1] == CHARACTER and  -- that is a digit (unrecognized parameter/replacement text?)
                        lpeg.match(parsers.decimal_digit, tokens[next_token_number + 1][2]) then  -- skip all tokens
                      record_other_tokens(new_range(token_number, next_token_number + 1, INCLUSIVE, #tokens))
                      token_number = next_token_number + 2
                      goto continue
                    end
                  end
                end
                -- an unbraced n-type argument, record it
                issues:add('w302', 'unbraced n-type function call argument', next_byte_range)
                table.insert(arguments, new_range(next_token_number, next_token_number, INCLUSIVE, #tokens))
              end
            else
              error('Unexpected argument specifier "' .. argument_specifier .. '"')
            end
            next_token_number = next_token_number + 1
          end
          table.insert(calls, {CALL, new_range(token_number, next_token_number, EXCLUSIVE, #tokens), csname, arguments})
          token_number = next_token_number
          goto continue
        else  -- a non-expl3 control sequence, skip it
          goto skip_other_token
        end
      elseif token_type == CHARACTER then  -- an ordinary character
        if payload == "=" then  -- an equal sign
          if token_number + 2 <= token_range:stop() then  -- followed by two other tokens
            if tokens[token_number + 1][1] == CONTROL_SEQUENCE then  -- the first being a control sequence
              if tokens[token_number + 2][1] == CHARACTER and tokens[token_number + 2][2] == "," then  -- and the second being a comma
                -- (probably l3keys definition?), skip all three tokens
                record_other_tokens(new_range(token_number, token_number + 2, INCLUSIVE, #tokens))
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
      record_other_tokens(new_range(token_number, token_number, INCLUSIVE, #tokens))
      token_number = token_number + 1
      ::continue::
    end
    return calls
  end

  local calls = {}
  for part_number, part_tokens in ipairs(results.tokens) do
    local part_groupings = results.groupings[part_number]
    local part_token_range = new_range(1, #part_tokens, INCLUSIVE, #part_tokens)
    local part_calls = get_calls(part_tokens, part_token_range, part_groupings)
    table.insert(calls, part_calls)
  end

  -- Store the intermediate results of the analysis.
  results.calls = calls
end

return {
  process = syntactic_analysis,
  call_types = call_types
}
