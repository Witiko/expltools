local sort_issues = require("explcheck-issues").sort_issues
local utils = require("explcheck-utils")

local filename = "e420.tex"
local options = {
  expl3_detection_strategy = "always",
  ignored_issues = {"s412", "s413", "w415"},
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 1)
assert(#issues.warnings == 0)

local expected_line_numbers = {{7, 7}}
for index, err in ipairs(sort_issues(issues.errors)) do
  assert(err[1] == "e420")
  assert(err[2] == "locally setting a global variable")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
end
