local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")

local filename = "e304.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local results = {}
local options = {expl3_detection_strategy = "always"}

preprocessing.process(filename, content, issues, results, options)
lexical_analysis.process(filename, content, issues, results, options)
syntactic_analysis.process(filename, content, issues, results, options)

assert(#issues.errors == 1)

local expected_line_numbers = {3}
for index, err in ipairs(issues.sort(issues.errors)) do
  assert(err[1] == "e304")
  assert(err[2] == "unexpected parameter number")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
