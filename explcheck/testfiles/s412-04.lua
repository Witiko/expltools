local utils = require("explcheck-utils")

local filename = "s412-04.tex"
local options = {
  expl3_detection_strategy = "always",
  ignored_issues = {"w401"},
  stop_after = "semantic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues = state.issues

assert(#issues.errors == 0)
assert(#issues.warnings == 0, #issues.warnings)
