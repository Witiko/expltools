local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")

local filename = "e102-02.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local results = {}

preprocessing(filename, content, issues, results)

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
