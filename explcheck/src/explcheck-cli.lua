-- A command-line interface for the static analyzer explcheck.

local evaluation = require("explcheck-evaluation")
local format = require("explcheck-format")
local get_option = require("explcheck-config").get_option
local utils = require("explcheck-utils")

local new_file_results = evaluation.new_file_results
local new_aggregate_results = evaluation.new_aggregate_results

local argument_types = {
  ARGUMENT_SEPARATOR = "a separator between mixed command-line options and filenames and only filenames",
  LONG_OPTION = "a long command-line option like `--porcelain`",
  SHORT_OPTION = "a long command-line option like `-p`",
  OTHER_ARGUMENT = "another unrecognized argument such as a pathname or a value for a long command-line option",
}

local ARGUMENT_SEPARATOR = argument_types.ARGUMENT_SEPARATOR
local LONG_OPTION = argument_types.LONG_OPTION
local SHORT_OPTION = argument_types.SHORT_OPTION
local OTHER_ARGUMENT = argument_types.OTHER_ARGUMENT

-- Process all input file groups.
local function process_file_groups(pathname_groups, options)
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

-- Process all command-line arguments, if any, and take the appropriate actions.
local function process_arguments(arguments)

  -- Print information about the usage of the command-line interface.
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

  -- Print the versions of the expltools bundle and the explcheck package.
  local function print_version()
    print("explcheck (expltools ${DATE}) ${VERSION}")
    print("Copyright (c) 2024-2026 Vít Starý Novotný")
    print("Licenses: LPPL 1.3 or later, GNU GPL v2 or later")
  end

  -- Print an unrecognized command-line argument and exit.
  local function unrecognized_argument(argument)
    print(string.format('Unrecognized argument: %s\n', argument))
    print_usage()
    os.exit(1)
  end

  -- In the absence of command-line arguments, print information about the usage of the command-line interface and exit.
  if #arguments == 0 then
    print_usage()
    os.exit(1)
  end

  -- Otherwise, define the recognized command-line options.
  local pathnames, allow_pathname_separators = {}, {}
  local only_pathnames_from_now_on = false
  local options = {}
  local long_options = {
    ["help"] = {
      action = function()
        print_usage()
        os.exit(0)
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
      action = function(_, value)
        options.config_file = value
      end,
    },
    ["error-format"] = {
      value_required = true,
      action = function(_, value)
        options.error_format = value
      end,
    },
    ["expl3-detection-strategy"] = {
      value_required = true,
      field_name = "expl3_detection_strategy",
      action = function(_, value)
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
      action = function(_, value)
        local file = assert(io.open(value, "r"))
        for pathname in file:lines() do
          table.insert(pathnames, pathname)
          table.insert(allow_pathname_separators, false)
        end
        assert(file:close())
      end,
    },
    ["group-files"] = {
      action = function(_, value)
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
      action = function(_, value)
        options.ignored_issues = {}
        for issue_identifier in value:gmatch('[^,]+') do
          table.insert(options.ignored_issues, issue_identifier)
        end
      end,
    },
    ["make-at-letter"] = {
      action = function(_, value)
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
      action = function(name, value)
        local max_line_length = tonumber(value)
        if max_line_length == nil then
          print(string.format('Malformed numeric value "%s" for the option "%s".\n', value, name))
          print_usage()
          os.exit(1)
        end
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

  -- Parse the following command-line argument and determine its general type as well as any other relevant information.
  local function parse_argument(argument)
    if argument == "--" then
      return ARGUMENT_SEPARATOR
    elseif argument:sub(1, 2) == "--" then
      local option_name, option_value
      local pos = argument:find("=", 1, true)
      if pos then
        option_name = argument:sub(3, pos - 1)
        option_value = argument:sub(pos + 1)
      else
        option_name = argument:sub(3)
      end
      return LONG_OPTION, option_name, option_value
    elseif argument:sub(1, 1) == "-" and argument:len() == 2 then
      local option_name = argument:sub(2, 2)
      return SHORT_OPTION, option_name
    else
      return OTHER_ARGUMENT
    end
  end

  -- Then, process all arguments and collect all input file groups, if any.
  local argument_number = 1
  while argument_number <= #arguments do
    local argument = arguments[argument_number]
    if only_pathnames_from_now_on then
      table.insert(pathnames, argument)
      table.insert(allow_pathname_separators, true)
    else
      local argument_type, option_name, option_value = parse_argument(argument)
      if argument_type == ARGUMENT_SEPARATOR then
        only_pathnames_from_now_on = true
      elseif argument_type == LONG_OPTION then
        assert(option_name ~= nil)
        if long_options[option_name] == nil then
          unrecognized_argument(argument)
        end
        if long_options[option_name].value_required then
          if option_value == nil then
            -- Parse long option with separate value `--option VALUE`.
            if argument_number == #arguments then
              print(string.format('No value provided for option "%s".\n', argument))
              print_usage()
              os.exit(1)
            end
            assert(argument_number + 1 <= #arguments)
            local next_argument = arguments[argument_number + 1]
            local next_argument_type, next_option_name, _ = parse_argument(next_argument)
            if next_argument_type == LONG_OPTION and long_options[next_option_name] ~= nil or
                next_argument_type == SHORT_OPTION and short_options[next_option_name] ~= nil then
              print(string.format('Ambiguous value provided for option "%s": "%s".\n', argument, next_argument))
              print_usage()
              os.exit(1)
            end
            argument_number = argument_number + 1
            option_value = arguments[argument_number]
          end
          long_options[option_name].action(option_name, option_value)
        else
          if option_value ~= nil then
            print(string.format('Option "%s" does not take a value but "%s" was provided.\n', option_name, option_value))
            print_usage()
            os.exit(1)
          end
          long_options[option_name].action(option_name)
        end
      elseif argument_type == SHORT_OPTION then
        -- TODO: Support merged short options, e.g. `-abc` as a shorthand for `-a -b -c`?
        assert(option_name ~= nil)
        if short_options[option_name] == nil then
          unrecognized_argument(argument)
        end
        short_options[option_name].action()
      elseif argument_type == OTHER_ARGUMENT then
        if argument:sub(1, 1) == "-" then
          -- TODO: Support long options with just a single leading dash, e.g. `-long-option` rather than `--long-option`?
          --       This is consistent with *TeX but mutually exclusive with support for merged short options, e.g. `-abc`
          --       as a shorthand for `-a -b -c`. See also <https://github.com/witiko/expltools/pull/185#discussion_r2904253886>.
          -- TODO: Support `-` as a short-hand for `/dev/stdin` but check that it has only occurred once in `pathnames`.
          unrecognized_argument(argument)
        else
          table.insert(pathnames, argument)
          table.insert(allow_pathname_separators, true)
        end
      else
        error('Unexpected argument type "' .. argument.type .. '"')
      end
    end
    argument_number = argument_number + 1
  end
  assert(#pathnames == #allow_pathname_separators)

  -- In the absence of file groups, print information about the usage of the command-line interface and exit.
  if #pathnames == 0 then
    print_usage()
    os.exit(1)
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
  local exit_code = process_file_groups(pathname_groups, options)
  os.exit(exit_code)
end

process_arguments(arg)
