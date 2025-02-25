local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")

local filename = "s207-02.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local results = {}
local options = {expl3_detection_strategy = "always"}

preprocessing(filename, content, issues, results, options)
lexical_analysis(filename, content, issues, results, options)

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
