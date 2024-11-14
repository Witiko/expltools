-- A command-line interface for the static analyzer explcheck.

local new_issues = require("explcheck-issues")
local print_results, print_summary = table.unpack(require("explcheck-format"))

local preprocessing = require("explcheck-preprocessing")
-- local lexical_analysis = require("explcheck-lexical-analysis")
-- local syntactic_analysis = require("explcheck-syntactic-analysis")
-- local semantic_analysis = require("explcheck-semantic-analysis")
-- local pseudo_flow_analysis = require("explcheck-pseudo-flow-analysis")

-- Deduplicate pathnames.
local function deduplicate_pathnames(pathnames)
  local deduplicated_pathnames = {}
  local seen_pathnames = {}
  for _, pathname in ipairs(pathnames) do
    if seen_pathnames[pathname] ~= nil then
      goto continue
    end
    seen_pathnames[pathname] = true
    table.insert(deduplicated_pathnames, pathname)
    ::continue::
  end
  return deduplicated_pathnames
end

-- Process all input files.
local function main(pathnames)
  local num_warnings = 0
  local num_errors = 0

  print("Checking " .. #pathnames .. " files")

  for pathname_number, pathname in ipairs(pathnames) do

    -- Load an input file.
    local file = assert(io.open(pathname, "r"), "Could not open " .. pathname .. " for reading")
    local content = assert(file:read("*a"))
    assert(file:close())
    local issues = new_issues()

    -- Run all processing steps.
    local line_starting_byte_numbers, _ = preprocessing(issues, content)
    if #issues.errors > 0 then
      goto continue
    end
    -- lexical_analysis(issues)
    -- syntactic_analysis(issues)
    -- semantic_analysis(issues)
    -- pseudo_flow_analysis(issues)

    -- Print warnings and errors.
    ::continue::
    num_warnings = num_warnings + #issues.warnings
    num_errors = num_errors + #issues.errors
    print_results(pathname, issues, line_starting_byte_numbers, pathname_number == #pathnames)
  end

  -- Print a summary.
  print_summary(#pathnames, num_warnings, num_errors)

  if(num_errors > 0) then
    os.exit(1)
  end
end

if #arg == 0 then
  print("Usage: " .. arg[0] .. " FILENAMES")
else
  local pathnames = deduplicate_pathnames(arg)
  main(pathnames)
end
