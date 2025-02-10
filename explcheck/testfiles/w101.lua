local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")

local filename = "w101.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()

local line_starting_byte_numbers = preprocessing(issues, content)

assert(#issues.errors == 0)
assert(#issues.warnings == 2)

local expected_line_numbers = {2, 9}
for index, warning in ipairs(issues.sort(issues.warnings)) do
  assert(warning[1] == "w101")
  assert(warning[2] == "unexpected delimiters")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
