#!/usr/bin/env texlua
-- Merge collected issues and code coverage.

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
    local code, pathname = input_issue_code_and_pathname:match("^([^ ]+) (.+)$")
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
local all_aggregate_evaluation_results, nondoc_aggregate_evaluation_results = {}, {}
for _, aggregate_evaluation_results in ipairs({all_aggregate_evaluation_results, nondoc_aggregate_evaluation_results}) do
  aggregate_evaluation_results.num_total_bytes = 0
  aggregate_evaluation_results.num_expl_bytes = 0
  aggregate_evaluation_results.num_tokens = 0
  aggregate_evaluation_results.num_well_understood_tokens = 0
end

for input_coverage_file_number = 1, num_input_files do
  local input_coverage_file_pathname = string.format(input_coverage_file_pathname_template, input_coverage_file_number)
  local input_coverage_file = assert(io.open(input_coverage_file_pathname, "r"))

  for _, aggregate_evaluation_results in ipairs({all_aggregate_evaluation_results, nondoc_aggregate_evaluation_results}) do
    local coverage_values = assert(input_coverage_file:read("*line"))
    local current_num_total_bytes, current_num_expl_bytes, current_num_tokens, current_num_well_understood_tokens
      = coverage_values:match("^(%d+) (%d+) (%d+) (%d+)$")
    aggregate_evaluation_results.num_total_bytes = aggregate_evaluation_results.num_total_bytes + tonumber(current_num_total_bytes)
    aggregate_evaluation_results.num_expl_bytes = aggregate_evaluation_results.num_expl_bytes + tonumber(current_num_expl_bytes)
    aggregate_evaluation_results.num_tokens = aggregate_evaluation_results.num_tokens + tonumber(current_num_tokens)
    aggregate_evaluation_results.num_well_understood_tokens
      = aggregate_evaluation_results.num_well_understood_tokens + tonumber(current_num_well_understood_tokens)
  end

  assert(input_coverage_file:close())
end

-- Export the code coverage.
local output_coverage_file = assert(io.open(output_coverage_file_pathname, "w"))
for _, aggregate_evaluation_title_and_results in ipairs({
  {"Package files outside the `/doc` tree", nondoc_aggregate_evaluation_results},
  {"All package files", all_aggregate_evaluation_results},
}) do
  local result_title, aggregate_evaluation_results = table.unpack(aggregate_evaluation_title_and_results)
  assert(
    output_coverage_file:write(
      string.format(
        "%s: %s well-understood expl3 %s (%s of %s expl3 tokens, ~%s of %s total bytes)\n",
        result_title,
        titlecase(humanize(aggregate_evaluation_results.num_well_understood_tokens)),
        pluralize("token", aggregate_evaluation_results.num_well_understood_tokens),
        format_ratio(aggregate_evaluation_results.num_well_understood_tokens, aggregate_evaluation_results.num_tokens),
        humanize(aggregate_evaluation_results.num_tokens),
        format_ratio(
          aggregate_evaluation_results.num_well_understood_tokens * aggregate_evaluation_results.num_expl_bytes,
          aggregate_evaluation_results.num_tokens * aggregate_evaluation_results.num_total_bytes
        ),
        humanize(aggregate_evaluation_results.num_total_bytes)
      )
    )
  )
end
assert(output_coverage_file:close())
