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
local function lexical_analysis(issues, content, expl_ranges, options)  -- luacheck: ignore issues content expl_ranges options

  local tokens = {}

  -- TODO

  return tokens

end

return lexical_analysis
