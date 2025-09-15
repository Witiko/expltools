local utils = require("explcheck-utils")

local filename = "w100-02.tex"
local options = {
  expl3_detection_strategy = "always",
  stop_after = "preprocessing",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues = state.issues

assert(#issues.errors == 0)
assert(#issues.warnings == 0)
