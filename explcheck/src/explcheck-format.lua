-- Formatting for the command-line interface of the static analyzer explcheck.

-- Transform a singular into plural if the count is zero or greater than two.
local function pluralize(singular, count)
  if count == 1 then
    return singular
  else
    return singular .. "s"
  end
end

-- Shorten a pathname, so that it does not exceed maximum length.
local function format_pathname(pathname, max_length)
  -- First, replace path segments with `/.../`, keeping other segments.
  local first_iteration = true
  while #pathname > max_length do
    local pattern
    if first_iteration then
      pattern = "([^/]*)/[^/]*/(.*)"
    else
      pattern = "([^/]*)/%.%.%./[^/]*/(.*)"
    end
    local prefix_start, _, prefix, suffix = pathname:find(pattern)
    if prefix_start == nil or prefix_start > 1 then
      break
    end
    pathname = prefix .. "/.../" .. suffix
    first_iteration = false
  end
  -- If this isn't enough, remove the initial path segment and prefix the filename with `...`.
  if #pathname > max_length then
    local pattern
    if first_iteration then
      pattern = "([^/]*/?)(.*)"
    else
      pattern = "([^/]*/%.%.%./)(.*)"
    end
    local prefix_start, _, _, suffix = pathname:find(pattern)
    if prefix_start == 1 then
      pathname = ".../" .. suffix
      if #pathname > max_length then
        pathname = "..." .. suffix:sub(-(max_length - #("...")))
      end
    end
  end
  return pathname
end

-- Colorize a string using ASCII color codes.
local function colorize(text, ...)
  local buffer = {}
  for _, color_code in ipairs({...}) do
    table.insert(buffer, "\27[")
    table.insert(buffer, tostring(color_code))
    table.insert(buffer, "m")
  end
  table.insert(buffer, text)
  table.insert(buffer, "\27[0m")
  return table.concat(buffer, "")
end

-- Remove ASCII color codes from a string.
local function decolorize(text)
  return text:gsub("\27%[[0-9]+m", "")
end

-- Convert a byte number in a file to a line and column number in a file.
local function convert_byte_to_line_and_column(line_starting_byte_numbers, byte_number)
  local line_number = 0
  for _, line_starting_byte_number in ipairs(line_starting_byte_numbers) do
    if line_starting_byte_number > byte_number then
      break
    end
    line_number = line_number + 1
  end
  assert(line_number > 0)
  local line_starting_byte_number = line_starting_byte_numbers[line_number]
  assert(line_starting_byte_number <= byte_number)
  local column_number = byte_number - line_starting_byte_number + 1
  return line_number, column_number
end

-- Print the results of analyzing a file.
local function print_results(pathname, issues, line_starting_byte_numbers, is_last_file)
  -- Display an overview.
  local all_issues = {}
  local status
  if(#issues.errors > 0) then
    status = (
      colorize(
        (
          tostring(#issues.errors)
          .. " "
          .. pluralize("error", #issues.errors)
        ), 1, 31
      )
    )
    table.insert(all_issues, issues.errors)
    if(#issues.warnings > 0) then
      status = (
        status
        .. ", "
        .. colorize(
          (
            tostring(#issues.warnings)
            .. " "
            .. pluralize("warning", #issues.warnings)
          ), 1, 33
        )
      )
      table.insert(all_issues, issues.warnings)
    end
  elseif(#issues.warnings > 0) then
    status = colorize(
      (
        tostring(#issues.warnings)
        .. " "
        .. pluralize("warning", #issues.warnings)
      ), 1, 33
    )
    table.insert(all_issues, issues.warnings)
  else
    status = colorize("OK", 1, 32)
  end

  local max_overview_length = 72
  local prefix = "Checking "
  local formatted_pathname = format_pathname(
    pathname,
    math.max(
      (
        max_overview_length
        - #prefix
        - #(" ")
        - #decolorize(status)
      ), 1
    )
  )
  local overview = (
    prefix
    .. formatted_pathname
    .. (" "):rep(
      math.max(
        (
          max_overview_length
          - #prefix
          - #decolorize(status)
          - #formatted_pathname
        ), 1
      )
    )
    .. status
  )
  io.write("\n" .. overview)

  -- Display the errors, followed by warnings.
  if #all_issues > 0 then
    for _, warnings_or_errors in ipairs(all_issues) do
      print()
      -- Before display, copy and sort the warnings/errors using location as the primary key.
      local sorted_warnings_or_errors = {}
      for _, issue in ipairs(warnings_or_errors) do
        local code = issue[1]
        local message = issue[2]
        local range = issue[3]
        table.insert(sorted_warnings_or_errors, {code, message, range})
      end
      table.sort(sorted_warnings_or_errors, function(a, b)
        local a_code, b_code = a[1], b[1]
        local a_range, b_range = (a[3] and a[3][1]) or 0, (b[3] and b[3][1]) or 0
        return a_range < b_range or (a_range == b_range and a_code < b_code)
      end)
      -- Display the warnings/errors.
      for _, issue in ipairs(sorted_warnings_or_errors) do
        local code = issue[1]
        local message = issue[2]
        local range = issue[3]
        local position = ":"
        if range ~= nil then
          local line_number, column_number = convert_byte_to_line_and_column(line_starting_byte_numbers, range[1])
          position = position .. tostring(line_number) .. ":" .. tostring(column_number) .. ":"
        end
        local max_line_length = 88
        local reserved_position_length = 10
        local reserved_suffix_length = 30
        local label_indent = (" "):rep(4)
        local suffix = code:upper() .. " " .. message
        formatted_pathname = format_pathname(
          pathname,
          math.max(
            (
              max_line_length
              - #label_indent
              - reserved_position_length
              - #(" ")
              - math.max(#suffix, reserved_suffix_length)
            ), 1
          )
        )
        local line = (
          label_indent
          .. formatted_pathname
          .. position
          .. (" "):rep(
            math.max(
              (
                max_line_length
                - #label_indent
                - #formatted_pathname
                - #decolorize(position)
                - math.max(#suffix, reserved_suffix_length)
              ), 1
            )
          )
          .. suffix
          .. (" "):rep(math.max(reserved_suffix_length - #suffix, 0))
        )
        io.write("\n" .. line)
      end
    end
    if(not is_last_file) then
      print()
    end
  end
end

-- Print the summary results of analyzing multiple files.
local function print_summary(num_pathnames, num_warnings, num_errors)
  io.write("\n\nTotal: ")

  local errors_message = tostring(num_errors) .. " " .. pluralize("error", num_errors)
  errors_message = colorize(errors_message, 1, (num_errors > 0 and 31) or 32)
  io.write(errors_message .. ", ")

  local warnings_message = tostring(num_warnings) .. " " .. pluralize("warning", num_warnings)
  warnings_message = colorize(warnings_message, 1, (num_warnings > 0 and 33) or 32)
  io.write(warnings_message .. " in ")

  print(tostring(num_pathnames) .. " " .. pluralize("file", num_pathnames))
end

return {print_results, print_summary}