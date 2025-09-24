#!/usr/bin/env texlua
-- A command-line interface for the static analyzer explcheck that exports issues and code coverage into separate files.

local kpse = require("kpse")
kpse.set_program_name("texlua", "collect-explcheck-issues-and-code-coverage")

local evaluation = require("explcheck-evaluation")
local format = require("explcheck-format")
local utils = require("explcheck-utils")
local sort_issues = require("explcheck-issues").sort_issues

local format_ratio = format.format_ratio
local humanize = format.humanize
local pluralize = format.pluralize
local titlecase = format.titlecase

local new_file_results = evaluation.new_file_results
local new_aggregate_results = evaluation.new_aggregate_results

-- Process all input files and export issues and code coverage.
local function main(pathname_groups, output_issue_dirname)
  local issue_pathnames = {}
  local aggregate_evaluation_results = new_aggregate_results()
  for _, pathname_group in ipairs(pathname_groups) do
    local is_ok, error_message = xpcall(function()
      -- Run all processing steps and collect issues and analysis results.
      local states = utils.process_files(pathname_group)
      assert(#states == #pathname_group)
      for pathname_number, state in ipairs(states) do
        assert(pathname_group[pathname_number] == state.pathname)
        -- Record issues.
        local issues = state.issues
        for _, issue_table in ipairs({issues.warnings, issues.errors}) do
          for _, issue in ipairs(sort_issues(issue_table)) do
            local code = issue[1]
            if issue_pathnames[code] == nil then
              issue_pathnames[code] = {}
            end
            issue_pathnames[code][state.pathname] = true
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
  end
  -- Sort and export issues.
  local output_issue_files = {}
  for code, pathnames in pairs(issue_pathnames) do
    local sorted_pathnames = {}
    for pathname, _ in pairs(pathnames) do
      table.insert(sorted_pathnames, pathname)
    end
    table.sort(sorted_pathnames)
    for _, pathname in ipairs(sorted_pathnames) do
      if output_issue_files[code] == nil then
        output_issue_files[code] = assert(io.open(string.format("%s/%s.txt", output_issue_dirname, code), "w"))
      end
      output_issue_files[code]:write(pathname, "\n")
    end
  end
  for code, _ in pairs(output_issue_files) do
    assert(output_issue_files[code]:close())
  end
  -- Export coverage.
  local output_coverage_file = assert(io.open(string.format("%s/COVERAGE", output_issue_dirname), "w"))
  local num_total_bytes = aggregate_evaluation_results.num_total_bytes
  local num_expl_bytes = aggregate_evaluation_results.num_expl_bytes
  local num_tokens = aggregate_evaluation_results.num_tokens
  local num_well_understood_tokens = aggregate_evaluation_results.num_well_understood_tokens
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
  assert(output_coverage_file:close())
end

local files_from = arg[1]
local output_issue_dirname = arg[2]

-- Collect pathnames.
local input_pathnames, allow_pathname_separators = {}, {}
local file = assert(io.open(files_from, "r"))
for pathname in file:lines() do
  table.insert(input_pathnames, pathname)
  table.insert(allow_pathname_separators, false)
end

-- Group pathnames.
local input_pathname_groups = utils.group_pathnames(input_pathnames, nil, allow_pathname_separators)

main(input_pathname_groups, output_issue_dirname)
