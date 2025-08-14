local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")

local filename = "s414-04.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local options = {expl3_detection_strategy = "always", ignored_issues = {"w415"}}
local issues = new_issues(filename, options)
local results = {}

preprocessing.process(filename, content, issues, results, options)
lexical_analysis.process(filename, content, issues, results, options)
syntactic_analysis.process(filename, content, issues, results, options)
semantic_analysis.process(filename, content, issues, results, options)

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
