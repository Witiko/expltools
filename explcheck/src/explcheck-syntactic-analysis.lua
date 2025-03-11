-- The syntactic analysis step of static analysis converts TeX tokens into a tree of function calls.

local new_range = require("explcheck-ranges")
local parsers = require("explcheck-parsers")

local lpeg = require("lpeg")

-- Convert the content to a tree of function calls an register any issues.
local function syntactic_analysis(pathname, content, issues, results, options)  -- luacheck: ignore pathname content options

  -- Extract function calls from TeX tokens and groupings.
  local function get_calls(tokens, token_range, groupings)
    local calls = {}
    if #token_range == 0 then
      return calls
    end
    local token_number = token_range:start()
    while token_number <= token_range:stop() do
      local token = tokens[token_number]
      local token_type, payload, catcode, byte_range = table.unpack(token)  -- luacheck: ignore catcode byte_range
      if token_type == "control sequence" then  -- a control sequence, try to extract a call
        local csname = payload
        local _, _, argument_specifiers = csname:find(":([^:]*)")
        if argument_specifiers ~= nil and lpeg.match(parsers.argument_specifiers, argument_specifiers) ~= nil then
          local call = {new_range(token_number, token_number, "inclusive", #tokens)}
          local arguments = {}
          local next_token_number = token_number + 1
          local next_token, next_token_type, next_payload, next_catcode, next_byte_range  -- luacheck: ignore next_payload
          local next_grouping
          for argument_specifier in argument_specifiers:gmatch(".") do  -- an expl3 control sequence, try to collect the arguments
            if lpeg.match(parsers.parameter_argument_specifier, argument_specifier) then
              token_number = token_number + 1  -- a "TeX parameter" argument specifier, skip the control sequence
              goto skip
            elseif lpeg.match(parsers.weird_argument_specifier, argument_specifier) then
              token_number = token_number + 1  -- a "weird" argument specifier, skip the control sequence
              goto skip
            elseif lpeg.match(parsers.do_not_use_argument_specifier, argument_specifier) then
              token_number = token_number + 1  -- a "do not use" argument specifier, skip the control sequence
              goto skip
            end
            if next_token_number > token_range:stop() then
              token_number = token_number + 1  -- a missing argument (partial application?), skip the control sequence
              goto skip
            end
            next_token = tokens[next_token_number]
            next_token_type, next_payload, next_catcode, next_byte_range = table.unpack(next_token)
            if lpeg.match(parsers.N_type_argument_specifier, argument_specifier) then  -- an N-type argument specifier
              if next_token_type == "character" and next_catcode == 1 then  -- begin grouping, skip the control sequence
                issues:add('e300', 'unexpected function call argument', next_byte_range)
                token_number = token_number + 1
                goto skip
              else  -- an N-type argument, record it
                table.insert(arguments, new_range(next_token_number, next_token_number, "inclusive", #tokens))
              end
            elseif lpeg.match(parsers.n_type_argument_specifier, argument_specifier) then  -- an n-type argument specifier
              if next_token_type == "character" and next_catcode == 1 then  -- an n-type argument, try to collect the balanced text
                next_grouping = groupings[next_token_number]
                assert(next_grouping ~= nil)
                assert(next_grouping.start == next_token_number)
                if next_grouping.stop == nil then  -- an unclosed grouping, skip the control sequence
                  token_number = token_number + 1
                  goto skip
                else  -- a balanced text, record it
                  table.insert(arguments, new_range(next_grouping.start, next_grouping.stop, "inclusive", #tokens))
                  next_token_number = next_grouping.stop
                end
              else  -- not begin grouping, skip the control sequence
                issues:add('e300', 'unexpected function call argument', next_byte_range)
                token_number = token_number + 1
                goto skip
              end
            else
              error('Unexpected argument specifier "' .. argument_specifier .. '"')
            end
            next_token_number = next_token_number + 1
          end
          table.insert(call, arguments)
          table.insert(calls, call)
          token_number = next_token_number
          ::skip::
        else  -- a non-expl3 control sequence, skip it
          token_number = token_number + 1
        end
      elseif token_type == "character" then  -- an ordinary character, skip it
        token_number = token_number + 1
      else
        error('Unexpected token type "' .. token_type .. '"')
      end
    end
    return calls
  end

  local calls = {}
  for part_number, part_tokens in ipairs(results.tokens) do
    local part_groupings = results.groupings[part_number]
    local part_token_range = new_range(1, #part_tokens, "inclusive", #part_tokens)
    local part_calls = get_calls(part_tokens, part_token_range, part_groupings)
    table.insert(calls, part_calls)
  end

  -- Store the intermediate results of the analysis.
  results.calls = calls
end

return syntactic_analysis
