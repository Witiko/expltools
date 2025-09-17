local sort_issues = require("explcheck-issues").sort_issues
local utils = require("explcheck-utils")

local filename = "t422-06.tex"
local options = {
  expl3_detection_strategy = "always",
  ignored_issues = {"s413"},
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 5)
assert(#issues.warnings == 0)

local expected_line_numbers = {{5, 6}, {7, 8}, {11, 12}, {13, 14}, {15, 16}}
for index, err in ipairs(sort_issues(issues.errors)) do
  assert(err[1] == "t422")
  assert(err[2] == "using a variable of an incompatible type")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
end
