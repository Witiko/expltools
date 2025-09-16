local utils = require("explcheck-utils")

local filename = "t422-12.tex"
local options = {
  expl3_detection_strategy = "always",
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 1)
assert(#issues.warnings == 0)

local expected_line_numbers = {{4, 6}}
for index, err in ipairs(issues.sort(issues.errors)) do
  assert(err[1] == "t422")
  assert(err[2] == "using a variable of an incompatible type")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index][1])
  assert(end_line_number == expected_line_numbers[index][2])
end
