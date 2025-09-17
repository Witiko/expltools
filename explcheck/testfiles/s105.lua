local utils = require("explcheck-utils")

local filename = "s105.tex"
local options = {
  stop_after = "preprocessing",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 0)
assert(#issues.warnings == 1)

local expected_line_numbers = {2}
for index, warning in ipairs(issues.sort(issues.warnings)) do
  assert(warning[1] == "s105")
  assert(warning[2] == "needlessly ignored issue")
  local byte_range = warning[3]
  local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
  local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
  assert(start_line_number == expected_line_numbers[index])
  assert(end_line_number == expected_line_numbers[index])
end
