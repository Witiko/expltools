local utils = require("explcheck-utils")

local filename = "e300-02.tex"
local options = {
  expl3_detection_strategy = "always",
  stop_after = "syntactic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 1)

local expected_line_numbers = {2}
for index, err in ipairs(issues.sort(issues.errors)) do
  assert(err[1] == "e300")
  assert(err[2] == "unexpected function call argument")
  local byte_range = err[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
