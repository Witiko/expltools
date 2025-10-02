-- The lexical analysis step of static analysis converts expl3 parts of the input files into TeX tokens.

local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local obsolete = require("explcheck-latex3").obsolete
local parsers = require("explcheck-parsers")

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE

local lpeg = require("lpeg")

local token_types = {
  CONTROL_SEQUENCE = "control sequence",
  CHARACTER = "character",
  ARGUMENT = "argument",  -- corresponds to zero or more tokens inserted by a function call, never produced by lexical analysis
}

local CONTROL_SEQUENCE = token_types.CONTROL_SEQUENCE
local CHARACTER = token_types.CHARACTER
local ARGUMENT = token_types.ARGUMENT

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

-- Determine whether a token constitutes "simple text" [1, p. 383] with no expected side effects.
--
--  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
--
local function is_token_simple(token)
  if token.type == CONTROL_SEQUENCE or token.type == ARGUMENT then
    return false
  elseif token.type == CHARACTER then
    return simple_text_catcodes[token.catcode] ~= nil
  else
    error('Unexpected token type "' .. token.type .. '"')
  end
end

-- Get the byte range for a given token.
local function get_token_byte_range(tokens)
  return function(token_number)
    local byte_range = tokens[token_number].byte_range
    return byte_range
  end
end

-- Convert a token range to a corresponding byte range.
local function get_token_range_to_byte_range(tokens, num_bytes)
  local byte_range_getter = get_token_byte_range(tokens)
  local function token_range_to_byte_range(token_range)
    return token_range:new_range_from_subranges(byte_range_getter, num_bytes)
  end
  return token_range_to_byte_range
end

-- Format a control sequence name as it appears in expl3 code.
local function format_csname(csname)
  return string.format("\\%s", csname)
end

