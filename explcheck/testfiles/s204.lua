local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")

local filename = "s204.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local options = {expect_expl3_everywhere = true}

local line_starting_byte_numbers, expl_ranges = preprocessing(issues, content, options)
lexical_analysis(issues, content, expl_ranges, options)

assert(#issues.errors == 0)
assert(#issues.warnings == 5)

local expected_line_numbers = {3, 5, 5, 5, 5}
for index, warning in ipairs(issues.sort(issues.warnings)) do
  assert(warning[1] == "s204")
  assert(warning[2] == "missing stylistic whitespaces")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
