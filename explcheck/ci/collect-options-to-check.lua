#!/usr/bin/env texlua
-- Collect all options to check for redundancy and prepare task files for them.

local kpse = require("kpse")
kpse.set_program_name("texlua", "collect-options-to-check")

local config = require("explcheck-config")
local format = require("explcheck-format")

local get_user_config = config.get_user_config
local get_package = config.get_package
local get_filename = config.get_filename

local humanize = format.humanize
local pluralize = format.pluralize

local input_file_pathname = arg[1]
local output_task_pathname_template = arg[2]

-- Read the user config
local user_config, user_config_pathname = get_user_config()
assert(user_config ~= nil)
assert(user_config_pathname ~= nil)

-- Collect pathnames.
local input_pathnames = {}
local input_file = assert(io.open(input_file_pathname, "r"))
for pathname in input_file:lines() do
  table.insert(input_pathnames, pathname)
end
assert(input_file:close())

-- Try to remove sections that apply to no filenames that entered the regression tests.
local visited_section_pathnames = {
  filename = {},
  package = {},
}
local visited_section_list = {}
local num_affected_pathnames = 0
for _, pathname in ipairs(input_pathnames) do
  local is_pathname_affected = false
  local filename = get_filename(pathname)
  if user_config.filename and user_config.filename[filename] ~= nil then
    if visited_section_pathnames.filename[filename] == nil then
      visited_section_pathnames.filename[filename] = {}
      table.insert(visited_section_list, {'filename', filename})
    end
    table.insert(visited_section_pathnames.filename[filename], pathname)
    is_pathname_affected = true
  end
  local package = get_package(pathname)
  if user_config.package and user_config.package[package] ~= nil then
    if visited_section_pathnames.package[package] == nil then
      visited_section_pathnames.package[package] = {}
      table.insert(visited_section_list, {'package', package})
    end
    table.insert(visited_section_pathnames.package[package], pathname)
    is_pathname_affected = true
  end
  if is_pathname_affected then
    num_affected_pathnames = num_affected_pathnames + 1
  end
end
for key, _ in pairs(visited_section_pathnames) do
  if user_config[key] ~= nil then
    for value, _ in pairs(user_config[key]) do
      if visited_section_pathnames[key][value] == nil then
        print(string.format('Section [%s."%s"] can be removed from the file "%s".', key, value, user_config_pathname))
        os.exit(1)
      end
    end
  end
end

-- Export task files.
local output_task_number = 0
for _, section_and_subsection in ipairs(visited_section_list) do
  local section, subsection = table.unpack(section_and_subsection)
  local pathnames = visited_section_pathnames[section][subsection]
  local options = user_config[section][subsection]
  local option_keys = {}
  for key, _ in pairs(options) do
    table.insert(option_keys, key)
  end
  table.sort(option_keys)
  for _, option_key in ipairs(option_keys) do
    output_task_number = output_task_number + 1
    local output_task_pathname = string.format(output_task_pathname_template, output_task_number)
    local output_task = assert(io.open(output_task_pathname, "w"))
    assert(output_task:write(string.format('%s %s %s\n', section, subsection, option_key)))
    for _, pathname in ipairs(pathnames) do
      assert(output_task:write(string.format('%s\n', pathname)))
    end
    assert(output_task:close())
  end
end
print(
  string.format(
    'Collected %s %s affecting %s %s from the files "%s" and "%s".',
    humanize(output_task_number),
    pluralize('option', output_task_number),
    humanize(num_affected_pathnames),
    pluralize('package file', num_affected_pathnames),
    user_config_pathname,
    input_file_pathname
  )
)
