#!/usr/bin/env texlua
-- Process a list of pathnames with explcheck, collecting issues and code coverage.

local kpse = require("kpse")
kpse.set_program_name("texlua", "collect-explcheck-issues-and-code-coverage")

local evaluation = require("explcheck-evaluation")
local format = require("explcheck-format")
local utils = require("explcheck-utils")
local sort_issues = require("explcheck-issues").sort_issues

local humanize = format.humanize
local pluralize = format.pluralize

local get_basename = utils.get_basename
local process_files = utils.process_files
local group_pathnames = utils.group_pathnames

local new_file_results = evaluation.new_file_results
local new_aggregate_results = evaluation.new_aggregate_results

local input_file_pathname_template = arg[1]
local output_issue_file_pathname_template = arg[2]
local output_coverage_file_pathname_template = arg[3]
local worker_number = tonumber(arg[4])

-- Collect pathnames.
local input_pathnames, allow_pathname_separators = {}, {}
local input_file_pathname = string.format(input_file_pathname_template, worker_number)
local input_file = assert(io.open(input_file_pathname, "r"))
for pathname in input_file:lines() do
  table.insert(input_pathnames, pathname)
  table.insert(allow_pathname_separators, false)
end
assert(input_file:close())

-- Group pathnames.
local input_pathname_groups = group_pathnames(input_pathnames, nil, allow_pathname_separators)

-- Collect and export issues.
local output_issue_file_pathname = string.format(output_issue_file_pathname_template, worker_number)
local output_issue_file = assert(io.open(output_issue_file_pathname, "w"))
local aggregate_evaluation_results = new_aggregate_results()
for pathname_group_number, pathname_group in ipairs(input_pathname_groups) do
  local is_ok, error_message = xpcall(function()
    -- Run all processing steps and collect issues and analysis results.
    local states = process_files(pathname_group)
    assert(#states == #pathname_group)
    for pathname_number, state in ipairs(states) do
      assert(pathname_group[pathname_number] == state.pathname)
      -- Record issues.
      local issues = state.issues
      for _, issue_table in ipairs({issues.warnings, issues.errors}) do
        for _, issue in ipairs(sort_issues(issue_table)) do
          local code = issue[1]
          assert(output_issue_file:write(string.format('%s %s\n', code, state.pathname)))
        end
      end
      -- Update the aggregate evaluation results.
      local file_evaluation_results = new_file_results(state)
      aggregate_evaluation_results:add(file_evaluation_results)
    end
  end, debug.traceback)
  if not is_ok then
    error("Failed to process " .. table.concat(pathname_group, ', ') .. ": " .. tostring(error_message), 0)
  end
  -- Display the current status.
  print(
    string.format(
      '[Worker %02d, %s] Finished %s out of %s %s in "%s" (last group: "%s"%s%s).',
      worker_number,
      os.date(),
      humanize(pathname_group_number),
      humanize(#input_pathname_groups),
      pluralize("file group", #input_pathname_groups),
      input_file_pathname,
      get_basename(pathname_group[1]),
      #pathname_group > 1 and string.format(
        " and %s other %s",
        humanize(#pathname_group - 1),
        pluralize("file", #pathname_group - 1)
      ) or "",
      pathname_group_number < #input_pathname_groups and string.format(
        ', next group: "%s"%s',
        get_basename(input_pathname_groups[pathname_group_number + 1][1]),
        #input_pathname_groups[pathname_group_number + 1] > 1 and string.format(
          " and %s other %s",
          humanize(#input_pathname_groups[pathname_group_number + 1] - 1),
          pluralize("file", #input_pathname_groups[pathname_group_number + 1] - 1)
        ) or ""
      ) or ""
    )
  )
end
assert(output_issue_file:close())

-- Export code coverage.
local output_coverage_file_pathname = string.format(output_coverage_file_pathname_template, worker_number)
local output_coverage_file = assert(io.open(output_coverage_file_pathname, "w"))
assert(
  output_coverage_file:write(
    string.format("%d %d %d %d\n",
      aggregate_evaluation_results.num_total_bytes,
      aggregate_evaluation_results.num_expl_bytes,
      aggregate_evaluation_results.num_tokens,
      aggregate_evaluation_results.num_well_understood_tokens
    )
  )
)
assert(output_coverage_file:close())
