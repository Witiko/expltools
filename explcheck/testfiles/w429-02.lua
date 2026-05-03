local sort_issues = require("explcheck-issues").sort_issues
local utils = require("explcheck-utils")

local filename = "w429-02.tex"
local options = {
  expl3_detection_strategy = "always",
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 0)
assert(#issues.warnings == 3)

local expected_line_numbers = {{1, 9}, {1, 9}, {1, 9}}
local expected_contexts = {[[\example_unexpandable:F]], [[\example_unexpandable:T]], [[\example_unexpandable:TF]]}
for index, warning in ipairs(sort_issues(issues.warnings)) do
  assert(warning[1] == "w429")
  assert(warning[2] == "defined an unexpandable function as unprotected")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
  assert(warning[4] == expected_contexts[index])
end
