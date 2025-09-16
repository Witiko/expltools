local utils = require("explcheck-utils")

local filename = "w100.tex"
local options = {
  stop_after = "preprocessing",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues = state.issues

assert(#issues.errors == 0)
assert(#issues.warnings == 1)

local warning = issues.warnings[1]
assert(warning[1] == "w100")
assert(warning[2] == "no standard delimiters")
assert(warning[3] == nil)  -- file-wide warning
