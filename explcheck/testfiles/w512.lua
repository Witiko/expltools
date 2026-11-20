local sort_issues = require("explcheck-issues").sort_issues
local utils = require("explcheck-utils")

local filename = "w512.tex"
local options = {
  expl3_detection_strategy = "always",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 0)
assert(#issues.warnings == 1)

local expected_line_numbers = {{14, 16}}
local expected_contexts = {[[\example_also_unexpandable: -> \example_unexpandable: -> \tl_set:Nn]]}
for index, warning in ipairs(sort_issues(issues.warnings)) do
  assert(warning[1] == "w512")
  assert(warning[2] == "defined an unexpandable function as unprotected")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
  assert(warning[4] == expected_contexts[index])
end
