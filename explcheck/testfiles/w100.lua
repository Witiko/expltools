local common = require("explcheck-common")
local preprocessing = require("explcheck-preprocessing")

local filename = "w100.tex"
local state = common.initialize_state(filename)
preprocessing(state)

assert(#state.errors == 0)
assert(#state.warnings == 1)

local warning = state.warnings[1]
assert(warning[1] == "w100")
assert(warning[2] == "no standard delimiters")
assert(warning[3] == nil)  -- file-wide warning
