-- A command-line interface for the static analyzer explcheck.

local evaluation = require("explcheck-evaluation")
local format = require("explcheck-format")
local get_option = require("explcheck-config").get_option
local utils = require("explcheck-utils")

local new_file_results = evaluation.new_file_results
local new_aggregate_results = evaluation.new_aggregate_results

-- Process all input files.
local function main(pathname_groups, options)
  local num_pathnames = 0
  for _, pathname_group in ipairs(pathname_groups) do
    num_pathnames = num_pathnames + #pathname_group
  end
  if not options.porcelain then
    print("Checking " .. num_pathnames .. " " .. format.pluralize("file", num_pathnames))
  end

  local aggregate_evaluation_results = new_aggregate_results()
  for pathname_group_number, pathname_group in ipairs(pathname_groups) do
    local is_last_group = pathname_group_number == #pathname_groups
    local is_ok, error_message = xpcall(function()
      -- Run all processing steps and collect issues and analysis results.
      local states = utils.process_files(pathname_group, options)
      assert(#states == #pathname_group)
      for pathname_number, state in ipairs(states) do
        assert(pathname_group[pathname_number] == state.pathname)
        -- Print warnings and errors.
        local file_evaluation_results = new_file_results(state)
        aggregate_evaluation_results:add(file_evaluation_results)
        local is_last_file = is_last_group and (pathname_number == #pathname_group)
        format.print_results(state, options, file_evaluation_results, is_last_file)
      end
    end, debug.traceback)
    if not is_ok then
      error("Failed to process " .. table.concat(pathname_group, ', ') .. ": " .. tostring(error_message), 0)
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
  local max_line_length = tostring(get_option("max_line_length"))
  print(
    "Options:\n\n"
    .. "\t--config-file FILENAME     The name of the user config file. Defaults to FILENAME=\"" .. get_option("config_file") .. "\".\n\n"
    .. "\t--error-format FORMAT      The Vim's quickfix errorformat used for the output with --porcelain enabled.\n"
    .. "\t                           The default format is FORMAT=\"" .. get_option("error_format") .. "\".\n\n"
    .. "\t--expl3-detection-strategy {never|always|precision|recall|auto}\n\n"
    .. "\t                           The strategy for detecting expl3 parts of the input files:\n\n"
    .. '\t                           - "never": Assume that no part of the input files is in expl3.\n'
    .. '\t                           - "always": Assume that the whole input files are in expl3.\n'
    .. '\t                           - "precision", "recall", and "auto": Analyze standard delimiters such as \n'
    .. '\t                             \\ExplSyntaxOn and Off. If no standard delimiters exist, assume either that:\n'
    .. '\t                               - "precision": No part of the input file is in expl3.\n'
    .. '\t                               - "recall": The entire input file is in expl3.\n'
    .. '\t                               - "auto": Use context cues to determine whether no part or the whole input file\n'
    .. "\t                                 is in expl3.\n\n"
    .. "\t                           The default setting is --expl3-detection-strategy " .. expl3_detection_strategy .. ".\n\n"
    .. "\t--files-from FILE          Read the list of FILENAMES from FILE.\n\n"
    .. '\t--group-files              Always group files into sets that are assumed to be used together unless "," is written\n'
    .. "\t                           between a pair of FILENAMES.\n\n"
    .. "\t                           The default setting is --group-files " .. get_option("group_files") .. ".\n\n"
    .. "\t--ignored-issues ISSUES    A comma-list of issue identifiers (or just prefixes) that should not be reported.\n\n"
    .. '\t--make-at-letter           Tokenize "@" as a letter (catcode 11), like in LaTeX style files.\n\n'
    .. '\t--make-at-other            Tokenize "@" as an other character (catcode 12), like in plain TeX.\n\n'
    .. "\t--max-line-length N        The maximum line length before the warning S103 (Line too long) is produced.\n"
    .. "\t                           The default maximum line length is N=" .. max_line_length .. " characters.\n\n"
    .. "\t--no-config-file           Do not load a user config file. See also --config-file.\n\n"
    .. '\t--no-group-files           Never group files into sets that are assumed to be used together unless "+" is written\n'
    .. "\t                           between a pair of FILENAMES.\n\n"
    .. "\t--porcelain, -p            Produce machine-readable output. See also --error-format.\n\n"
    .. "\t--verbose                  Print additional information in non-machine-readable output. See also --porcelain.\n\n"
    .. "\t--warnings-are-errors      Produce a non-zero exit code if any warnings are produced by the analysis.\n"
  )
  print("The options are provisional and may be changed or removed before version 1.0.0.")
end

local function print_usage_and_exit(exit_code)
  print_usage()
  os.exit(exit_code)
end

local function print_version()
  print("explcheck (expltools ${DATE}) ${VERSION}")
  print("Copyright (c) 2024-2026 Vít Starý Novotný")
  print("Licenses: LPPL 1.3 or later, GNU GPL v2 or later")
end

if #arg == 0 then
  print_usage_and_exit(1)
end

-- Collect arguments.
local pathnames, allow_pathname_separators = {}, {}
local only_pathnames_from_now_on = false
local options = {}

local long_options = {
  ["help"] = {
    action = function()
      print_usage_and_exit(0)
    end,
  },
  ["version"] = {
    action = function()
      print_version()
      os.exit(0)
    end,
  },
  ["config-file"] = {
    value_required = true,
    action = function(value)
      options.config_file = value
    end,
  },
  ["error-format"] = {
    value_required = true,
    action = function(value)
      options.error_format = value
    end,
  },
  ["expl3-detection-strategy"] = {
    value_required = true,
    field_name = "expl3_detection_strategy",
    action = function(value)
      options.expl3_detection_strategy = value
    end,
  },
  -- TODO: Remove `--expect-expl3-everywhere` in v1.0.0.
  ["expect-expl3-everywhere"] = {
    action = function()
      options.expl3_detection_strategy = "always"
    end,
  },
  ["files-from"] = {
    value_required = true,
    action = function(value)
      local file = assert(io.open(value, "r"))
      for pathname in file:lines() do
        table.insert(pathnames, pathname)
        table.insert(allow_pathname_separators, false)
      end
      assert(file:close())
    end,
  },
  ["group-files"] = {
    action = function(value)
      if value == nil then
        options.group_files = true
      else
        -- TODO: Remove `--group-files[={true|false|auto}]` in v1.0.0.
        if value == "true" then
          options.group_files = true
        elseif value == "false" then
          options.group_files = false
        else
          options.group_files = value
        end
      end
    end,
  },
  ["ignored-issues"] = {
    value_required = true,
    action = function(value)
      options.ignored_issues = {}
      for issue_identifier in value:gmatch('[^,]+') do
        table.insert(options.ignored_issues, issue_identifier)
      end
    end,
  },
  ["make-at-letter"] = {
    action = function(value)
      if value == nil then
        options.make_at_letter = true
      else
        -- TODO: Remove `--make-at-letter[={true|false|auto}]` in v1.0.0.
        if value == "true" then
          options.make_at_letter = true
        elseif value == "false" then
          options.make_at_letter = false
        else
          options.make_at_letter = value
        end
      end
    end,
  },
  ["make-at-other"] = {
    action = function()
      options.make_at_letter = false
    end,
  },
  ["max-line-length"] = {
    value_required = true,
    action = function(value)
      options.max_line_length = tonumber(value)
    end,
  },
  ["no-config-file"] = {
    action = function()
      options.config_file = ""
    end,
  },
  ["no-group-files"] = {
    action = function()
      options.group_files = false
    end,
  },
  ["porcelain"] = {
    action = function()
      options.porcelain = true
    end,
  },
  ["verbose"] = {
    action = function()
      options.verbose = true
    end,
  },
  ["warnings-are-errors"] = {
    action = function()
      options.warnings_are_errors = true
    end,
  },
}

local short_options = {
  h = long_options["help"],
  v = long_options["version"],
  p = long_options["porcelain"],
}

local function unknown_argument(argument)
  print(string.format('Unrecognized argument: %s\n', argument))
  print_usage_and_exit(1)
end

local i = 1
while i <= #arg do
  local argument = arg[i]
  if only_pathnames_from_now_on then
    table.insert(pathnames, argument)
    table.insert(allow_pathname_separators, true)
  elseif argument == "--" then
    only_pathnames_from_now_on = true
  -- Parse long options.
  elseif argument:sub(1, 2) == "--" then
    local option_name, option_value
    local pos = argument:find("=", 1, true)
    if pos then
      option_name = argument:sub(3, pos - 1)
      option_value = argument:sub(pos + 1)
    else
      option_name = argument:sub(3)
    end
    if not long_options[option_name] then
      unknown_argument(argument)
    end
    if long_options[option_name].value_required then
      if not option_value then
        -- Parse long option with separate value `--option VALUE`.
        if i == #arg or arg[i + 1]:sub(1, 1) == "-" then
          print(string.format("No value provided for option: %s\n", argument))
          print_usage_and_exit(1)
        end
        i = i + 1
        option_value = arg[i]
      end
      long_options[option_name].action(option_value)
    else
      if option_value then
        print(string.format("Option does not take a value: %s\n", argument))
        print_usage_and_exit(1)
      end
      long_options[option_name].action()
    end
  -- Parse short options.
  elseif argument:sub(1, 1) == "-" and argument:len() == 2 then
    -- TODO: Support merged short options, e.g. `-abc` as a shorthand for `-a -b -c`.
    local option_name = argument:sub(2, 2)
    if not short_options[option_name] then
      unknown_argument(argument)
    end
    -- TODO: Support short options with values, e.g. `-p VALUE`.
    short_options[option_name].action()
  elseif argument:sub(1, 1) == "-" then
    unknown_argument(argument)
  else
    table.insert(pathnames, argument)
    table.insert(allow_pathname_separators, true)
  end
  i = i + 1
end

assert(#pathnames == #allow_pathname_separators)

if #pathnames == 0 then
  print_usage_and_exit(1)
end

-- Group pathnames.
local pathname_groups = utils.group_pathnames(pathnames, options, allow_pathname_separators)

-- Check pathnames.
for _, pathname_group in ipairs(pathname_groups) do
  for _, pathname in ipairs(pathname_group) do
    local is_ok, error_message = utils.check_pathname(pathname)
    if not is_ok then
      print('Failed to process "' .. pathname .. '": ' .. error_message .. "\n")
      os.exit(1)
    end
  end
end

-- Run the analysis.
local exit_code = main(pathname_groups, options)
os.exit(exit_code)
