-- A command-line interface for the static analyzer explcheck.

local new_issues = require("explcheck-issues")
local format = require("explcheck-format")

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

-- Convert a pathname of a file to the suffix of the file.
local function get_suffix(pathname)
  return pathname:gsub(".*%.", "."):lower()
end

-- Convert a pathname of a file to the base name of the file.
local function get_basename(pathname)
  return pathname:gsub(".*[\\/]", "")
end

-- Convert a pathname of a file to the pathname of its parent directory.
local function get_parent(pathname)
  if pathname:find("[\\/]") then
    return pathname:gsub("(.*)[\\/].*", "%1")
  else
    return "."
  end
end

-- Check that the pathname specifies a file that we can process.
local function check_pathname(pathname)
  local suffix = get_suffix(pathname)
  if suffix == ".ins" then
    local basename = get_basename(pathname)
    if basename:find(" ") then
      basename = "'" .. basename .. "'"
    end
    return
      false,
      "explcheck can't currently process .ins files directly\n"
      .. 'Use a command such as "luatex ' .. basename .. '" '
      .. "to generate .tex, .cls, and .sty files and process these files instead."
  elseif suffix == ".dtx" then
    local parent = get_parent(pathname)
    local basename = "*.ins"
    local has_lfs, lfs = pcall(require, "lfs")
    if has_lfs then
      for candidate_basename in lfs.dir(parent) do
        local candidate_suffix = get_suffix(candidate_basename)
        if candidate_suffix == ".ins" then
          basename = candidate_basename
          if basename:find(" ") then
            basename = "'" .. candidate_basename .. "'"
          end
          break
        end
      end
    end
    return
      false,
      "explcheck can't currently process .dtx files directly\n"
      .. 'Use a command such as "luatex ' .. basename .. '" '
      .. "to generate .tex, .cls, and .sty files and process these files instead."
  end
  return true
end

-- Process all input files.
local function main(pathnames, warnings_are_errors, max_line_length, porcelain)
  local num_warnings = 0
  local num_errors = 0

  if not porcelain then
    print("Checking " .. #pathnames .. " " .. format.pluralize("file", #pathnames))
  end

  for pathname_number, pathname in ipairs(pathnames) do

    -- Load an input file.
    local file = assert(io.open(pathname, "r"), "Could not open " .. pathname .. " for reading")
    local content = assert(file:read("*a"))
    assert(file:close())
    local issues = new_issues()

    -- Run all processing steps.
    local line_starting_byte_numbers, _ = preprocessing(issues, content, max_line_length)
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
    format.print_results(pathname, issues, line_starting_byte_numbers, pathname_number == #pathnames, porcelain)
  end

  -- Print a summary.
  if not porcelain then
    format.print_summary(#pathnames, num_warnings, num_errors, porcelain)
  end

  if(num_errors > 0) then
    return 1
  elseif(warnings_are_errors and num_warnings > 0) then
    return 2
  else
    return 0
  end
end

local function print_usage()
  print("Usage: " .. arg[0] .. " [OPTIONS] FILENAMES\n")
  print("Run static analysis on expl3 files.\n")
  print("Options:")
  print("\t--max-line-length=N    The maximum line length before the warning S103 (Line too long) is produced.")
  print("\t--porcelain            Produce machine-readable output.")
  print("\t--warnings-are-errors  Produce a non-zero exit code if any warnings are produced by the analysis.")
end

local function print_version()
  print("explcheck (expltools ${DATE}) ${VERSION}")
  print("Copyright (c) 2024 Vít Starý Novotný")
  print("Licenses: LPPL 1.3 or later, GNU GPL v2 or later")
end

if #arg == 0 then
  print_usage()
  os.exit(1)
else
  -- Collect arguments.
  local pathnames = {}
  local warnings_are_errors = false
  local only_pathnames_from_now_on = false
  local max_line_length = nil
  local porcelain = false
  for _, argument in ipairs(arg) do
    if only_pathnames_from_now_on then
      table.insert(pathnames, argument)
    elseif argument == "--" then
      only_pathnames_from_now_on = true
    elseif argument == "--help" or argument == "-h" then
      print_usage()
      os.exit(0)
    elseif argument == "--version" or argument == "-v" then
      print_version()
      os.exit(0)
    elseif argument == "--warnings-are-errors" then
      warnings_are_errors = true
    elseif argument == "--porcelain" then
      porcelain = true
    elseif argument:sub(1, 18) == "--max-line-length=" then
      max_line_length = tonumber(argument:sub(19))
    elseif argument:sub(1, 2) == "--" then
      -- An unknown argument
      print_usage()
      os.exit(1)
    else
      table.insert(pathnames, argument)
    end
  end

  -- Deduplicate and check that pathnames specify files that we can process.
  pathnames = deduplicate_pathnames(pathnames)
  for _, pathname in ipairs(pathnames) do
    local is_ok, error_message = check_pathname(pathname)
    if not is_ok then
      print('Failed to process "' .. pathname .. '": ' .. error_message)
      os.exit(1)
    end
  end

  -- Run the analysis.
  local exit_code = main(pathnames, warnings_are_errors, max_line_length, porcelain)
  os.exit(exit_code)
end
