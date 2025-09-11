-- A command-line interface for the static analyzer explcheck.

local evaluation = require("explcheck-evaluation")
local format = require("explcheck-format")
local get_option = require("explcheck-config").get_option
local new_issues = require("explcheck-issues")
local utils = require("explcheck-utils")

local new_file_results = evaluation.new_file_results
local new_aggregate_results = evaluation.new_aggregate_results

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

-- Check that the pathname specifies a file that we can process.
local function check_pathname(pathname)
  local suffix = utils.get_suffix(pathname)
  if suffix == ".ins" then
    local basename = utils.get_basename(pathname)
    if basename:find(" ") then
      basename = "'" .. basename .. "'"
    end
    return
      false,
      "explcheck can't currently process .ins files directly\n"
      .. 'Use a command such as "luatex ' .. basename .. '" '
      .. "to generate .tex, .cls, and .sty files and process these files instead."
  elseif suffix == ".dtx" then
    local parent = utils.get_parent(pathname)
    local basename = "*.ins"
    local has_lfs, lfs = pcall(require, "lfs")
    if has_lfs then
      for candidate_basename in lfs.dir(parent) do
        local candidate_suffix = utils.get_suffix(candidate_basename)
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
  if not options.porcelain then
    print("Checking " .. #pathnames .. " " .. format.pluralize("file", #pathnames))
  end

  local aggregate_evaluation_results = new_aggregate_results()
  for pathname_number, pathname in ipairs(pathnames) do
    local is_ok, error_message = xpcall(function()

      -- Set up the issue registry.
      local issues = new_issues(pathname, options)

      -- Load an input file.
      local file = assert(io.open(pathname, "r"))
      local content = assert(file:read("*a"))
      assert(file:close())

      -- Run all steps.
      local analysis_results = {}
      utils.process_with_all_steps(pathname, content, issues, analysis_results, options)

      -- Print warnings and errors.
      local file_evaluation_results = new_file_results(content, analysis_results, issues)
      aggregate_evaluation_results:add(file_evaluation_results)
      local is_last_file = pathname_number == #pathnames
      format.print_results(pathname, issues, analysis_results, options, file_evaluation_results, is_last_file)
    end, debug.traceback)
    if not is_ok then
      error("Failed to process " .. pathname .. ": " .. tostring(error_message), 0)
    end
  end

  format.print_summary(options, aggregate_evaluation_results)

  local num_errors = aggregate_evaluation_results.num_errors
  local num_warnings = aggregate_evaluation_results.num_warnings
  if(num_errors > 0) then
    return 1
  elseif(get_option("warnings_are_errors", options) and num_warnings > 0) then
    return 2
  else
    return 0
  end
end

local function print_usage()
  print("Usage: " .. arg[0] .. " [OPTIONS] FILENAMES\n")
  print("Run static analysis on expl3 files.\n")
  local expl3_detection_strategy = get_option("expl3_detection_strategy")
  local make_at_letter = tostring(get_option("make_at_letter"))
  local max_line_length = tostring(get_option("max_line_length"))
  local max_grouped_files = get_option("max_grouped_files_per_directory")
  print(
    "Options:\n\n"
    .. "\t--config-file=FILENAME     The name of the user config file. Defaults to FILENAME=\"" .. get_option("config_file") .. "\".\n\n"
    .. "\t--error-format=FORMAT      The Vim's quickfix errorformat used for the output with --porcelain enabled.\n"
    .. "\t                           The default format is FORMAT=\"" .. get_option("error_format") .. "\".\n\n"
    .. "\t--expl3-detection-strategy={never|always|precision|recall|auto}\n\n"
    .. "\t                           The strategy for detecting expl3 parts of the input files:\n\n"
    .. '\t                           - "never": Assume that no part of the input files is in expl3.\n'
    .. '\t                           - "always": Assume that the whole input files are in expl3.\n'
    .. '\t                           - "precision", "recall", and "auto": Analyze standard delimiters such as \n'
    .. '\t                             \\ExplSyntaxOn and Off. If no standard delimiters exist, assume either that:\n'
    .. '\t                               - "precision": No part of the input file is in expl3.\n'
    .. '\t                               - "recall": The entire input file is in expl3.\n'
    .. '\t                               - "auto": Use context cues to determine whether no part or the whole input file\n'
    .. "\t                                 is in expl3.\n\n"
    .. "\t                           The default setting is --expl3-detection-strategy=" .. expl3_detection_strategy .. ".\n\n"
    .. "\t--group-files={no|yes|auto}\n\n"
    .. "\t                           The strategy for grouping input files into sets that are assumed to be used together:\n\n"
    .. '\t                           - "no": Never group files unless "+" is written between a pair of FILENAMES.\n'
    .. '\t                           - "yes": Always group files unless "," is written between a pair of FILENAMES.\n'
    .. '\t                           - "auto": Group files from the same directory, unless they are separated with ","\n'
    .. "\t                             and unless there are more than " .. max_grouped_files .. " files in the directory.\n\n"
    .. "\t                           The default setting is --group-files=" .. get_option("group_files") .. ".\n\n"
    .. "\t--ignored-issues=ISSUES    A comma-list of issue identifiers (or just prefixes) that should not be reported.\n\n"
    .. "\t--make-at-letter[={true|false|auto}]\n\n"
    .. '\t                           How the at sign ("@") should be tokenized:\n\n'
    .. '\t                           - empty or "true": Tokenize "@" as a letter (catcode 11), like in LaTeX style files.\n'
    .. '\t                           - "false": Tokenize "@" as an other character (catcode 12), like in plain TeX.\n'
    .. '\t                           - "auto": Use context cues to determine the catcode of "@".\n\n'
    .. "\t                           The default setting is --make-at-letter=" .. make_at_letter .. ".\n\n"
    .. "\t--max-line-length=N        The maximum line length before the warning S103 (Line too long) is produced.\n"
    .. "\t                           The default maximum line length is N=" .. max_line_length .. " characters.\n\n"
    .. "\t--no-config-file           Do not load a user config file. See also --config-file.\n\n"
    .. "\t--porcelain, -p            Produce machine-readable output. See also --error-format.\n\n"
    .. "\t--verbose                  Print additional information in non-machine-readable output. See also --porcelain.\n\n"
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
    elseif argument:sub(1, 14) == "--config-file=" then
      options.config_file = argument:sub(15)
    elseif argument:sub(1, 15) == "--error-format=" then
      options.error_format = argument:sub(16)
    elseif argument:sub(1, 27) == "--expl3-detection-strategy=" then
      options.expl3_detection_strategy = argument:sub(28)
    elseif argument == "--expect-expl3-everywhere" then
      -- TODO: Remove `--expect-expl3-everywhere` in v1.0.0.
      options.expl3_detection_strategy = "always"
    elseif argument:sub(1, 17) == "--ignored-issues=" then
      options.ignored_issues = {}
      for issue_identifier in argument:sub(18):gmatch('[^,]+') do
        table.insert(options.ignored_issues, issue_identifier)
      end
    elseif argument == "--make-at-letter" then
      options.make_at_letter = true
    elseif argument:sub(1, 17) == "--make-at-letter=" then
      local make_at_letter = argument:sub(18)
      if make_at_letter == "true" then
        options.make_at_letter = true
      elseif make_at_letter == "false" then
        options.make_at_letter = false
      else
        options.make_at_letter = make_at_letter
      end
    elseif argument:sub(1, 18) == "--max-line-length=" then
      options.max_line_length = tonumber(argument:sub(19))
    elseif argument == "--no-config-file" then
      options.config_file = ""
    elseif argument == "--porcelain" or argument == "-p" then
      options.porcelain = true
    elseif argument == "--verbose" then
      options.verbose = true
    elseif argument == "--warnings-are-errors" then
      options.warnings_are_errors = true
    elseif argument:sub(1, 1) == "-" then
      print(string.format('Unrecognized argument: %s\n', argument))
      print_usage()
      os.exit(1)
    else
      table.insert(pathnames, argument)
    end
  end

  if #pathnames == 0 then
    print_usage()
    os.exit(1)
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
