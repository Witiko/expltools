-- A registry of warnings and errors identified by different processing steps.

local get_option = require("explcheck-config").get_option
local new_prefix_tree = require("explcheck-utils").new_prefix_tree  -- luacheck: ignore new_prefix_tree
local new_range_tree = require("explcheck-ranges").new_range_tree

local Issues = {}

-- Normalize an issue identifier or its prefix.
local function normalize_identifier(identifier)
  return identifier:lower()
end

function Issues.new(cls, pathname, content_length, options)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.closed = false
  --- Issue tables
  for _, issue_table_name in ipairs({"errors", "warnings"}) do
    self[issue_table_name] = {
      _identifier_index = {},
      _range_index = new_range_tree(1, content_length),
      _ignored_index = {},
      _num_ignored = 0,
    }
  end
  --- Seen issues
  self.seen_issues = {}
  --- Suppressed issues
  self.suppressed_issue_map = {}
  for issue_identifier, suppressed_issues in pairs(get_option("suppressed_issue_map", options, pathname)) do
    issue_identifier = normalize_identifier(issue_identifier)
    self.suppressed_issue_map[issue_identifier] = suppressed_issues
  end
  --- Ignored issues
  self.ignored_issues = {}
  self.max_ignored_issue_ratio = get_option("max_ignored_issue_ratio", options, pathname)
  for _, issue_identifier in ipairs(get_option("ignored_issues", options, pathname)) do
    self:ignore({identifier_prefix = issue_identifier})
  end
  return self
end

-- Convert an issue identifier to either a table of warnings or a table of errors.
function Issues:_get_issue_table(identifier)
  identifier = normalize_identifier(identifier)
  local prefix = identifier:sub(1, 1)
  if prefix == "s" or prefix == "w" then
    return self.warnings
  elseif prefix == "t" or prefix == "e" then
    return self.errors
  else
    assert(false, 'Identifier "' .. identifier .. '" has an unknown prefix "' .. prefix .. '"')
  end
end

