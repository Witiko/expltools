bundle = "expltools"
module = "explcheck"
maindir = ".."

-- Convert a pathname of a file to the base name of a file.
local function get_suffix(filename)
  return filename:gsub(".+%.", ".")
end

function checkinit_hook()
  local lfs = require("lfs")
  local support_files = {}
  for filename in lfs.dir("src") do
    if get_suffix(filename) == ".lua" then
      table.insert(support_files, "src/" .. filename)
    end
  end
  local testfiles = {}
  for filename in lfs.dir("testfiles") do
    local suffix = get_suffix(filename)
    if suffix == ".lua" or suffix == ".tex" then
      table.insert(testfiles, "testfiles/" .. filename)
    end
  end
  local run_tests = require("test")
  local test_result = run_tests("test", support_files, testfiles)
  os.exit(test_result and 0 or 1)
end
