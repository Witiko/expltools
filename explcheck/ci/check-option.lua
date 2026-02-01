#!/usr/bin/env texlua
-- Take a single option and check whether omitting the options in that section changes detections.

local kpse = require("kpse")
kpse.set_program_name("texlua", "check-option")

local lfs = require("lfs")

local config = require("explcheck-config")
local new_issues = require("explcheck-issues").new_issues
local utils = require("explcheck-utils")

local default_config = config.default_config
local get_user_config = config.get_user_config

local get_stem = utils.get_stem
local get_suffix = utils.get_suffix
local group_pathnames = utils.group_pathnames
local process_files = utils.process_files

local input_file_pathname = arg[1]
local input_issue_directory_pathname = arg[2]
local input_task_pathname = arg[3]

-- Read the user config
local user_config, user_config_pathname = get_user_config()
assert(user_config ~= nil)
assert(user_config_pathname ~= nil)

-- Collect all pathnames.
local pathnames, allow_pathname_separators = {}, {}
local input_file = assert(io.open(input_file_pathname, "r"))
for pathname in input_file:lines() do
  table.insert(pathnames, pathname)
  table.insert(allow_pathname_separators, false)
end
assert(input_file:close())

-- Group pathnames.
local pathname_groups = group_pathnames(pathnames, nil, allow_pathname_separators)

-- Index the file groups.
local pathname_group_index = {}
for pathname_group_number, pathname_group in ipairs(pathname_groups) do
  for pathname_number, pathname in ipairs(pathname_group) do
    pathname_group_index[pathname] = {pathname_group_number, pathname_group, pathname_number}
  end
end
local pathname_group_results = {}

-- Read the issues.
local results = {
  pathnames = {},
  issues = {},
}
do
  local seen_pathnames = {}
  for issue_pathname in lfs.dir(input_issue_directory_pathname) do
    if get_suffix(issue_pathname) ~= ".txt" then
      goto continue
    end
    local issue = get_stem(issue_pathname)
    for pathname in io.lines(string.format("%s/%s", input_issue_directory_pathname, issue_pathname)) do
      if seen_pathnames[pathname] == nil then
        seen_pathnames[pathname] = true
        table.insert(results.pathnames, pathname)
        local file = assert(io.open(pathname, "r"))
        local content = assert(file:read("*a"))
        assert(file:close())
        results.issues[pathname] = new_issues(pathname, content)
      end
      results.issues[pathname]:add(issue)
    end
    ::continue::
  end
end
for _, issues in pairs(results.issues) do
  issues:close()
end

-- Read the task file.
local input_task = assert(io.open(input_task_pathname, "r"))
local section, subsection, option_key, table_index = assert(input_task:read("*line"):match("^([^ ]*) (.*) ([^ ]*) (%d+)$"))
table_index = tonumber(table_index)
local options = user_config[section][subsection]
local task_pathnames = {}
for pathname in input_task:lines() do
  table.insert(task_pathnames, pathname)
end

-- Determine the option location and how it should be checked based on its type.
local options_location = string.format('section [%s."%s"]', section, subsection)
local option_value = options[option_key]
assert(option_value ~= nil)
local option_key_location, updated_option_value
if type(option_value) == 'string' or type(option_value) == 'number' or type(option_value) == 'boolean' then
  assert(table_index == 0)
  updated_option_value = default_config.defaults[option_key]
  assert(updated_option_value ~= nil)
  option_key_location = string.format('Option "%s" in %s', option_key, options_location)
else
  assert(type(option_value) == 'table')
  assert(table_index ~= 0)
  local option_item = option_value[table_index]
  assert(option_item ~= nil)
  option_key_location = string.format('Item "%s" in option "%s" in %s', option_item, option_key, options_location)
  updated_option_value = {}
  for other_table_index = 1, #option_value do
    if table_index ~= other_table_index then
      local other_option_item = option_value[other_table_index]
      table.insert(updated_option_value, other_option_item)
    end
  end
end

-- Check the option for every file that it affects.
local option_key_locations = {
  seen = {},
  results = {},
}

for _, pathname in ipairs(task_pathnames) do
  if option_key_locations.results[option_key_location] == nil then
    table.insert(option_key_locations.seen, option_key_location)
    option_key_locations.results[option_key_location] = {}
  end

  -- Collect the cached results for the group of files or run all steps of the static analysis and cache the results.
  local pathname_group_number, pathname_group, pathname_number = table.unpack(pathname_group_index[pathname])
  if pathname_group_results[pathname_group_number] == nil or
      pathname_group_results[pathname_group_number][option_key_location] == nil then
    local updated_options = {[option_key] = updated_option_value}
    local states = process_files(pathname_group, updated_options)
    assert(#states == #pathname_group)

    local group_actual_issues = {}
    for _, state in ipairs(states) do
      table.insert(group_actual_issues, state.issues)
    end
    assert(#group_actual_issues == #states)

    if pathname_group_results[pathname_group_number] == nil then
      pathname_group_results[pathname_group_number] = {}
    end
    pathname_group_results[pathname_group_number][option_key_location] = group_actual_issues
  end
  local actual_issues = pathname_group_results[pathname_group_number][option_key_location][pathname_number]

  -- Compare the expected results of the static analysis with the actual results.
  local expected_issues = results.issues[pathname]
  if expected_issues == nil then
    expected_issues = new_issues()
    expected_issues:close()
  end
  local result = actual_issues:has_same_codes_as(expected_issues)
  table.insert(option_key_locations.results[option_key_location], result)
end

-- Collect all options that can be removed without affecting any files from the test results.
option_key_locations.to_remove = {}
for _, seen_option_key_location in ipairs(option_key_locations.seen) do
  for _, result in ipairs(option_key_locations.results[seen_option_key_location]) do
    if not result then
      goto skip_option_key_location
    end
  end
  table.insert(option_key_locations.to_remove, seen_option_key_location)
  ::skip_option_key_location::
end

-- Print the results.
for _, redundant_option_key_location in ipairs(option_key_locations.to_remove) do
  print(
    string.format(
      '%s can be removed from the file "%s".',
      redundant_option_key_location,
      user_config_pathname
    )
  )
end
os.exit(#option_key_locations.to_remove > 0 and 1 or 0)
