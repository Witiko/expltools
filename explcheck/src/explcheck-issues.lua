-- A registry of warnings and errors identified by different processing steps.

local Issues = {}

function Issues.new(cls)
  local new_object = {}
  setmetatable(new_object, cls)
  cls.__index = cls
  new_object.errors = {}
  new_object.warnings = {}
  new_object.ignored_issues = {}
  return new_object
end

-- Convert an issue identifier to either a table of warnings or a table of errors.
function Issues:_get_issue_table(identifier)
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
function Issues:add(identifier, message, range_start, range_end)
  if self.ignored_issues[identifier] then
    return
  end
  local issue_table = self:_get_issue_table(identifier)
  local range
  if range_start == nil then
    range = nil
  else
    range = {range_start, range_end}
  end
  table.insert(issue_table, {identifier, message, range})
end

-- Prevent an issue from being present in the table of issues.
function Issues:ignore(identifier)
  -- Remove the issue if it has already been added.
  local issue_table = self:_get_issue_table(identifier)
  local updated_issues = {}
  for _, issue in ipairs(issue_table) do
    if issue[1] ~= identifier then
      table.insert(updated_issues, issue)
    end
  end
  for issue_index, issue in ipairs(updated_issues) do
    issue_table[issue_index] = issue
  end
  for issue_index = #updated_issues + 1, #issue_table, 1 do
    issue_table[issue_index] = nil
  end
  -- Prevent the issue from being added later.
  self.ignored_issues[identifier] = true
end

-- Sort the warnings/errors using location as the primary key.
function Issues.sort(warnings_and_errors)
  local sorted_warnings_and_errors = {}
  for _, issue in ipairs(warnings_and_errors) do
    local code = issue[1]
    local message = issue[2]
    local range = issue[3]
    table.insert(sorted_warnings_and_errors, {code, message, range})
  end
  table.sort(sorted_warnings_and_errors, function(a, b)
    local a_code, b_code = a[1], b[1]
    local a_range, b_range = (a[3] and a[3][1]) or 0, (b[3] and b[3][1]) or 0
    return a_range < b_range or (a_range == b_range and a_code < b_code)
  end)
  return sorted_warnings_and_errors
end

return function()
  return Issues:new()
end