-- Add an issue to the table of issues.
function Issues:add(identifier, message, range, context)
  if self.closed then
    error('Cannot add issues to a closed issue registry')
  end
  if range ~= nil and #range == 0 then
    error('Cannot ignore an empty byte range')
  end

  identifier = normalize_identifier(identifier)

  -- Discard duplicate issues.
  local range_start = (range ~= nil and range:start()) or false
  local range_end = (range ~= nil and range:stop()) or false
  if self.seen_issues[identifier] == nil then
    self.seen_issues[identifier] = {}
  end
  if self.seen_issues[identifier][context or ''] == nil then
    self.seen_issues[identifier][context or ''] = {}
  end
  if self.seen_issues[identifier][context or ''][range_start] == nil then
    self.seen_issues[identifier][context or ''][range_start] = {}
  end
  if self.seen_issues[identifier][context or ''][range_start][range_end] == nil then
    self.seen_issues[identifier][context or ''][range_start][range_end] = true
  else
    return
  end

  -- Suppress any dependent issues.
  if self.suppressed_issue_map[identifier] ~= nil then
    for _, suppressed_issue_identifier in ipairs(self.suppressed_issue_map[identifier]) do
      suppressed_issue_identifier = normalize_identifier(suppressed_issue_identifier)
      self:ignore({identifier_prefix = suppressed_issue_identifier, range = range, seen = true})
    end
  end

  -- Construct the issue.
  local issue = {identifier, message, range, context}

  -- Determine if the issue should be ignored.
  --
  -- TODO: Instead of running all `check()` functions, use efficient data structures such as prefix trees for identifier (prefixes)
  -- and segment trees for ranges, so that we can determine whether an issue should be ignored in time O(log n) instead of O(n).
  -- The segment trees should be implemented in the file `explcheck-ranges.lua`.
  for _, ignored_issue in ipairs(self.ignored_issues) do
    if ignored_issue.check(issue) then
      ignored_issue.seen = true
      return
    end
  end

  -- Add the issue to the table of issues.
  local issue_table = self:_get_issue_table(identifier)
  table.insert(issue_table, issue)
  if issue_table._identifier_index[identifier] == nil then
    issue_table._identifier_index[identifier] = {}
  end
  table.insert(issue_table._identifier_index[identifier], #issue_table)
end

-- Prevent issues from being present in the table of issues.
function Issues:ignore(ignored_issue)
  if self.closed then
    error('Cannot ignore issues in a closed issue registry')
  end
  if ignored_issue.range ~= nil and #ignored_issue.range == 0 then
    error('Cannot ignore an empty byte range')
  end
  if ignored_issue.identifier_prefix ~= nil then
    if #ignored_issue.identifier_prefix == 0 then
      error('Cannot ignore an empty identifier prefix')
    elseif #ignored_issue.identifier_prefix > 4 then
      error('An identifier prefix cannot be longer than four characters')
    end
  end

  -- Normalize the ignored identifier (prefix) and determine whether it's an exact identifier or a prefix.
  local is_exact_identifier
  if ignored_issue.identifier_prefix ~= nil then
    ignored_issue.identifier_prefix = normalize_identifier(ignored_issue.identifier_prefix)
    is_exact_identifier = #ignored_issue.identifier_prefix == 4
  end

  -- Determine whether an issue should be ignored based on its byte range and the ignored byte range.
  local function match_issue_range(issue_range)
    return ignored_issue.range:intersects(issue_range)
  end

  -- Determine whether an issue should be ignored based on its identifier and the ignored identifier prefix.
  local match_issue_identifier
  if is_exact_identifier then
    function match_issue_identifier(identifier)
      return identifier == ignored_issue.identifier_prefix
    end
  else
    function match_issue_identifier(identifier)
      return identifier:sub(1, #ignored_issue.identifier_prefix) == ignored_issue.identifier_prefix
    end
  end
  assert(match_issue_identifier ~= nil)

  -- Determine which issues should be ignored.
  local issue_tables, issue_number_lists
  if ignored_issue.identifier_prefix == nil and ignored_issue.range == nil then
    -- Prevent any issues.
    issue_tables = {self.warnings, self.errors}
    issue_number_lists = {}
    ignored_issue.check = function() return true end
  elseif ignored_issue.identifier_prefix == nil then
    -- Prevent any issues within the given range.
    issue_tables = {self.warnings, self.errors}
    issue_number_lists = {}
    ignored_issue.check = function(issue)
      local issue_range = issue[3]
      if issue_range == nil then  -- file-wide issue
        return false
      else  -- ranged issue
        return match_issue_range(issue_range)
      end
    end
  elseif ignored_issue.range == nil then
    -- Prevent any issues with the given identifier.
    assert(ignored_issue.identifier_prefix ~= nil)
    local issue_table = self:_get_issue_table(ignored_issue.identifier_prefix)
    local issue_number_list = issue_table._identifier_index[ignored_issue.identifier_prefix]
    issue_tables = {issue_table}
    if issue_number_list == nil and is_exact_identifier then
      -- If we are ignoring an exact identifier and there is no index, then we know that there are no matching issues and there is
      -- no need to scan all issues.
      issue_number_list = {}
    end
    issue_number_lists = {issue_number_list}
    ignored_issue.check = function(issue)
      local issue_identifier = issue[1]
      return match_issue_identifier(issue_identifier)
    end
  else
    -- Prevent any issues with the given identifier that are also either within the given range or file-wide.
    assert(ignored_issue.range ~= nil and ignored_issue.identifier_prefix ~= nil)
    local issue_table = self:_get_issue_table(ignored_issue.identifier_prefix)
    local issue_number_list = issue_table._identifier_index[ignored_issue.identifier_prefix]
    issue_tables = {issue_table}
    if issue_number_list == nil and is_exact_identifier then
      -- If we are ignoring an exact identifier and there is no index, then we know that there are no matching issues and there is
      -- no need to scan all issues.
      issue_number_list = {}
    end
    issue_number_lists = {issue_number_list}
    ignored_issue.check = function(issue)
      local issue_identifier = issue[1]
      local issue_range = issue[3]
      if issue_range == nil then  -- file-wide issue
        return match_issue_identifier(issue_identifier)
      else  -- ranged issue
        return match_issue_range(issue_range) and match_issue_identifier(issue_identifier)
      end
    end
  end
  assert(ignored_issue.check ~= nil)
  assert(issue_tables ~= nil)
  assert(issue_number_lists ~= nil)

  -- Remove the issue if it has already been added.
  --
  -- TODO: Instead of using `check()` functions, use efficient data structures such as prefix trees for identifier (prefixes) and
  -- segment trees for ranges, so that we can determine which past issues should be removed in time O(log n) instead of O(n).
  -- The segment trees should be implemented in the file `explcheck-ranges.lua`.
  for issue_table_number, issue_table in ipairs(issue_tables) do

    -- Check a single issue from the current issue table.
    local function check_issue(issue_number)
      local issue = issue_table[issue_number]
      assert(issue ~= nil)
      if ignored_issue.check(issue) then
        -- If the issue has been ignored, record that fact and schedule the issue for a later removal.
        ignored_issue.seen = true
        if issue_table._ignored_index[issue_number] == nil then
          issue_table._ignored_index[issue_number] = true
          issue_table._num_ignored = issue_table._num_ignored + 1
        end
      end
    end

    local issue_numbers = issue_number_lists[issue_table_number]
    if issue_numbers ~= nil then
      -- If the ignored issue has a corresponding index, check just the indexed issues.
      for _, issue_number in ipairs(issue_numbers) do
        check_issue(issue_number)
      end
    else
      -- Otherwise, check all issues (slow).
      for issue_number, _ in ipairs(issue_table) do
        check_issue(issue_number)
      end
    end

    -- If many issues were already scheduled for a later removal, remove them now.
    if issue_table._num_ignored >= self.max_ignored_issue_ratio * #issue_table then
      self:commit_ignores({issue_table})
    end
  end

  -- Prevent the issue from being added later.
  --
  -- TODO: Instead of using `check()` functions, use efficient data structures such as prefix trees for identifier (prefixes) and
  -- segment trees for ranges, so that we can determine whether a future issue should be ignored in time O(log n) instead of
  -- O(n). The segment trees should be implemented in the file `explcheck-ranges.lua`.
  table.insert(self.ignored_issues, ignored_issue)
end

-- Check whether two registries only contain issues with the same codes.
function Issues:has_same_codes_as(other)
  if not self.closed or not other.closed then
    error('Cannot compared issues between unclosed issue registries')
  end

  -- Collect codes of all issues.
  local self_codes, other_codes = {}, {}
  for _, table_name in ipairs({'warnings', 'errors'}) do
    for _, tables in ipairs({{self[table_name], self_codes}, {other[table_name], other_codes}}) do
      local issue_table, codes = table.unpack(tables)
      for _, issue in ipairs(issue_table) do
        local code = issue[1]
        codes[code] = true
      end
    end
  end
  -- Check whether this registry has any extra codes.
  for code, _ in pairs(self_codes) do
    if other_codes[code] == nil then
      return false
    end
  end
  -- Check whether the other registry has any extra codes.
  for code, _ in pairs(other_codes) do
    if self_codes[code] == nil then
      return false
    end
  end
  return true
end

-- Remove all issues that were previously scheduled to be ignored.
function Issues:commit_ignores(issue_tables)
  for _, issue_table in ipairs(issue_tables or {self.warnings, self.errors}) do
    local removed_identifiers = {}
    if issue_table._num_ignored == 0 then
      goto next_issue_table
    end

    -- Remove the issues.
    local filtered_issues = {}
    for issue_number, issue in ipairs(issue_table) do
      if issue_table._ignored_index[issue_number] then
        local identifier = issue[1]
        removed_identifiers[identifier] = true
      else
        table.insert(filtered_issues, issue)
      end
    end
    for issue_number, issue in ipairs(filtered_issues) do
      issue_table[issue_number] = issue
    end
    for issue_number = #filtered_issues + 1, #issue_table, 1 do
      issue_table[issue_number] = nil
    end

    -- Clear the schedule.
    issue_table._ignored_index = {}
    issue_table._num_ignored = 0

    -- Rebuild all identifier indexes for removed issue identifiers.
    for identifier, _ in pairs(removed_identifiers) do
      issue_table._identifier_index[identifier] = {}
    end
    for issue_number, issue in ipairs(filtered_issues) do
      local identifier = issue[1]
      if removed_identifiers[identifier] then
        table.insert(issue_table._identifier_index[identifier], issue_number)
      end
    end
    ::next_issue_table::
  end
end

-- Close the issue registry, preventing future modifications and report all needlessly ignored issues.
function Issues:close()
  if self.closed then
    error('Cannot close an already closed issue registry')
  end

  -- Report all needlessly ignored issues.
  local format_identifier = require('explcheck-format').format_issue_identifier
  for _, ignored_issue in ipairs(self.ignored_issues) do
    if not ignored_issue.seen and ignored_issue.source_range ~= nil then
      local formatted_identifier_prefix
      if ignored_issue.identifier_prefix ~= nil then
        formatted_identifier_prefix = format_identifier(ignored_issue.identifier_prefix)
      end
      self:add('s105', 'needlessly ignored issue', ignored_issue.source_range, formatted_identifier_prefix)
    end
  end

  -- Remove all issues that were previously scheduled to be ignored.
  self:commit_ignores()

  -- Clear indexes, since we wouldn't need them anymore.
  for _, issue_table in ipairs({self.warnings, self.errors}) do
    issue_table._identifier_index = nil
    issue_table._ignored_index = nil
    issue_table._num_ignored = nil
  end
  self.seen_issues = nil
  self.ignored_issues = nil

  -- Close the registry.
  self.closed = true
end

-- Sort the warnings/errors using location as the primary key.
local function sort_issues(warnings_and_errors)
  local sorted_warnings_and_errors = {}
  for _, issue in ipairs(warnings_and_errors) do
    table.insert(sorted_warnings_and_errors, issue)
  end
  table.sort(sorted_warnings_and_errors, function(a, b)
    local a_identifier, b_identifier = a[1], b[1]
    local a_range, b_range = (a[3] and a[3]:start()) or 0, (b[3] and b[3]:start()) or 0
    local a_context, b_context = a[4] or '', b[4] or ''
    return (
      a_range < b_range
      or (a_range == b_range and a_identifier < b_identifier)
      or (a_range == b_range and a_identifier == b_identifier and a_context < b_context)
    )
  end)
  return sorted_warnings_and_errors
end

return {
  new_issues = function(...)
    return Issues:new(...)
  end,
  sort_issues = sort_issues,
}