-- Format a token as it appears in expl3 code.
local function format_token(token, content)
  assert(#token.byte_range > 0)
  return content:sub(token.byte_range:start(), token.byte_range:stop())
end

-- Format a range of tokens as they appear in expl3 code.
local function format_tokens(token_range, tokens, content)
  if token_range == 0 then
    return ""
  end
  local byte_range = token_range:new_range_from_subranges(get_token_byte_range(tokens), #content)
  return content:sub(byte_range:start(), byte_range:stop())
end

-- Determine whether the lexical analysis step is too confused by the results
-- of the previous steps to run.
local function is_confused(_, results, _)
  if #results.expl_ranges == 0 then
    return true, "no expl3 material was detected"
  end
  return false
end

-- Tokenize the content.
local function analyze(states, file_number, options)

  local state = states[file_number]

  local pathname = state.pathname
  local content = state.content
  local issues = state.issues
  local results = state.results

  -- Process bytes within a given range similarly to TeX's input processor (TeX's "eyes" [1]) and produce lines.
  --
  -- See also:
  -- - Section 31 on page 16 and Section 362 on page 142 of Knuth (1986) [1]
  -- - Section 7 on page 36 and Section 8 on page 42 of Knuth (1986) [2]
  -- - Section 1.2 on page 12 of Olsak (2001) [3]
  --
  --  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
  --  [2]: Donald Ervin Knuth. 1986. The TeXbook. Addison-Wesley, USA.
  --  [3]: Petr Olsak. 2001. TeXbook naruby. Konvoj, Brno.
  --       https://petr.olsak.net/ftp/olsak/tbn/tbn.pdf
  --
  local function get_lines(range)
    local range_content = content:sub(range:start(), range:stop())
    for _, line in ipairs(lpeg.match(parsers.tex_lines, range_content)) do
      local line_start, line_text, line_end = table.unpack(line)
      local line_range = new_range(line_start, line_end, EXCLUSIVE, #content)
      local map_back = (function(line_text, line_range)  -- luacheck: ignore line_text line_range
        return function (index)
          assert(index > 0)
          assert(index <= #line_text + #parsers.expl3_endlinechar)
          if index <= #line_text then
            local mapped_index = range:start() + line_range:start() + index - 2  -- a line character
            assert(line_text[index] == range_content[mapped_index])
            return mapped_index
          elseif index > #line_text and index <= #line_text + #parsers.expl3_endlinechar then
            return math.max(1, range:start() + line_range:start() + #line_text - 2)  -- an \endlinechar
          else
            assert(false)
          end
        end
      end)(line_text, line_range)
      coroutine.yield(line_text .. parsers.expl3_endlinechar, map_back)
    end
  end

  -- Process lines similarly to TeX's token processor (TeX's "mouth" [1]) and produce tokens and a tree of apparent TeX groupings.
  --
  -- See also:
  -- - Section 303 on page 122 of Knuth (1986) [1]
  -- - Section 7 on page 36 and Section 8 on page 42 of Knuth (1986) [2]
  -- - Section 1.3 on page 19 of Olsak (2001) [3]
  --
  --  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
  --  [2]: Donald Ervin Knuth. 1986. The TeXbook. Addison-Wesley, USA.
  --  [3]: Petr Olsak. 2001. TeXbook naruby. Konvoj, Brno.
  --       https://petr.olsak.net/ftp/olsak/tbn/tbn.pdf
  --
  local function get_tokens(lines)
    local tokens = {}

    local groupings = {}
    local current_grouping = groupings
    local parent_grouping

    local num_invalid_characters = 0

    local state  -- luacheck: ignore state

    -- Determine the category code of the at sign ("@").
    local make_at_letter = get_option("make_at_letter", options, pathname)
    if make_at_letter == "auto" then
      make_at_letter = results.seems_like_latex_style_file
    end

    for line_text, map_back in lines do
      state = "N"
      local character_index = 1

      local function determine_expl3_catcode(character)
        local catcode
        if character == "@" then
          if make_at_letter then
            catcode = 11  -- letter
          else
            catcode = 12  -- other
          end
        else
          catcode = lpeg.match(parsers.determine_expl3_catcode, character)
        end
        return catcode
      end

      local function get_character_and_catcode(index)
        assert(index <= #line_text)
        local character = line_text:sub(index, index)
        local catcode = determine_expl3_catcode(character)
        -- Process TeX' double circumflex convention (^^X and ^^XX).
        local actual_character, index_increment = lpeg.match(parsers.double_superscript_convention, line_text, index)
        if actual_character ~= nil then
          local actual_catcode = determine_expl3_catcode(actual_character)
          return actual_character, actual_catcode, index_increment  -- double circumflex convention
        else
          return character, catcode, 1  -- single character
        end
      end

      local previous_catcode, previous_csname = 9, nil
      while character_index <= #line_text do
        local character, catcode, character_index_increment = get_character_and_catcode(character_index)
        local range = new_range(character_index, character_index, INCLUSIVE, #line_text, map_back, #content)
        if (
              catcode ~= 9 and catcode ~= 10  -- a potential missing stylistic whitespace
              and (
                previous_catcode == 0  -- right after a control sequence
                or previous_catcode == 1 or previous_catcode == 2  -- or a begin/end grouping
              )
            ) then
          if (previous_catcode == 0) then
            assert(previous_csname ~= nil)
          end
          if (
                catcode ~= 0 and catcode ~= 1 and catcode ~= 2  -- for a control sequence or begin/end grouping, we handle this elsewhere
                -- do not require whitespace after non-expl3 control sequences or control sequences with empty or one-character names
                and (previous_catcode ~= 0 or #previous_csname > 1 and lpeg.match(parsers.expl3like_csname, previous_csname) ~= nil)
                and (previous_catcode ~= 0 or character ~= ",")  -- allow a comma after a control sequence without whitespace in between
                and (previous_catcode ~= 1 or catcode ~= 6)  -- allow a parameter after begin grouping without whitespace in between
                and (previous_catcode ~= 2 or character ~= ",")  -- allow a comma after end grouping without whitespace in between
              ) then
            issues:add('s204', 'missing stylistic whitespaces', range)
          end
        end
        if catcode == 0 then  -- control sequence
          local csname_table = {}
          local csname_index = character_index + character_index_increment
          local previous_csname_index = csname_index
          if csname_index <= #line_text then
            local csname_index_increment
            character, catcode, csname_index_increment = get_character_and_catcode(csname_index)
            table.insert(csname_table, character)
            csname_index = csname_index + csname_index_increment
            if catcode == 11 then  -- control word
              state = "S"
              while csname_index <= #line_text do
                character, catcode, csname_index_increment = get_character_and_catcode(csname_index)
                if catcode == 11 then
                  table.insert(csname_table, character)
                  previous_csname_index = csname_index
                  csname_index = csname_index + csname_index_increment
                else
                  break
                end
              end
            elseif catcode == 10 then  -- escaped space
              state = "S"
            else  -- control symbol
              state = "M"
            end
          end
          local csname = table.concat(csname_table)
          range = new_range(character_index, previous_csname_index, INCLUSIVE, #line_text, map_back, #content)
          table.insert(tokens, {
            type = CONTROL_SEQUENCE,
            payload = csname,
            catcode = 0,
            byte_range = range,
          })
          if (
                previous_catcode ~= 9 and previous_catcode ~= 10  -- a potential missing stylistic whitespace
                -- do not require whitespace before non-expl3 control sequences or control sequences with empty or one-character names
                and #csname > 1 and lpeg.match(parsers.expl3like_csname, csname) ~= nil
              ) then
            issues:add('s204', 'missing stylistic whitespaces', range)
          end
          previous_catcode, previous_csname = 0, csname
          character_index = csname_index
        elseif catcode == 5 then  -- end of line
          if state == "N" then
            table.insert(tokens, {
              type = CONTROL_SEQUENCE,
              payload = "par",
              catcode = 0,
              byte_range = range,
            })
          elseif state == "M" then
            table.insert(tokens, {
              type = CHARACTER,
              payload = " ",
              catcode = 10,
              byte_range = range,
            })
          end
          character_index = character_index + character_index_increment
        elseif catcode == 9 then  -- ignored character
          previous_catcode = catcode
          character_index = character_index + character_index_increment
        elseif catcode == 10 then  -- space
          if state == "M" then
            table.insert(tokens, {
              type = CHARACTER,
              payload = " ",
              catcode = 10,
              byte_range = range,
            })
          end
          previous_catcode = catcode
          character_index = character_index + character_index_increment
        elseif catcode == 14 then  -- comment character
          character_index = #line_text + 1
        else
          if catcode == 15 then  -- invalid character
            num_invalid_characters = num_invalid_characters + 1
            issues:add('e209', 'invalid characters', range)
          end
          if catcode == 1 or catcode == 2 then  -- begin/end grouping
            if catcode == 1 then  -- begin grouping
              current_grouping = {parent = current_grouping, start = #tokens + 1}
              assert(groupings[current_grouping.start] == nil)
              assert(current_grouping.parent[current_grouping.start] == nil)
              groupings[current_grouping.start] = current_grouping  -- provide flat access to groupings
              current_grouping.parent[current_grouping.start] = current_grouping  -- provide recursive access to groupings
            elseif catcode == 2 then  -- end grouping
              if current_grouping.parent ~= nil then
                current_grouping.stop = #tokens + 1
                assert(current_grouping.start ~= nil and current_grouping.start < current_grouping.stop)
                parent_grouping = current_grouping.parent
                current_grouping.parent = nil  -- remove a circular reference for the current grouping
                current_grouping = parent_grouping
              else
                issues:add('e208', 'too many closing braces', range)
              end
            end
            if (
                    previous_catcode ~= 9 and previous_catcode ~= 10  -- a potential missing stylistic whitespace
                    -- do not require whitespace after non-expl3 control sequences or control sequences with empty or one-character names
                    and (previous_catcode ~= 0 or #previous_csname > 1 and lpeg.match(parsers.expl3like_csname, previous_csname) ~= nil)
                    and (previous_catcode ~= 1 or catcode ~= 2)  -- allow an end grouping immediately after begin grouping
                    and (previous_catcode ~= 6 or catcode ~= 1 and catcode ~= 2)  -- allow a parameter immediately before grouping
                ) then
              issues:add('s204', 'missing stylistic whitespaces', range)
            end
            previous_catcode = catcode
          elseif (  -- maybe a parameter?
                previous_catcode == 6 and catcode == 12
                and lpeg.match(parsers.decimal_digit, character) ~= nil
              ) then
            previous_catcode = 6
          else  -- some other character
            previous_catcode = catcode
          end
          table.insert(tokens, {
            type = CHARACTER,
            payload = character,
            catcode = catcode,
            byte_range = range,
          })
          state = "M"
          character_index = character_index + character_index_increment
        end
      end
    end
    -- Remove circular references for all unclosed groupings.
    while current_grouping.parent ~= nil do
      parent_grouping = current_grouping.parent
      current_grouping.parent = nil
      current_grouping = parent_grouping
    end
    return tokens, groupings, num_invalid_characters
  end

  -- Tokenize the content.
  local tokens, groupings, num_invalid_characters = {}, {}, 0
  for _, range in ipairs(results.expl_ranges) do
    local lines = (function()
      local co = coroutine.create(function()
        get_lines(range)
      end)
      return function()
        local _, line_text, map_back = coroutine.resume(co)
        return line_text, map_back
      end
    end)()
    local part_tokens, part_groupings, part_num_invalid_characters = get_tokens(lines)
    table.insert(tokens, part_tokens)
    table.insert(groupings, part_groupings)
    num_invalid_characters = num_invalid_characters + part_num_invalid_characters
  end

  -- Store the intermediate results of the analysis.
  results.tokens = tokens
  results.groupings = groupings
  results.num_invalid_characters = num_invalid_characters
end

-- Report any issues.
local function report_issues(states, file_number, options)  -- luacheck: ignore options

  local state = states[file_number]

  local content = state.content
  local issues = state.issues
  local results = state.results

  -- Record issues that are apparent after the lexical analysis.
  for _, part_tokens in ipairs(results.tokens) do
    for _, token in ipairs(part_tokens) do
      if token.type == CONTROL_SEQUENCE then
        local _, _, argument_specifiers = token.payload:find(":([^:]*)")
        if argument_specifiers ~= nil then
          if lpeg.match(parsers.do_not_use_argument_specifiers, argument_specifiers) then
            issues:add('w200', '"do not use" argument specifiers', token.byte_range, format_token(token, content))
          end
          if lpeg.match(parsers.argument_specifiers, argument_specifiers) == nil then
            issues:add('e201', 'unknown argument specifiers', token.byte_range, format_token(token, content))
          end
        end
        if lpeg.match(obsolete.deprecated_csname, token.payload) ~= nil then
          issues:add('w202', 'deprecated control sequences', token.byte_range, format_token(token, content))
        end
      end
    end
  end
end

local substeps = {
  analyze,
  report_issues,
}

return {
  format_csname = format_csname,
  format_token = format_token,
  format_tokens = format_tokens,
  get_token_byte_range = get_token_byte_range,
  get_token_range_to_byte_range = get_token_range_to_byte_range,
  is_confused = is_confused,
  is_token_simple = is_token_simple,
  name = "lexical analysis",
  substeps = substeps,
  token_types = token_types,
}
