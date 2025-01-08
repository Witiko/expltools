-- The lexical analysis step of static analysis converts expl3 parts of the input files into TeX tokens.

local parsers = require("explcheck-parsers")

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
  [9] = parsers.spacechar,  -- ignored character
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
local function lexical_analysis(issues, content, expl_ranges, options)  -- luacheck: ignore issues options

  -- Process bytes within a given range similarly to TeX's input processor and produce processed lines.
  --
  -- See also:
  -- - Section 31 on page 16 of Knuth (1986) [1]
  -- - Section 7 on page 36 and Section 8 on page 42 of Knuth (1986) [2]
  -- - Section 1.2 on page 12 of Olsak (2001) [3]
  --
  --  [1]: Donald Ervin Knuth. 1986. TeX: The Program. Addison-Wesley, USA.
  --  [2]: Donald Ervin Knuth. 1986. The TeXbook. Addison-Wesley, USA.
  --  [3]: Petr Olsak. 2001. TeXbook naruby. Konvoj, Brno.
  --       https://petr.olsak.net/ftp/olsak/tbn/tbn.pdf
  --
  local function get_lines(content, range)  -- luacheck: ignore content range
    local lines = {}
    -- TODO
    return lines
  end

  -- Tokenize a processed line, similarly to TeX's token processor.
  --
  -- See also:
  -- - Section 7 on page 36 and Section 8 on page 42 of Knuth (1986) [2]
  -- - Section 1.3 on page 19 of Olsak (2001) [3]
  --
  --  [2]: Donald Ervin Knuth. 1986. The TeXbook. Addison-Wesley, USA.
  --  [3]: Petr Olsak. 2001. TeXbook naruby. Konvoj, Brno.
  --       https://petr.olsak.net/ftp/olsak/tbn/tbn.pdf
  --
  local function get_tokens(lines)  -- luacheck: ignore lines
    local tokens = {}
    -- TODO
    return tokens
  end

  local all_tokens = {}
  for _, expl_range in ipairs(expl_ranges) do
    local lines = get_lines(content, expl_range)
    local tokens = get_tokens(lines)
    table.insert(all_tokens, tokens)
  end
  return all_tokens
end

return lexical_analysis
