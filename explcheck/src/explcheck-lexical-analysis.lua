-- The lexical analysis step of static analysis converts expl3 parts of the input files into TeX tokens.

local parsers = require("explcheck-parsers")

local lpeg = require("lpeg")
local Cp, Ct, Cs = lpeg.Cp, lpeg.Ct, lpeg.Cs

-- Default expl3 category code table, corresponds to `\c_code_cctab` in expl3
local expl3_endlinechar = ' '  -- luacheck: ignore expl3_endlinechar
local expl3_catcodes = {
  [0] = parsers.backslash,  -- escape character
  [1] = parsers.lbrace,  -- begin grouping
  [2] = parsers.rbrace,  -- end grouping
  [3] = parsers.dollar_sign,  -- math shift
  [4] = parsers.ampersand,  -- alignment tab
  [5] = parsers.newline,  -- end of line
  [6] = parsers.hash_sign,  -- parameter
  [7] = parsers.circumflex,  -- superscript
  [8] = parsers.fail,  -- subscript
  [9] = parsers.space + parsers.tab,  -- ignored character
  [10] = parsers.tilde,  -- space
  [11] = parsers.letter + parsers.colon + parsers.underscore,  -- letter
  [13] = parsers.form_feed,  -- active character
  [14] = parsers.percent_sign,  -- comment character
  [15] = parsers.control_character,  -- invalid character
}
expl3_catcodes[12] = parsers.any  -- other
for catcode, parser in pairs(expl3_catcodes) do
  if catcode ~= 12 then
    expl3_catcodes[12] = expl3_catcodes[12] - parser
  end
end

-- A parser that assigns a category code to a character.
local determine_expl3_catcode = parsers.fail
for catcode, parser in pairs(expl3_catcodes) do
  determine_expl3_catcode = (
    determine_expl3_catcode
    + parser / function() return catcode end
  )
end

-- Tokenize the content and register any issues.
local function lexical_analysis(issues, all_content, expl_ranges, options)  -- luacheck: ignore issues options

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
    local range_start, range_end = table.unpack(range)
    local content = all_content:sub(range_start, range_end - 1)
    local tex_lines = Ct(
      Ct(
        Cp()
        * Cs(parsers.tex_line)
        * Cp()
      )^0
    )
    for _, line in ipairs(lpeg.match(tex_lines, content)) do
      local line_start, line_text, line_end = table.unpack(line)
      local map_back = (function(line_start, line_text, line_end)  -- luacheck: ignore line_start line_text line_end
        return function (index)
          assert(index > 0)
          assert(index <= #line_text + #expl3_endlinechar)
          if index > 0 and index <= #line_text then
            return range_start + line_start + index - 2  -- a line character
          elseif index > #line_text and index <= #line_text + #expl3_endlinechar then
            return range_start + line_end - 2  -- an \endlinechar
          else
            assert(false)
          end
        end
      end)(line_start, line_text, line_end)
      coroutine.yield(line_text .. expl3_endlinechar, map_back)
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
    for line_text, map_back in lines do
      state = "N"
      local character_index = 1

      local function get_character_and_catcode(index)
        assert(character_index <= #line_text)
        local character = line_text:sub(index, index)
        local catcode = lpeg.match(determine_expl3_catcode, character)
        -- TODO: process ^^X, ^^XX, and potentionally other codes supported by Unicode-aware engines
        return character, catcode
      end

      while character_index <= #line_text do
        local character, catcode = get_character_and_catcode(character_index)
        local actual_character_index = map_back(character_index)
        if catcode == 0 then  -- control sequence
          local csname_table = {}
          local csname_index = character_index + 1
          if csname_index <= #line_text then
            character, catcode = get_character_and_catcode(csname_index)
            table.insert(csname_table, character)
            csname_index = csname_index + 1
            if catcode == 11 then  -- control word
              state = "S"
              while csname_index <= #line_text do
                character, catcode = get_character_and_catcode(csname_index)
                if catcode == 11 then
                  table.insert(csname_table, character)
                  csname_index = csname_index + 1
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
          table.insert(tokens, {"control_sequence", csname, 0, actual_character_index})
          character_index = csname_index
        elseif catcode == 5 then  -- end of line
          if state == "N" then
            table.insert(tokens, {"control_sequence", "par", actual_character_index})
          elseif state == "M" then
            table.insert(tokens, {"character", " ", 10, actual_character_index})
          end
          character_index = character_index + 1
        elseif catcode == 9 then  -- ignored character
          character_index = character_index + 1
        elseif catcode == 10 then  -- space
          if state == "M" then
            table.insert(tokens, {"character", " ", 10, actual_character_index})
          end
          character_index = character_index + 1
        elseif catcode == 14 then  -- comment character
          character_index = #line_text + 1
        elseif catcode == 15 then  -- invalid character
          -- TODO: register an error
          character_index = character_index + 1
        else  -- regular character
          table.insert(tokens, {"character", character, catcode, actual_character_index})
          state = "M"
          character_index = character_index + 1
        end
      end
    end
    return tokens
  end

  -- Tokenize the content.
  local all_tokens = {}
  for _, expl_range in ipairs(expl_ranges) do
    local lines = (function()
      local co = coroutine.create(function()
        get_lines(expl_range)
      end)
      return function()
        local _, line_text, map_back = coroutine.resume(co)
        return line_text, map_back
      end
    end)()
    local tokens = get_tokens(lines)
    table.insert(all_tokens, tokens)
  end

  -- TODO: Register any issues.
  for _, tokens in ipairs(all_tokens) do
    for _, token in ipairs(tokens) do
      local token_type, payload, catcode, index = table.unpack(token)
      print(
        '<token type="' .. token_type .. '" catcode="' .. catcode .. '" index="' .. index .. '">'
        .. payload
        .. '</token>'
      )
    end
  end

  return all_tokens
end

return lexical_analysis
