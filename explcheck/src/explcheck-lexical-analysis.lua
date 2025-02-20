-- The lexical analysis step of static analysis converts expl3 parts of the input files into TeX tokens.

local parsers = require("explcheck-parsers")
local obsolete = require("explcheck-obsolete")
local new_range = require("explcheck-ranges")
local utils = require("explcheck-utils")

local lpeg = require("lpeg")

-- Tokenize the content and register any issues.
local function lexical_analysis(issues, all_content, expl_ranges, seems_like_latex_style_file, options)

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
    local content = all_content:sub(range:start(), range:stop())
    for _, line in ipairs(lpeg.match(parsers.tex_lines, content)) do
      local line_start, line_text, line_end = table.unpack(line)
      local line_range = new_range(line_start, line_end, "exclusive", #all_content)
      local map_back = (function(line_text, line_range)  -- luacheck: ignore line_text line_range
        return function (index)
          assert(index > 0)
          assert(index <= #line_text + #parsers.expl3_endlinechar)
          if index <= #line_text then
            local mapped_index = range:start() + line_range:start() + index - 2  -- a line character
            assert(line_text[index] == content[mapped_index])
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

  -- Tokenize a line, similarly to TeX's token processor (TeX's "mouth" [1]).
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
    local state
    local num_open_groups_upper_estimate = 0

    -- Determine the category code of the at sign ("@").
    local make_at_letter = utils.get_option(options, "make_at_letter")
    if make_at_letter == "auto" then
      make_at_letter = seems_like_latex_style_file
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
        local range = new_range(character_index, character_index, "inclusive", #line_text, map_back, #all_content)
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
                and (previous_catcode ~= 0 or #previous_csname > 1 and lpeg.match(parsers.non_expl3_csname, previous_csname) == nil)
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
          range = new_range(character_index, previous_csname_index, "inclusive", #line_text, map_back, #all_content)
          table.insert(tokens, {"control sequence", csname, 0, range})
          if (
                previous_catcode ~= 9 and previous_catcode ~= 10  -- a potential missing stylistic whitespace
                -- do not require whitespace before non-expl3 control sequences or control sequences with empty or one-character names
                and #csname > 1 and lpeg.match(parsers.non_expl3_csname, csname) == nil
              ) then
            issues:add('s204', 'missing stylistic whitespaces', range)
          end
          previous_catcode, previous_csname = 0, csname
          character_index = csname_index
        elseif catcode == 5 then  -- end of line
          if state == "N" then
            table.insert(tokens, {"control sequence", "par", range})
          elseif state == "M" then
            table.insert(tokens, {"character", " ", 10, range})
          end
          character_index = character_index + character_index_increment
        elseif catcode == 9 then  -- ignored character
          previous_catcode = catcode
          character_index = character_index + character_index_increment
        elseif catcode == 10 then  -- space
          if state == "M" then
            table.insert(tokens, {"character", " ", 10, range})
          end
          previous_catcode = catcode
          character_index = character_index + character_index_increment
        elseif catcode == 14 then  -- comment character
          character_index = #line_text + 1
        elseif catcode == 15 then  -- invalid character
          issues:add('e209', 'invalid characters', range)
          character_index = character_index + character_index_increment
        else
          if catcode == 1 or catcode == 2 then  -- begin/end grouping
            if catcode == 1 then
              num_open_groups_upper_estimate = num_open_groups_upper_estimate + 1
            elseif catcode == 2 then
              if num_open_groups_upper_estimate > 0 then
                num_open_groups_upper_estimate = num_open_groups_upper_estimate - 1
              else
                issues:add('e208', 'too many closing braces', range)
              end
            end
            if (
                    previous_catcode ~= 9 and previous_catcode ~= 10  -- a potential missing stylistic whitespace
                    -- do not require whitespace after non-expl3 control sequences or control sequences with empty or one-character names
                    and (previous_catcode ~= 0 or #previous_csname > 1 and lpeg.match(parsers.non_expl3_csname, previous_csname) == nil)
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
          table.insert(tokens, {"character", character, catcode, range})
          state = "M"
          character_index = character_index + character_index_increment
        end
      end
    end
    return tokens
  end

  -- Tokenize the content.
  local all_tokens = {}
  for _, range in ipairs(expl_ranges) do
    local lines = (function()
      local co = coroutine.create(function()
        get_lines(range)
      end)
      return function()
        local _, line_text, map_back = coroutine.resume(co)
        return line_text, map_back
      end
    end)()
    local tokens = get_tokens(lines)
    table.insert(all_tokens, tokens)
  end

  for _, tokens in ipairs(all_tokens) do
    for token_index, token in ipairs(tokens) do
      local token_type, payload, catcode, range = table.unpack(token)  -- luacheck: ignore catcode
      if token_type == "control sequence" then
        local csname = payload
        local _, _, argument_specifiers = csname:find(":(.*)")
        if argument_specifiers ~= nil then
          if lpeg.match(parsers.do_not_use_argument_specifiers, argument_specifiers) then
            issues:add('w200', '"do not use" argument specifiers', range)
          end
          if lpeg.match(parsers.argument_specifiers, argument_specifiers) == nil then
            issues:add('e201', 'unknown argument specifiers', range)
          end
        end
        if lpeg.match(obsolete.deprecated_csname, csname) ~= nil then
          issues:add('w202', 'deprecated control sequences', range)
        end
        if token_index + 1 <= #tokens then
          local next_token = tokens[token_index + 1]
          local next_token_type, next_csname, _, next_range = table.unpack(next_token)
          if next_token_type == "control sequence" then
            if (
                  lpeg.match(parsers.expl3_function_assignment_csname, csname) ~= nil
                  and lpeg.match(parsers.non_expl3_csname, next_csname) == nil
                  and lpeg.match(parsers.expl3_function_csname, next_csname) == nil
                ) then
              issues:add('s205', 'malformed function name', next_range)
            end
            if (
                  lpeg.match(parsers.expl3_variable_or_constant_use_csname, csname) ~= nil
                  and lpeg.match(parsers.non_expl3_csname, next_csname) == nil
                  and lpeg.match(parsers.expl3_scratch_variable_csname, next_csname) == nil
                  and lpeg.match(parsers.expl3_variable_or_constant_csname, next_csname) == nil
                ) then
              issues:add('s206', 'malformed variable or constant name', next_range)
            end
            if (
                  lpeg.match(parsers.expl3_quark_or_scan_mark_definition_csname, csname) ~= nil
                  and lpeg.match(parsers.expl3_quark_or_scan_mark_csname, next_csname) == nil
                ) then
              issues:add('s207', 'malformed quark or scan mark name', next_range)
            end
          end
        end
      end
    end
  end

  return all_tokens
end

return lexical_analysis
