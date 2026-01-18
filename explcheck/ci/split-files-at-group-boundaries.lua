#!/usr/bin/env texlua
-- Split a list of pathnames into many, making sure that files from the same directory that can be grouped by explcheck are kept together.

local kpse = require("kpse")
kpse.set_program_name("texlua", "split-files-at-group-boundaries")

local format = require("explcheck-format")
local utils = require("explcheck-utils")

local humanize = format.humanize
local pluralize = format.pluralize

local group_pathnames = utils.group_pathnames

local input_file_pathname = arg[1]
local output_file_pathname_template = arg[2]
local num_output_files = tonumber(arg[3])

-- Collect pathnames.
local input_pathnames, allow_pathname_separators = {}, {}
local input_file = assert(io.open(input_file_pathname, "r"))
for pathname in input_file:lines() do
  table.insert(input_pathnames, pathname)
  table.insert(allow_pathname_separators, false)
end
assert(input_file:close())

-- Group pathnames.
local input_pathname_groups = group_pathnames(input_pathnames, nil, allow_pathname_separators)

print(
  string.format(
    'Collected %s %s forming %s %s from the file "%s".',
    humanize(#input_pathnames),
    pluralize('package file', #input_pathnames),
    humanize(#input_pathname_groups),
    pluralize('file group', #input_pathname_groups),
    input_file_pathname
  )
)

-- Open output files.
local output_files = {}
for output_file_number = 1, num_output_files do
  local output_file_pathname = string.format(output_file_pathname_template, output_file_number)
  local output_file = assert(io.open(output_file_pathname, "w"))
  table.insert(output_files, output_file)
end

-- Split pathname groups.
for pathname_group_number, pathname_group in ipairs(input_pathname_groups) do
  local output_file_number = math.floor((pathname_group_number - 1) / #input_pathname_groups * num_output_files) + 1
  local output_file = output_files[output_file_number]
  for _, pathname in ipairs(pathname_group) do
    assert(output_file:write(string.format("%s\n", pathname)))
  end
end

-- Close output files.
for _, output_file in ipairs(output_files) do
  assert(output_file:close())
end
