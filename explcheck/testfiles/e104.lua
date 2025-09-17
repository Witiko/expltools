local sort_issues = require("explcheck-issues").sort_issues
local utils = require("explcheck-utils")

local filename = "e104.tex"
local options = {
  stop_after = "preprocessing",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues, results = state.issues, state.results

assert(#issues.errors == 1)
assert(#issues.warnings == 0)

local errors = sort_issues(issues.errors)
local err = errors[1]

assert(err[1] == "e104")
assert(err[2] == [[multiple delimiters `\ProvidesExpl*` in a single file]])
local byte_range = err[3]
local start_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:start())
local end_line_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, byte_range:stop())
assert(start_line_number == 4)
assert(end_line_number == 5)
