-- A registry of warnings and errors identified by different processing steps.

local get_option = require("explcheck-config").get_option
local new_prefix_tree = require("explcheck-trie").new_prefix_tree
local new_range_tree = require("explcheck-ranges").new_range_tree

local Issues = {}

-- Normalize an issue identifier or its prefix.
local function normalize_identifier(identifier)
  return identifier:lower()
end

-- TODO: Aim at least for the measurements with Dell G5 15 on the file `expl3-code.tex` from before `PrefixTree`
-- and `RangeTree` were added after commit 6ab6b9d5:
--
--     $ time explcheck expl3-code.tex | grep XXX
--     XXXX    preprocessing           1       2.825616        0.15764000000001        0.016291               41514
--     XXXX    lexical-analysis        1       2.403953        0.016523000000024       0.0                     2848
--     XXXX    lexical-analysis        2       0.618749        0.32456599999998        0.024647000000011       2197
--     XXXX    syntactic-analysis      1       0.153292        0.00032400000000177     0.0                       46
--     XXXX    semantic-analysis       1       0.690973        0.06382399999999        0.0097439999999995       829
--     XXXX    semantic-analysis       2       1.179811        0.77534300000002        0.0                      270
--
-- TODO: After commit 259ae1d, the measurements with `max_range_tree_depth` set to 1 are the fastest when tested on
-- a range from 1 to 7, which gives a strong indication that `RangeTree` can go, since it's not adding anything to
-- the table compared to a linear scan. The contribution of `PrefixTree` seems unclear.
--
--     $ time explcheck expl3-code.tex | grep XXX
--     XXXX    preprocessing           1       3.331975        0.8277059999999         0.033757               41514
--     XXXX    lexical-analysis        1       2.230335        0.067801999999989       0.0                     2848
--     XXXX    lexical-analysis        2       0.167146        0.10382600000001        0.07158099999999        2197
--     XXXX    syntactic-analysis      1       0.173643        0.00065300000000157     0.0                       46
--     XXXX    semantic-analysis       1       0.480903        0.0091530000000111      0.012088999999999        829
--     XXXX    semantic-analysis       2       0.34739         0.0043879999999925      0.0                      270
--     XXX
--     XXX     add_duration (trie)     0.10088700000009
--     XXX     get_prefixed_by_duration (trie) 0.040856000000013
--     XXX     get_prefixes_of_duration (trie) 0.14401700000006
--     XXX     add_duration (ranges)   0.26725799999979
--     XXX     add_loops (ranges)      95686   ~358029 loops/s
--     XXX     get_intersecting_ranges_duration (ranges)       0.088016000000041
--     XXX
--     XXX     total (trie)    0.28576000000017
--     XXX     total (ranges)  0.35527399999983
--
--     real    0m8.430s
--     user    0m7.289s
--     sys     0m0.414s
--
function Issues.new(cls, pathname, content_length, options)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.closed = false
  --- Issue tables
  self.content_length = content_length
  self.max_range_tree_depth = get_option("max_range_tree_depth", options, pathname)
  for _, issue_table_name in ipairs({"errors", "warnings"}) do
    self[issue_table_name] = {
      _identifier_index = new_prefix_tree(),
      _range_index = self:_new_range_tree(),
      _identifier_range_indexes = {},
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
  self.ignored_issues = {
    _identifier_prefix_index = new_prefix_tree(),
    _range_index = self:_new_range_tree(),
    _identifier_prefix_range_indexes = {},
  }
  self.max_ignored_issue_ratio = get_option("max_ignored_issue_ratio", options, pathname)
  for _, issue_identifier in ipairs(get_option("ignored_issues", options, pathname)) do
    self:ignore({identifier_prefix = issue_identifier})
  end
  return self
end

-- Produce a new range tree for storing ranged issues.
function Issues:_new_range_tree()
  return new_range_tree(1, self.content_length, self.max_range_tree_depth)
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

local total_issues = 0
local total_issue_time = 0

-- Add an issue to the table of issues.
function Issues:add(identifier, message, range, context)
  local start_time = os.clock()
  total_issues = total_issues + 1

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
  assert(range_start ~= nil and range_end ~= nil)
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

  -- Determine if the issue should ignored.
  if range ~= nil then
    -- Look for ignored issues by their ranges and their identifiers or identifier prefixes.
    for identifier_prefix, _ in self.ignored_issues._identifier_prefix_index:get_prefixes_of(identifier) do
      local identifier_prefix_range_index = self.ignored_issues._identifier_prefix_range_indexes[identifier_prefix]
      if identifier == "e209" then
      end
      if identifier_prefix_range_index ~= nil then
        for _, ignored_issue in identifier_prefix_range_index:get_intersecting_ranges(range) do
          assert(ignored_issue.identifier_prefix == identifier_prefix)
          ignored_issue.seen = true
          goto record_time
        end
      end
    end
    -- Look for ignored issues by their ranges.
    for _, ignored_issue in self.ignored_issues._range_index:get_intersecting_ranges(range) do
      assert(ignored_issue.identifier_prefix == nil)
      ignored_issue.seen = true
      goto record_time
    end
  end
  -- Look for ignored issues by their identifiers or identifier prefixes.
  for _, ignored_issue in self.ignored_issues._identifier_prefix_index:get_prefixes_of(identifier) do
    ignored_issue.seen = true
    goto record_time
  end

  do
    -- Construct the issue.
    local issue = {identifier, message, range, context}

    -- Add the issue to the table of issues.
    local issue_table = self:_get_issue_table(identifier)
    table.insert(issue_table, issue)
    local issue_number = #issue_table
    issue_table._identifier_index:add(identifier, issue_number)
    if range ~= nil then
      if issue_table._identifier_range_indexes[identifier] == nil then
         issue_table._identifier_range_indexes[identifier] = self:_new_range_tree()
      end
      issue_table._identifier_range_indexes[identifier]:add(range, issue_number)
      issue_table._range_index:add(range, issue_number)
    end
  end
  ::record_time::
  local end_time = os.clock()
  total_issue_time = total_issue_time + end_time - start_time
end

local total_ignore_time = 0

-- Prevent issues from being present in the table of issues.
function Issues:ignore(ignored_issue)
  local start_time = os.clock()

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
  assert(ignored_issue.identifier_prefix ~= nil or ignored_issue.range ~= nil)

  -- Normalize the ignored identifier (prefix).
  if ignored_issue.identifier_prefix ~= nil then
    ignored_issue.identifier_prefix = normalize_identifier(ignored_issue.identifier_prefix)
  end

  -- Ignore future issues.
  table.insert(self.ignored_issues, ignored_issue)
  if ignored_issue.range ~= nil then
    if ignored_issue.identifier_prefix ~= nil then
      -- Record ignored issues by their ranges and their identifiers or identifier prefixes.
      if self.ignored_issues._identifier_prefix_range_indexes[ignored_issue.identifier_prefix] == nil then
        self.ignored_issues._identifier_prefix_range_indexes[ignored_issue.identifier_prefix] = self:_new_range_tree()
      end
      self.ignored_issues._identifier_prefix_range_indexes[ignored_issue.identifier_prefix]:add(ignored_issue.range, ignored_issue)
    else
      -- Record ignored issues by their ranges.
      self.ignored_issues._range_index:add(ignored_issue.range, ignored_issue)
    end
  end
  if ignored_issue.identifier_prefix ~= nil then
    -- Record ignored issues by their identifiers or identifier prefixes.
    self.ignored_issues._identifier_prefix_index:add(ignored_issue.identifier_prefix, ignored_issue)
  end

  -- Determine which current issues should be ignored.
  local issue_tables, issue_number_lists
  if ignored_issue.identifier_prefix == nil then
    assert(ignored_issue.range ~= nil)
    -- Prevent any issues within the given range.
    issue_tables = {self.warnings, self.errors}
    issue_number_lists = {{}, {}}
    for issue_table_number, issue_table in ipairs(issue_tables) do
      local issue_number_list = issue_number_lists[issue_table_number]
      for _, issue_number in issue_table._range_index:get_intersecting_ranges(ignored_issue.range) do
        table.insert(issue_number_list, issue_number)
      end
    end
  else
    assert(ignored_issue.identifier_prefix ~= nil)
    -- Prevent any issues with the given identifier.
    local issue_table = self:_get_issue_table(ignored_issue.identifier_prefix)
    local issue_number_list = {}
    local issue_number_list_from_identifiers, issue_number_index_from_identifiers = {}, {}
    local identifier_list, identifier_index = {}, {}
    for _, issue_number in issue_table._identifier_index:get_prefixed_by(ignored_issue.identifier_prefix) do
      local issue = issue_table[issue_number]
      local identifier, range = issue[1], issue[3]
      assert(identifier ~= nil)
      if identifier_index[identifier] == nil then
        identifier_index[identifier] = true
        table.insert(identifier_list, identifier)
      end
      if range == nil then
        -- Prevent rangeless issues immediately, since these should be ignored regardless of a range match.
        table.insert(issue_number_list, issue_number)
      else
        issue_number_index_from_identifiers[issue_number] = true
      end
      table.insert(issue_number_list_from_identifiers, issue_number)
    end
    if ignored_issue.range ~= nil then
      -- If a range was also given, intersect the results of the identifier query with the results of the range query.
      for _, identifier in ipairs(identifier_list) do
        local identifier_range_index = issue_table._identifier_range_indexes[identifier]
        if identifier_range_index ~= nil then
          for _, issue_number in identifier_range_index:get_intersecting_ranges(ignored_issue.range) do
            if issue_number_index_from_identifiers[issue_number] ~= nil then
              table.insert(issue_number_list, issue_number)
            end
          end
        end
      end
    else
      issue_number_list = issue_number_list_from_identifiers
    end
    issue_tables = {issue_table}
    issue_number_lists = {issue_number_list}
  end
  assert(issue_tables ~= nil)
  assert(issue_number_lists ~= nil)

  -- Remove current issues that should be ignored.
  for issue_table_number, issue_table in ipairs(issue_tables) do
    local issue_numbers = issue_number_lists[issue_table_number]
    assert(issue_numbers ~= nil)
    for _, issue_number in ipairs(issue_numbers) do
      ignored_issue.seen = true
      -- Schedule an issue for later removal.
      if issue_table._ignored_index[issue_number] == nil then
        issue_table._ignored_index[issue_number] = true
        issue_table._num_ignored = issue_table._num_ignored + 1
      end
    end

    -- If many issues were already scheduled for a later removal, remove them now.
    if issue_table._num_ignored >= self.max_ignored_issue_ratio * #issue_table then
      self:commit_ignores({issue_tables = {issue_table}})
    end
  end

  local end_time = os.clock()
  total_ignore_time = total_ignore_time + end_time - start_time
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
function Issues:commit_ignores(how)
  local issue_tables = how and how.issue_tables or {self.warnings, self.errors}
  for _, issue_table in ipairs(issue_tables) do
    if issue_table._num_ignored == 0 then
      goto next_issue_table
    end

    -- Remove the issues.
    local filtered_issues = {}
    for issue_number, issue in ipairs(issue_table) do
      if issue_table._ignored_index[issue_number] == nil then
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

    local skip_index_rebuild = how and how.skip_index_rebuild
    if not skip_index_rebuild then
      -- Rebuild all issue indexes.
      issue_table._identifier_index:clear()
      issue_table._range_index:clear()
      issue_table._identifier_range_indexes = {}
      for issue_number, issue in ipairs(issue_table) do
        local identifier, range = issue[1], issue[3]
        issue_table._identifier_index:add(identifier, issue_number)
        if range ~= nil then
          if issue_table._identifier_range_indexes[identifier] == nil then
             issue_table._identifier_range_indexes[identifier] = self:_new_range_tree()
          end
          issue_table._identifier_range_indexes[identifier]:add(range, issue_number)
          issue_table._range_index:add(range, issue_number)
        end
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
  self:commit_ignores({skip_index_rebuild = true})

  -- Clear indexes, since we wouldn't need them anymore.
  for _, issue_table in ipairs({self.warnings, self.errors}) do
    issue_table._identifier_index = nil
    issue_table._range_index = nil
    issue_table._identifier_range_indexes = nil
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
  total_issues = function()
    return total_issues
  end,
  total_issue_time = function()
    return total_issue_time
  end,
  total_ignore_time = function()
    return total_ignore_time
  end,
}
