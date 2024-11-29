local new_issues = require("explcheck-issues")
local format = require("explcheck-format")
local preprocessing = require("explcheck-preprocessing")

local filename = "s103.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()

local line_starting_byte_numbers = preprocessing(issues, content)

assert(#issues.errors == 0)
assert(#issues.warnings == 2)

local warnings = issues:sort(issues.warnings)

assert(warnings[1][1] == "w100")
assert(warnings[1][2] == "no standard delimiters")
assert(warnings[1][3] == nil)  -- file-wide warning

assert(warnings[2][1] == "s103")
assert(warnings[2][2] == "line too long")
local range_start_byte_number, range_end_byte_number = table.unpack(warnings[2][3])
local range_start_line_number = format.convert_byte_to_line_and_column(
  line_starting_byte_numbers,
  range_start_byte_number
)
local range_end_line_number = format.convert_byte_to_line_and_column(
  line_starting_byte_numbers,
  range_end_byte_number - 1
)
assert(range_start_line_number == 2)
assert(range_end_line_number == 2)
