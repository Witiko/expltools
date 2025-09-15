local utils = require("explcheck-utils")

local filename = "e102-01.tex"
local options = {
  stop_after = "preprocessing",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues = state.issues

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
