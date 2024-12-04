local new_issues = require("explcheck-issues")
local format = require("explcheck-format")
local preprocessing = require("explcheck-preprocessing")

local filename = "e104.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()

local line_starting_byte_numbers = preprocessing(issues, content)

assert(#issues.errors == 1)
assert(#issues.warnings == 0)

local errors = issues.sort(issues.errors)

assert(errors[1][1] == "e104")
assert(errors[1][2] == [[multiple delimiters `\ProvidesExpl*` in a single file]])
local range_start_byte_number, range_end_byte_number = table.unpack(errors[1][3])
local range_start_line_number = format.convert_byte_to_line_and_column(
  line_starting_byte_numbers,
  range_start_byte_number
)
local range_end_line_number = format.convert_byte_to_line_and_column(
  line_starting_byte_numbers,
  range_end_byte_number - 1
)
assert(range_start_line_number == 4)
assert(range_end_line_number == 5)
