local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")

local filename = "e102-01.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local results = {}
local options = {expl3_detection_strategy = "always"}

preprocessing.process(filename, content, issues, results, options)

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
