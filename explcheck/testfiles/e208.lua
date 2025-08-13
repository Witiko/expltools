local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")

local filename = "e208.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local options = {expl3_detection_strategy = "always", ignored_issues = {'s206'}}
local issues = new_issues(filename, options)
local results = {}

preprocessing.process(filename, content, issues, results, options)
lexical_analysis.process(filename, content, issues, results, options)

assert(#issues.errors == 1)
assert(#issues.warnings == 0)

local expected_line_numbers = {5}
for index, err in ipairs(issues.sort(issues.errors)) do
  assert(err[1] == "e208")
  assert(err[2] == "too many closing braces")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
