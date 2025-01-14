-- A command-line interface for the static analyzer explcheck.

local config = require("explcheck-config")
local new_issues = require("explcheck-issues")
local format = require("explcheck-format")
local utils = require("explcheck-utils")

local preprocessing = require("explcheck-preprocessing")
local lexical_analysis = require("explcheck-lexical-analysis")
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
local function main(pathnames, options)
  local num_warnings = 0
  local num_errors = 0

  if not options.porcelain then
    print("Checking " .. #pathnames .. " " .. format.pluralize("file", #pathnames))
  end

  for pathname_number, pathname in ipairs(pathnames) do

    -- Set up the issue registry.
    local issues = new_issues()
    for _, issue_identifier in ipairs(utils.get_option(options, "ignored_issues")) do
      issues:ignore(issue_identifier)
    end

    -- Load an input file.
    local file = assert(io.open(pathname, "r"), "Could not open " .. pathname .. " for reading")
    local content = assert(file:read("*a"))
    assert(file:close())

    -- Run all processing steps.
    local line_starting_byte_numbers, expl_ranges, tokens  -- luacheck: ignore tokens

    line_starting_byte_numbers, expl_ranges = preprocessing(issues, content, options)

    if #issues.errors > 0 then
      goto continue
    end

    tokens = lexical_analysis(issues, content, expl_ranges, options)

    -- syntactic_analysis(issues)
    -- semantic_analysis(issues)
    -- pseudo_flow_analysis(issues)

    -- Print warnings and errors.
    ::continue::
    num_warnings = num_warnings + #issues.warnings
    num_errors = num_errors + #issues.errors
    format.print_results(pathname, issues, line_starting_byte_numbers, pathname_number == #pathnames, options.porcelain)
  end

  -- Print a summary.
  if not options.porcelain then
    format.print_summary(#pathnames, num_warnings, num_errors, options.porcelain)
  end

  if(num_errors > 0) then
    return 1
  elseif(options.warnings_are_errors and num_warnings > 0) then
    return 2
  else
    return 0
  end
end

local function print_usage()
  print("Usage: " .. arg[0] .. " [OPTIONS] FILENAMES\n")
  print("Run static analysis on expl3 files.\n")
  local max_line_length = tostring(config.max_line_length)
  print(
    "Options:\n\n"
    .. "\t--expect-expl3-everywhere  Expect that the whole files are in expl3, ignoring \\ExplSyntaxOn and Off.\n"
    .. "\t                           This prevents the error E102 (expl3 material in non-expl3 parts).\n\n"
    .. "\t--ignored-issues=ISSUES    A comma-list of warning and error identifiers that should not be reported.\n\n"
    .. "\t--max-line-length=N        The maximum line length before the warning S103 (Line too long) is produced.\n"
    .. "\t                           The default maximum line length is N=" .. max_line_length .. " characters.\n\n"
    .. "\t--porcelain, -p            Produce machine-readable output.\n\n"
    .. "\t--warnings-are-errors      Produce a non-zero exit code if any warnings are produced by the analysis.\n"
  )
  print("The options are provisional and may be changed or removed before version 1.0.0.")
end

local function print_version()
  print("explcheck (expltools ${DATE}) ${VERSION}")
  print("Copyright (c) 2024-2025 Vít Starý Novotný")
  print("Licenses: LPPL 1.3 or later, GNU GPL v2 or later")
end

if #arg == 0 then
  print_usage()
  os.exit(1)
else
  -- Collect arguments.
  local pathnames = {}
  local only_pathnames_from_now_on = false
  local options = {}
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
    elseif argument == "--expect-expl3-everywhere" then
      options.expect_expl3_everywhere = true
    elseif argument:sub(1, 17) == "--ignored-issues=" then
      options.ignored_issues = {}
      for issue_identifier in argument:sub(18):gmatch('[^,]+') do
        table.insert(options.ignored_issues, issue_identifier)
      end
    elseif argument:sub(1, 18) == "--max-line-length=" then
      options.max_line_length = tonumber(argument:sub(19))
    elseif argument == "--porcelain" or argument == "-p" then
      options.porcelain = true
    elseif argument == "--warnings-are-errors" then
      options.warnings_are_errors = true
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
  local exit_code = main(pathnames, options)
  os.exit(exit_code)
end
