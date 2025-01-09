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
  [8] = parsers.underscore,  -- subscript
  [9] = parsers.space + parsers.tab,  -- ignored character
  [10] = parsers.tilde,  -- space
  [11] = parsers.letter + parsers.colon,  -- letter
  [12] = parsers.punctuation + parsers.digit,  -- other
  [13] = parsers.form_feed,  -- active character
  [14] = parsers.percent_sign,  -- comment character
  [15] = parsers.control_character,  -- invalid character
}
for catcode, parser in pairs(expl3_catcodes) do
  if catcode ~= 12 then
    expl3_catcodes[12] = expl3_catcodes[12] - parser
  end
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
    for line_text, map_back in lines do
      print("<line start=\"" .. tostring(map_back(1)) .. "\">" .. line_text .. "</line>")
      -- TODO
    end
    return tokens
  end

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
  return all_tokens
end

return lexical_analysis
