-- A registry of warnings and errors identified by different processing steps.

local get_option = require("explcheck-config").get_option

local Issues = {}

-- Normalize an issue identifier.
local function normalize_identifier(identifier)
  return identifier:lower()
end

function Issues.new(cls, pathname, options)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.closed = false
  --- Issue tables
  self.errors = {}
  self.warnings = {}
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
  for _, ignored_issue in ipairs(self.ignored_issues) do
    if ignored_issue.check(issue) then
      ignored_issue.seen = true
      return
    end
  end

  -- Add the issue to the table of issues.
  local issue_table = self:_get_issue_table(identifier)
  table.insert(issue_table, issue)
end

-- Prevent issues from being present in the table of issues.
function Issues:ignore(ignored_issue)
  if self.closed then
    error('Cannot ignore issues in a closed issue registry')
  end

  if ignored_issue.identifier_prefix ~= nil then
    ignored_issue.identifier_prefix = normalize_identifier(ignored_issue.identifier_prefix)
  end

  -- Determine which issues should be ignored.
  local function match_issue_range(issue_range)
    return (
      issue_range:start() >= ignored_issue.range:start() and issue_range:start() <= ignored_issue.range:stop()  -- issue starts within range
      or issue_range:start() <= ignored_issue.range:start() and issue_range:stop() >= ignored_issue.range:stop() -- issue in middle of range
      or issue_range:stop() >= ignored_issue.range:start() and issue_range:stop() <= ignored_issue.range:stop()  -- issue ends within range
    )
  end
  local function match_issue_identifier(identifier)
    -- Match the prefix of an issue, allowing us to ignore whole sets of issues with prefixes like "s" or "w4".
    return identifier:sub(1, #ignored_issue.identifier_prefix) == ignored_issue.identifier_prefix
  end

  local issue_tables
  if ignored_issue.identifier_prefix == nil and ignored_issue.range == nil then
    -- Prevent any issues.
    issue_tables = {self.warnings, self.errors}
    ignored_issue.check = function() return true end
  elseif ignored_issue.identifier_prefix == nil then
    -- Prevent any issues within the given range.
    issue_tables = {self.warnings, self.errors}
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
    issue_tables = {self:_get_issue_table(ignored_issue.identifier_prefix)}
    ignored_issue.check = function(issue)
      local issue_identifier = issue[1]
      return match_issue_identifier(issue_identifier)
    end
  else
    -- Prevent any issues with the given identifier that are also either within the given range or file-wide.
    assert(ignored_issue.range ~= nil and ignored_issue.identifier_prefix ~= nil)
    issue_tables = {self:_get_issue_table(ignored_issue.identifier_prefix)}
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

  -- Remove the issue if it has already been added.
  for _, issue_table in ipairs(issue_tables) do
    local filtered_issues = {}
    for _, issue in ipairs(issue_table) do
      if ignored_issue.check(issue) then
        ignored_issue.seen = true
      else
        table.insert(filtered_issues, issue)
      end
    end
    for issue_index, issue in ipairs(filtered_issues) do
      issue_table[issue_index] = issue
    end
    for issue_index = #filtered_issues + 1, #issue_table, 1 do
      issue_table[issue_index] = nil
    end
  end

  -- Prevent the issue from being added later.
  table.insert(self.ignored_issues, ignored_issue)
end

-- Check whether two registries only contain issues with the same codes.
function Issues:has_same_codes_as(other)
  if not self.closed or not other.close then
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
