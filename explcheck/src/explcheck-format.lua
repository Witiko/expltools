-- Formatting for the command-line interface of the static analyzer explcheck.

local get_option = require("explcheck-config")
local utils = require("explcheck-utils")

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
      pattern = "([^\\/]*)[\\/][^\\/]*[\\/](.*)"
    else
      pattern = "([^\\/]*)/%.%.%.[\\/][^\\/]*[\\/](.*)"
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
      pattern = "([^\\/]*[\\/])(.*)"
    else
      pattern = "([^\\/]*[\\/]%.%.%.[\\/])(.*)"
    end
    local prefix_start, _, _, suffix = pathname:find(pattern)
    if prefix_start == nil or prefix_start > 1 then
      pathname = "..." .. pathname:sub(-(max_length - #("...")))
    else
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

-- Format a ratio as a percentage.
local function format_ratio(num_expl_bytes, num_total_bytes)
  if num_expl_bytes == 0 then
    return "no"
  elseif num_expl_bytes < num_total_bytes then
    local expl_coverage = num_expl_bytes / num_total_bytes
    return string.format("%2.0f%%", math.max(1, math.min(99, 100 * expl_coverage)))
  else
    return "all"
  end
end

-- Format a number in a human-readable way, using words for small numbers and metric prefixes for large numbers.
local function format_human_readable(number)
  if number == 0 then
    return "no"
  elseif number == 1 then
    return "one"
  elseif number == 2 then
    return "two"
  elseif number == 4 then
    return "four"
  elseif number == 5 then
    return "five"
  elseif number == 6 then
    return "six"
  elseif number == 9 then
    return "nine"
  elseif number == 10 then
    return "ten"
  elseif number < 10^4 then
    return tostring(number)
  elseif number < 10^6 then
    return string.format("~%.0fk", number / 10^3)
  elseif number < 10^9 then
    return string.format("~%.0fM", number / 10^6)
  elseif number < 10^12 then
    return string.format("~%.0fG", number / 10^9)
  else
    return string.format("~%.0fT", number / 10^12)
  end
end

-- Print the summary results of analyzing multiple files.
local function print_summary(pathname, options, print_state)
  local num_pathnames = print_state.num_pathnames or 0
  local num_warnings = print_state.num_warnings or 0
  local num_errors = print_state.num_errors or 0

  io.write("\n\nTotal: ")

  local errors_message = tostring(num_errors) .. " " .. pluralize("error", num_errors)
  errors_message = colorize(errors_message, 1, (num_errors > 0 and 31) or 32)
  io.write(errors_message .. ", ")

  local warnings_message = tostring(num_warnings) .. " " .. pluralize("warning", num_warnings)
  warnings_message = colorize(warnings_message, 1, (num_warnings > 0 and 33) or 32)
  io.write(warnings_message .. " in ")

  io.write(tostring(num_pathnames) .. " " .. pluralize("file", num_pathnames))

  if get_option('verbose', options, pathname) then
    local notes = {}

    if print_state.filetypes ~= nil then
      local max_filetype, max_num_total_bytes = nil, -1
      local filetypes = {}
      for filetype, _ in pairs(print_state.filetypes) do
        table.insert(filetypes, filetype)
      end
      assert(#filetypes > 0)
      table.sort(filetypes)
      for _, filetype in ipairs(filetypes) do
        local num_total_bytes = print_state.filetypes[filetype]
        if num_total_bytes > max_num_total_bytes then
          max_filetype = filetype
        elseif num_total_bytes == max_num_total_bytes then
          max_filetype = string.format("%s and %s", max_filetype, filetype)
        end
        max_num_total_bytes = num_total_bytes
      end
      assert(max_filetype ~= nil)
      if #filetypes > 1 then
        max_filetype = string.format("mostly %s", max_filetype)
      end
      table.insert(notes, max_filetype)
    end

    if print_state.num_total_bytes ~= nil then
      local num_total_bytes = print_state.num_total_bytes
      local num_expl_bytes = print_state.num_expl_bytes or 0
      table.insert(notes, string.format("%s expl3", format_ratio(num_expl_bytes, num_total_bytes)))
    end

    if print_state.num_expl_tokens ~= nil then
      local num_expl_tokens = print_state.num_expl_tokens
      table.insert(notes, string.format("%s %s", format_human_readable(num_expl_tokens), pluralize("token", num_expl_tokens)))
    end

    if print_state.num_expl_calls ~= nil then
      local num_expl_calls = print_state.num_expl_calls
      table.insert(notes, string.format("%s %s", format_human_readable(num_expl_calls), pluralize("call", num_expl_calls)))
    end

    if #notes > 0 then
      io.write(string.format(" (%s)", table.concat(notes, ", ")))
    end
  end

  print()
end

-- Print the results of analyzing a file.
local function print_results(pathname, content, issues, results, options, is_last_file, print_state)
  print_state.num_pathnames = (print_state.num_pathnames or 0) + 1
  print_state.num_warnings = (print_state.num_warnings or 0) + #issues.warnings
  print_state.num_errors = (print_state.num_errors or 0) + #issues.errors

  -- Display an overview.
  local all_issues = {}
  local status
  local porcelain = get_option('porcelain', options, pathname)
  if(#issues.errors > 0) then
    if not porcelain then
      status = (
        colorize(
          (
            tostring(#issues.errors)
            .. " "
            .. pluralize("error", #issues.errors)
          ), 1, 31
        )
      )
    end
    table.insert(all_issues, issues.errors)
    if(#issues.warnings > 0) then
      if not porcelain then
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
      end
      table.insert(all_issues, issues.warnings)
    end
  else
    if(#issues.warnings > 0) then
      if not porcelain then
        status = colorize(
          (
            tostring(#issues.warnings)
            .. " "
            .. pluralize("warning", #issues.warnings)
          ), 1, 33
        )
      end
      table.insert(all_issues, issues.warnings)
    else
      if not porcelain then
        status = colorize("OK", 1, 32)
      end
    end
  end

  if not porcelain then
    local notes = {}

    if get_option('verbose', options, pathname) then
      if results.expl_ranges ~= nil then
        local num_total_bytes = #content
        print_state.num_total_bytes = (print_state.num_total_bytes or 0) + num_total_bytes
        if num_total_bytes > 0 then
          local filetype
          if results.seems_like_latex_style_file then
            filetype = "LaTeX"
          else
            filetype = "other"
          end
          table.insert(notes, filetype)
          print_state.filetypes = print_state.filetypes or {}
          print_state.filetypes[filetype] = (print_state.filetypes[filetype] or 0) + num_total_bytes
          local num_expl_bytes = 0
          for _, expl_range in ipairs(results.expl_ranges) do
            num_expl_bytes = num_expl_bytes + #expl_range
          end
          print_state.num_expl_bytes = (print_state.num_expl_bytes or 0) + num_expl_bytes
          local expl_coverage = string.format("%3s expl3", format_ratio(num_expl_bytes, num_total_bytes))
          table.insert(notes, expl_coverage)
          if num_expl_bytes > 0 then
            local num_expl_tokens = 0
            for _, tokens in ipairs(results.tokens) do
              num_expl_tokens = num_expl_tokens + #tokens
            end
            print_state.num_expl_tokens = (print_state.num_expl_tokens or 0) + num_expl_tokens
            local formatted_num_expl_tokens = format_human_readable(num_expl_tokens)
            formatted_num_expl_tokens = string.format("%4s %s", formatted_num_expl_tokens:sub(-4), pluralize("token", num_expl_tokens))
            table.insert(notes, formatted_num_expl_tokens)
            if num_expl_tokens > 0 then
              local num_expl_calls = 0
              for _, calls in ipairs(results.calls) do
                num_expl_calls = num_expl_calls + #calls
              end
              print_state.num_expl_calls = (print_state.num_expl_calls or 0) + num_expl_calls
              local formatted_num_expl_calls = format_human_readable(num_expl_calls)
              formatted_num_expl_calls = string.format("%4s %s", formatted_num_expl_calls:sub(-4), pluralize("call", num_expl_calls))
              table.insert(notes, formatted_num_expl_calls)
            end
          end
        else
          table.insert(notes, "empty")
        end
      end
    end

    local postfix
    if #notes == 0 then
      postfix = ""
    else
      postfix = string.format(" (%s)", table.concat(notes, ", "))
    end

    local max_overview_length = get_option('terminal_width', options, pathname)
    local prefix = "Checking "
    local reserved_postfix_length = 44
    local formatted_pathname = format_pathname(
      pathname,
      math.max(
        (
          max_overview_length
          - #prefix
          - #(" ")
          - #decolorize(status)
          - math.max(#postfix, reserved_postfix_length)
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
            - math.max(#postfix, reserved_postfix_length)
          ), 1
        )
      )
      .. status
    )
    if #postfix > 0 then
      overview = (
        overview
        .. postfix
      )
    end
    io.write("\n" .. overview)
  end

  -- Display the errors, followed by warnings.
  if #all_issues > 0 then
    for _, warnings_or_errors in ipairs(all_issues) do
      if not porcelain then
        print()
      end
      -- Display the warnings/errors.
      for _, issue in ipairs(issues.sort(warnings_or_errors)) do
        local code = issue[1]
        local message = issue[2]
        local range = issue[3]
        local start_line_number, start_column_number = 1, 1
        local end_line_number, end_column_number = 1, 1
        if range ~= nil then
          start_line_number, start_column_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, range:start())
          end_line_number, end_column_number = utils.convert_byte_to_line_and_column(results.line_starting_byte_numbers, range:stop())
          end_column_number = end_column_number
        end
        local position = ":" .. tostring(start_line_number) .. ":" .. tostring(start_column_number) .. ":"
        local terminal_width = get_option('terminal_width', options, pathname)
        local max_line_length = math.max(math.min(88, terminal_width), terminal_width - 16)
        local reserved_position_length = 10
        local reserved_suffix_length = 30
        local label_indent = (" "):rep(4)
        local suffix = code:upper() .. " " .. message
        if not porcelain then
          local formatted_pathname = format_pathname(
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
        else
          local line = get_option('error_format', options, pathname)

          local function replace_item(item)
            if item == '%%' then
              return '%'
            elseif item == '%c' then
              return tostring(start_column_number)
            elseif item == '%e' then
              return tostring(end_line_number)
            elseif item == '%f' then
              return pathname
            elseif item == '%k' then
              return tostring(end_column_number)
            elseif item == '%l' then
              return tostring(start_line_number)
            elseif item == '%m' then
              return message
            elseif item == '%n' then
              return code:sub(2)
            elseif item == '%t' then
              return code:sub(1, 1):lower()
            end
          end

          line = line:gsub("%%[%%cefklmnt]", replace_item)
          print(line)
        end
      end
    end
    if not porcelain and not is_last_file then
      print()
    end
  end
  if not porcelain and is_last_file then
    print_summary(pathname, options, print_state)
  end
end

return {
  pluralize = pluralize,
  print_results = print_results,
}
