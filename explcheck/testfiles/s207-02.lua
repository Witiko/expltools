local new_issues = require("explcheck-issues")
local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")

local filename = "s207-02.tex"

local file = assert(io.open(filename, "r"))
local content = assert(file:read("*a"))
assert(file:close())
local issues = new_issues()
local options = {expect_expl3_everywhere = true}

local _, expl_ranges = preprocessing(issues, content, options)
lexical_analysis(issues, content, expl_ranges, options)

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
