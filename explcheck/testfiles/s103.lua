local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")
local preprocessing = require("explcheck-preprocessing")

local filename = "s103.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local options = {expl3_detection_strategy = "recall"}

local line_starting_byte_numbers = preprocessing(issues, filename, content, options)

assert(#issues.errors == 0)
assert(#issues.warnings == 2)

local warnings = issues.sort(issues.warnings)

assert(warnings[1][1] == "w100")
assert(warnings[1][2] == "no standard delimiters")
assert(warnings[1][3] == nil)  -- file-wide warning

assert(warnings[2][1] == "s103")
assert(warnings[2][2] == "line too long")
local byte_range = warnings[2][3]
local start_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:start())
local end_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, byte_range:stop())
assert(start_line_number == 2)
assert(end_line_number == 2)
