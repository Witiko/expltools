local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")

local filename = "t422-02.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local options = {expl3_detection_strategy = "always", ignored_issues = {"s413"}}
local issues = new_issues(filename, options)
local results = {}

preprocessing.process(filename, content, issues, results, options)
lexical_analysis.process(filename, content, issues, results, options)
syntactic_analysis.process(filename, content, issues, results, options)
semantic_analysis.process(filename, content, issues, results, options)

assert(#issues.errors == 4)
assert(#issues.warnings == 0)

local expected_line_numbers = {{7, 8}, {11, 12}, {13, 14}, {15, 16}}
for index, err in ipairs(issues.sort(issues.errors)) do
  assert(err[1] == "t422")
  assert(err[2] == "using a variable of an incompatible type")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
end
