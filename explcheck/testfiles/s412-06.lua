local utils = require("explcheck-utils")

local filename = "s412-06.tex"
local options = {
  expl3_detection_strategy = "always",
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 0)
assert(#issues.warnings == 1)

local expected_line_numbers = {2}
for index, warning in ipairs(issues.sort(issues.errors)) do
  assert(warning[1] == "s412")
  assert(warning[2] == "malformed function name")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
