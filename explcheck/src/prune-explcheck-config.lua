#!/usr/bin/env texlua
-- A checker that reads the user configuration of the static analyzer explcheck and regression test results
-- and then tests which parts of the configuration can be removed without affecting the results of the static analysis.

local kpse = require("kpse")
kpse.set_program_name("texlua", "prune-explcheck-config")

local lfs = require("lfs")

local config = require("explcheck-config")
local humanize = require("explcheck-format").humanize
local new_issues = require("explcheck-issues").new_issues
local utils = require("explcheck-utils")

local get_stem = utils.get_stem
local get_suffix = utils.get_suffix
local group_pathnames = utils.group_pathnames
local process_files = utils.process_files

local default_config = config.default_config
local get_user_config = config.get_user_config
local get_package = config.get_package
local get_filename = config.get_filename

-- Read a list of files.
local function read_filelist(filelist_pathname)
  local pathnames = {}
  for pathname in io.lines(filelist_pathname) do
    table.insert(pathnames, pathname)
  end
  print(string.format('Read %s files listed in "%s".', humanize(#pathnames), filelist_pathname))
  return pathnames
end

-- Read regression test results.
local function read_results(results_pathname)
  local num_issues = 0
  local seen_pathnames = {}
  local results = {
    pathnames = {},
    issues = {},
  }
  for issue_pathname in lfs.dir(results_pathname) do
    if get_suffix(issue_pathname) ~= ".txt" then
      goto continue
    end
    num_issues = num_issues + 1
    local issue = get_stem(issue_pathname)
    for pathname in io.lines(results_pathname .. "/" .. issue_pathname) do
      if seen_pathnames[pathname] == nil then
        seen_pathnames[pathname] = true
        table.insert(results.pathnames, pathname)
        results.issues[pathname] = new_issues()
      end
      results.issues[pathname]:add(issue)
    end
    ::continue::
  end
  for _, issues in pairs(results.issues) do
    issues:close()
  end
  print(string.format('Read %s issues and %s files listed in "%s".', humanize(num_issues), humanize(#results.pathnames), results_pathname))
  return results
end

-- For each file from regression test results, try to remove all options in the user configuration that apply to it and check
-- whether this affects the results of the static analysis or not. Also check whether there exist sections that apply to no files
-- that were used in regression tests.
local function main(filelist_pathname, results_pathname)
  -- Read the user config
  local user_config, user_config_pathname = get_user_config()
  assert(user_config ~= nil)
  assert(user_config_pathname ~= nil)

  -- Read the list of all files and regression test results.
  local filelist = read_filelist(filelist_pathname)
  local results = read_results(results_pathname)

  local pathname_groups = group_pathnames(filelist)
  local pathname_group_index = {}
  for pathname_group_number, pathname_group in ipairs(pathname_groups) do
    for pathname_number, pathname in ipairs(pathname_group) do
      pathname_group_index[pathname] = {pathname_group_number, pathname_group, pathname_number}
    end
  end
  local pathname_group_results = {}

  local num_options = 0
  local key_locations = {
    seen = {},
    results = {},
    to_remove = {},
  }

  -- Try to remove a single option.
  local function try_to_remove_option(pathname, key, key_location, default_value, expected_issues)
    if key_locations.results[key_location] == nil then
      table.insert(key_locations.seen, key_location)
      key_locations.results[key_location] = {}
    end

    num_options = num_options + 1

    -- Collect the cached results for the group of files or run all steps of the static analysis and cache the results.
    local pathname_group_number, pathname_group, pathname_number = table.unpack(pathname_group_index[pathname])
    if pathname_group_results[pathname_group_number] == nil or pathname_group_results[pathname_group_number][key_location] == nil then
      local options = {[key] = default_value}
      local states = process_files(pathname_group, options)
      assert(#states == #pathname_group)

      local group_actual_issues = {}
      for _, state in ipairs(states) do
        table.insert(group_actual_issues, state.issues)
      end
      assert(#group_actual_issues == #states)

      if pathname_group_results[pathname_group_number] == nil then
        pathname_group_results[pathname_group_number] = {}
      end
      pathname_group_results[pathname_group_number][key_location] = group_actual_issues
    end
    local actual_issues = pathname_group_results[pathname_group_number][key_location][pathname_number]

    -- Compare the expected results of the static analysis with the actual results.
    local result = actual_issues:has_same_codes_as(expected_issues)
    table.insert(key_locations.results[key_location], result)
  end

  -- Try to remove all options in a section of the config file.
  local function try_to_remove_all_options(pathname, options, options_location, expected_issues)
    local keys = {}
    for key, _ in pairs(options) do
      table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      local value = options[key]
      assert(value ~= nil)
      if type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean' then
        local default_value = default_config.defaults[key]
        assert(default_value ~= nil)
        local key_location = string.format('Option "%s" in %s', key, options_location)
        try_to_remove_option(pathname, key, key_location, default_value, expected_issues)
      elseif type(value) == 'table' then
        for i, item in ipairs(value) do
          local key_location = string.format('Item "%s" in option "%s" in %s', item, key, options_location)
          local smaller_value = {}
          for j = 1, #value do
            if i ~= j then
              table.insert(smaller_value, value[j])
            end
          end
          try_to_remove_option(pathname, key, key_location, smaller_value, expected_issues)
        end
      end
    end
  end

  -- Try to remove all options for the individual files from the test results.
  for _, pathname in ipairs(filelist) do
    local expected_issues = results.issues[pathname]
    if expected_issues == nil then
      expected_issues = new_issues()
      expected_issues:close()
    end
    -- If the configuration specifies options for this filename, check them.
    local filename = get_filename(pathname)
    if user_config.filename and user_config.filename[filename] ~= nil then
      local options_location = string.format('section [filename."%s"]', filename)
      try_to_remove_all_options(pathname, user_config.filename[filename], options_location, expected_issues)
    end
    -- If the configuration specifies options for this package, check them.
    local package = get_package(pathname)
    if user_config.package and user_config.package[package] ~= nil then
      local options_location = string.format('section [package."%s"]', package)
      try_to_remove_all_options(pathname, user_config.package[package], options_location, expected_issues)
    end
  end

  -- Try to remove sections that apply to no filenames that entered the regression tests.
  local visited_sections = {
    filename = {},
    package = {},
  }
  for _, pathname in ipairs(filelist) do
    local filename = get_filename(pathname)
    if user_config.filename and user_config.filename[filename] ~= nil then
      visited_sections.filename[filename] = true
    end
    local package = get_package(pathname)
    if user_config.package and user_config.package[package] ~= nil then
      visited_sections.package[package] = true
    end
  end
  for key, _ in pairs(visited_sections) do
    if user_config[key] ~= nil then
      for value, _ in pairs(user_config[key]) do
        if visited_sections[key][value] == nil then
          local options_location = string.format('Section [%s."%s"]', key, value)
          table.insert(key_locations.to_remove, options_location)
        end
      end
    end
  end

  -- Collect all options that can be removed without affecting any files from the test results.
  for _, key_location in ipairs(key_locations.seen) do
    for _, result in ipairs(key_locations.results[key_location]) do
      if not result then
        goto skip_key_location
      end
    end
    table.insert(key_locations.to_remove, key_location)
    ::skip_key_location::
  end

  -- Print the results.
  io.write(string.format('Checked %s different options in file "%s"', humanize(num_options), user_config_pathname))
  if #key_locations.to_remove == 0 then
    print(string.format(', none of which can be removed without affecting files listed in "%s".', results_pathname))
  else
    print(
      string.format(
        ', %s of which can be removed without affecting files listed in "%s":',
        humanize(#key_locations.to_remove),
        results_pathname
      )
    )
    for _, key_location in ipairs(key_locations.to_remove) do
      print(string.format('- %s', key_location))
    end
  end

  if #key_locations.to_remove > 0 then
    os.exit(1)
  end
end

local function print_usage()
  print("Usage: " .. arg[0] .. " FILE_LIST TEST_RESULTS\n")
  print("Test which parts of the user config file can be removed without affecting regression test results.")
end

if #arg ~= 2 then
  print_usage()
  os.exit(1)
else
  local filelist_pathname = arg[1]
  local results_pathname = arg[2]
  main(filelist_pathname, results_pathname)
end
