-- The TeX comment removal part for the preprocessing step of static analysis.

local lpeg = require("lpeg")
local P, S, Cp, Ct = lpeg.P, lpeg.S, lpeg.Cp, lpeg.Ct

-- Define base parsers.
---- Generic
local any = P(1)

---- Tokens
local percent_sign = P("%")
local backslash = P([[\]])

---- Spacing
local spacechar = S("\t ")
local optional_spaces = spacechar^0
local newline = (
  P("\n")
  + P("\r\n")
  + P("\r")
)
local linechar = any - newline
local line = linechar^0 * newline
local blank_line = optional_spaces * newline

-- Define intermediate parsers.
local commented_line_letter = (
  linechar
  + newline
  - backslash
  - percent_sign
)
local commented_line = (
  (
    (
      commented_line_letter
      - newline
    )^1  -- initial state
    + (
      backslash  -- even backslash
      * (
        backslash
        + #newline
      )
    )^1
    + (
      backslash
      * (
        percent_sign
        + commented_line_letter
      )
    )
  )^0
  * (
    #percent_sign
    * Cp()
    * (
      (
        percent_sign  -- comment
        * linechar^0
        * Cp()
        * newline
        * #blank_line  -- blank line
      )
      + percent_sign  -- comment
      * linechar^0
      * Cp()
      * newline
      * optional_spaces  -- leading spaces
    )
    + newline
  )
)

-- Strip TeX comments from a text. Besides the transformed text, also return
-- a function that maps positions in the transformed text back to the original
-- text.
local function strip_comments(text)
  local transformed_index = 0
  local numbers_of_bytes_removed = {}
  local transformed_text_table = {}
  for index, text_position in ipairs(lpeg.match(Ct(commented_line^1), text)) do
    local span_size = text_position - transformed_index - 1
    if span_size > 0 then
      if index % 2 == 1 then  -- chunk of text
        table.insert(transformed_text_table, text:sub(transformed_index + 1, text_position - 1))
      else  -- comment
        table.insert(numbers_of_bytes_removed, {transformed_index, span_size})
      end
      transformed_index = transformed_index + span_size
    end
  end
  table.insert(transformed_text_table, text:sub(transformed_index + 1, -1))
  local transformed_text = table.concat(transformed_text_table, "")
  local function map_back(index)
    for _, where_and_number_of_bytes_removed in ipairs(numbers_of_bytes_removed) do
      local where, number_of_bytes_removed = table.unpack(where_and_number_of_bytes_removed)
      if index > where then
        index = index + number_of_bytes_removed
      else
        break
      end
    end
    return index
  end
  return transformed_text, map_back
end

return strip_comments
