local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")

local filename = "e102-03.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()

local line_starting_byte_numbers = preprocessing(issues, filename, content)

assert(#issues.errors == 3)
assert(#issues.warnings == 0)

local expected_line_numbers = {3, 5, 7}
for index, err in ipairs(issues.sort(issues.errors)) do
  assert(err[1] == "e102")
  assert(err[2] == "expl3 material in non-expl3 parts")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
