local new_issues = require("explcheck-issues")
local format = require("explcheck-format")
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
for index, warning in ipairs(issues:sort(issues.warnings)) do
  assert(warning[1] == "w101")
  assert(warning[2] == "unexpected delimiters")
  local range_start_byte_number, range_end_byte_number = table.unpack(warning[3])
  local range_start_line_number = format.convert_byte_to_line_and_column(
    line_starting_byte_numbers,
    range_start_byte_number
  )
  local range_end_line_number = format.convert_byte_to_line_and_column(
    line_starting_byte_numbers,
    range_end_byte_number - 1
  )
  assert(range_start_line_number == expected_line_numbers[index])
  assert(range_end_line_number == expected_line_numbers[index])
end
