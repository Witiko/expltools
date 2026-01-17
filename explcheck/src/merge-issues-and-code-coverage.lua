#!/usr/bin/env texlua
-- Merge collected issues and code coverage.

local kpse = require("kpse")
kpse.set_program_name("texlua", "merge-issues-and-code-coverage")

local format = require("explcheck-format")

local format_ratio = format.format_ratio
local humanize = format.humanize
local pluralize = format.pluralize
local titlecase = format.titlecase

local input_issue_file_pathname_template = arg[1]
local input_coverage_file_pathname_template = arg[2]
local output_issue_directory_pathname = arg[3]
local output_coverage_file_pathname = arg[4]
local num_input_files = tonumber(arg[5])

-- Collect the issues.
local issue_pathnames = {}
for input_issue_file_number = 1, num_input_files do
  local input_issue_file_pathname = string.format(input_issue_file_pathname_template, input_issue_file_number)
  local input_issue_file = assert(io.open(input_issue_file_pathname, "r"))

  for input_issue_code_and_pathname in input_issue_file:lines() do
    local code, pathname = input_issue_code_and_pathname:match("([^ ]+) (.+)")
    if issue_pathnames[code] == nil then
      issue_pathnames[code] = {}
    end
    issue_pathnames[code][pathname] = true
  end

  assert(input_issue_file:close())
end

-- Sort and export the issues.
local output_issue_files = {}
for code, pathnames in pairs(issue_pathnames) do
  local sorted_pathnames = {}
  for pathname, _ in pairs(pathnames) do
    table.insert(sorted_pathnames, pathname)
  end
  table.sort(sorted_pathnames)
  for _, pathname in ipairs(sorted_pathnames) do
    if output_issue_files[code] == nil then
      output_issue_files[code] = assert(io.open(string.format("%s/%s.txt", output_issue_directory_pathname, code), "w"))
    end
    assert(output_issue_files[code]:write(pathname, "\n"))
  end
end
for code, _ in pairs(output_issue_files) do
  assert(output_issue_files[code]:close())
end

-- Collect the code coverages.
local num_total_bytes, num_expl_bytes, num_tokens, num_well_understood_tokens = 0, 0, 0, 0
for input_coverage_file_number = 1, num_input_files do
  local input_coverage_file_pathname = string.format(input_coverage_file_pathname_template, input_coverage_file_number)
  local input_coverage_file = assert(io.open(input_coverage_file_pathname, "r"))

  local coverage_values = assert(input_coverage_file:read("*line"))
  local current_num_total_bytes, current_num_expl_bytes, current_num_tokens, current_num_well_understood_tokens
    = coverage_values:match("(%d+) (%d+) (%d+) (%d+)")
  num_total_bytes = num_total_bytes + tonumber(current_num_total_bytes)
  num_expl_bytes = num_expl_bytes + tonumber(current_num_expl_bytes)
  num_tokens = num_tokens + tonumber(current_num_tokens)
  num_well_understood_tokens = num_well_understood_tokens + tonumber(current_num_well_understood_tokens)

  assert(input_coverage_file:close())
end

-- Export the code coverage.
local output_coverage_file = assert(io.open(output_coverage_file_pathname, "w"))
assert(
  output_coverage_file:write(
    string.format(
      "%s well-understood expl3 %s (%s of %s expl3 tokens, ~%s of %s total bytes)\n",
      titlecase(humanize(num_well_understood_tokens)),
      pluralize("token", num_well_understood_tokens),
      format_ratio(num_well_understood_tokens, num_tokens),
      humanize(num_tokens),
      format_ratio(num_well_understood_tokens * num_expl_bytes, num_tokens * num_total_bytes),
      humanize(num_total_bytes)
    )
  )
)
assert(output_coverage_file:close())
