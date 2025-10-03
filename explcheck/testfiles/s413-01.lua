local sort_issues = require("explcheck-issues").sort_issues
local utils = require("explcheck-utils")

local filename = "s413-01.tex"
local options = {
  expl3_detection_strategy = "always",
  ignored_issues = {"w415", "w419"},
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 0)
assert(#issues.warnings == 3)

local expected_line_numbers = {{2, 2}, {4, 4}, {6, 6}}
for index, warning in ipairs(sort_issues(issues.warnings)) do
  assert(warning[1] == "s413")
  assert(warning[2] == "malformed variable or constant name")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
end
