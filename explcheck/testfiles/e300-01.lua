local utils = require("explcheck-utils")

local filename = "e300-01.tex"
local options = {
  expl3_detection_strategy = "always",
  stop_after = "syntactic analysis",
}
local state = table.unpack(utils.process_files({filename}, options))
local issues = state.issues

assert(#issues.errors == 0)
