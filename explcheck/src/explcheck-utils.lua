-- Common functions used by different modules of the static analyzer explcheck.

-- Convert a byte number in a file to a line and column number in a file.
local function convert_byte_to_line_and_column(line_starting_byte_numbers, byte_number)
  local line_number = 0
  for _, line_starting_byte_number in ipairs(line_starting_byte_numbers) do
    if line_starting_byte_number > byte_number then
      break
    end
    line_number = line_number + 1
  end
  assert(line_number > 0)
  local line_starting_byte_number = line_starting_byte_numbers[line_number]
  assert(line_starting_byte_number <= byte_number)
  local column_number = byte_number - line_starting_byte_number + 1
  return line_number, column_number
end

-- Convert a pathname of a file to the suffix of the file.
local function get_suffix(pathname)
  return pathname:gsub(".*%.", "."):lower()
end

-- Convert a pathname of a file to the base name of the file.
local function get_basename(pathname)
  return pathname:gsub(".*[\\/]", "")
end

-- Convert a pathname of a file to the stem of the file.
local function get_stem(pathname)
  return get_basename(pathname):gsub("%..*", "")
end

-- Convert a pathname of a file to the pathname of its parent directory.
local function get_parent(pathname)
  if pathname:find("[\\/]") then
    return pathname:gsub("(.*)[\\/].*", "%1")
  else
    return "."
  end
end

-- Return all parameters unchanged, mostly used for no-op map-back and map-forward functions.
local function identity(...)
  return ...
end

-- Check that a pathname specifies a file that we can process.
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

-- Group pathnames passed to the command-line interface.
local function group_pathnames(pathnames, options, allow_pathname_separators)
  assert(allow_pathname_separators == nil or #pathnames == #allow_pathname_separators)

  -- Require packages.
  local get_option = require("explcheck-config").get_option

  -- Get options.
  local group_files = get_option("group_files", options)
  local max_grouped_files_per_directory = get_option("max_grouped_files_per_directory", options)

  -- Set up variables.
  local pathname_groups, current_group = {}, {}
  local group_next, ungroup_next = false, false
  local previous_pathname, num_files_from_current_directory = nil, 0

  -- Close the current group by adding it to a list of groups, if nonempty, and opening the next group.
  local function close_current_group()
    if #current_group > 0 then
      table.insert(pathname_groups, current_group)
    end
    current_group = {}
  end

  -- Explode the current group by creating single-element groups out of it and adding them to the list of groups.
  local function explode_current_group()
    for _, pathname in ipairs(current_group) do
      table.insert(pathname_groups, {pathname})
    end
    current_group = {}
  end

  for pathname_number, current_pathname in ipairs(pathnames) do
    -- Process a grouping argument, such as "+" or ",".
    local allow_separator = allow_pathname_separators == nil or allow_pathname_separators[pathname_number] == true
    if allow_separator and (current_pathname == "+" or current_pathname == ",") then  -- a grouping argument
      if group_next or ungroup_next then
        error('Two arguments "+" or "," in a row')
      end
      if current_pathname == "+" then
        group_next = true
      else
        ungroup_next = true
      end
    else
      assert(not (group_next and ungroup_next))
      -- Process the pathname argument.
      if group_files == false then
        if not group_next then
          close_current_group()
        end
      elseif group_files == true then
        if ungroup_next then
          close_current_group()
        end
      elseif group_files == "auto" then
        if group_next then
          if num_files_from_current_directory > max_grouped_files_per_directory then
            explode_current_group()
          end
          num_files_from_current_directory = 0
        elseif ungroup_next then
          if num_files_from_current_directory > max_grouped_files_per_directory then
            explode_current_group()
          else
            close_current_group()
          end
          num_files_from_current_directory = 0
        elseif previous_pathname == nil or get_parent(previous_pathname) == get_parent(current_pathname) then
          num_files_from_current_directory = num_files_from_current_directory + 1
        else
          if num_files_from_current_directory > max_grouped_files_per_directory then
            explode_current_group()
          else
            close_current_group()
          end
          num_files_from_current_directory = 0
        end
      else
        error('Unexpected grouping strategy "' .. group_files .. '"')
      end
      group_next, ungroup_next = false, false
      previous_pathname = current_pathname
      table.insert(current_group, current_pathname)
    end
  end

  -- Close or explode any trailing group.
  if group_files == "auto" and num_files_from_current_directory > max_grouped_files_per_directory then
    explode_current_group()
  else
    close_current_group()
  end

  return pathname_groups
end

-- Run all processing steps on a group of files.
local function process_files(pathnames, options)
  -- Require packages.
  local get_option = require("explcheck-config").get_option
  local new_issues = require("explcheck-issues").new_issues

  -- Prepare empty processing states for all files in the group.
  local states = {}
  for _, pathname in ipairs(pathnames) do
    local file = assert(io.open(pathname, "r"))
    local state = {
      pathname = pathname,
      content = assert(file:read("*a")),
      issues = new_issues(pathname, options),
      results = {},
    }
    assert(file:close())
    table.insert(states, state)
  end
  assert(#states == #pathnames)

  -- Run all processing steps.
  local step_filenames = {'preprocessing', 'lexical-analysis', 'syntactic-analysis', 'semantic-analysis'}
  for step_number, step_filename in ipairs(step_filenames) do
    local step = require(string.format('explcheck-%s', step_filename))
    -- Process all files in the group with this step.
    for substep_number, process_with_substep in ipairs(step.substeps) do
      -- Process all files in the group with this substep.
      for file_number, state in ipairs(states) do
        -- Get options.
        local fail_fast = get_option('fail_fast', options, state.pathname)
        local stop_after = get_option('stop_after', options, state.pathname)
        local stop_early_when_confused = get_option('stop_early_when_confused', options, state.pathname)
        -- If we stopped early for this file, skip this (sub)step for this file also.
        local is_confused, reason
        if state.results.stopped_early ~= nil then
          goto continue
        end
        -- If the step is confused by this file, skip it and all following steps.
        if substep_number == 1 and stop_early_when_confused then
          is_confused, reason = step.is_confused(state.pathname, state.results, options)
          if is_confused then
            assert(reason ~= nil)
            state.results.stopped_early = {
              when = string.format("before the %s", step.name),
              reason = reason,
            }
            goto continue
          end
        end
        -- Run the substep for this file.
        process_with_substep(states, file_number, options)
        if substep_number == #step.substeps then
          -- If the step ended with errors for this file, skip all following steps for this file.
          if step_number < #step_filenames and fail_fast and #state.issues.errors > 0 then
            state.results.stopped_early = {
              when = string.format("after %s", step.name),
              reason = "it ended with errors and the option `fail_fast` was enabled",
            }
            goto continue
          end
          -- If the step is supposed to be the last step, skip all following steps.
          if step_number < #step_filenames and (stop_after == step_filename or stop_after == step.name) then
            state.results.stopped_early = {
              when = string.format("after %s", step.name),
              reason = "that was the final step according to the option `stop_after`",
            }
            goto continue
          end
        end
        ::continue::
      end
    end
  end

  -- Close all issue registries.
  for _, state in ipairs(states) do
    state.issues:close()
  end

  return states
end

return {
  check_pathname = check_pathname,
  convert_byte_to_line_and_column = convert_byte_to_line_and_column,
  get_basename = get_basename,
  get_parent = get_parent,
  get_stem = get_stem,
  get_suffix = get_suffix,
  group_pathnames = group_pathnames,
  identity = identity,
  process_files = process_files,
}
