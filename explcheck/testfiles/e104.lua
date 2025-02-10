local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
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
local err = errors[1]

assert(err[1] == "e104")
assert(err[2] == [[multiple delimiters `\ProvidesExpl*` in a single file]])
local byte_range = err[3]
local start_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:start())
local end_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:end_inclusive())
assert(start_line_number == 4)
assert(end_line_number == 5)
