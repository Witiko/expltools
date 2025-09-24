-- Formatting for the command-line interface of the static analyzer explcheck.

local get_option = require("explcheck-config").get_option
local utils = require("explcheck-utils")

local color_codes = {
  BOLD = 1,
  RED = 31,
  GREEN = 32,
  YELLOW = 33,
}

local BOLD = color_codes.BOLD
local RED = color_codes.RED
local GREEN = color_codes.GREEN
local YELLOW = color_codes.YELLOW

-- Get an iterator over the key-values in a table order by desceding values.
local function pairs_sorted_by_descending_values(obj)
  local items = {}
  for key, value in pairs(obj) do
    table.insert(items, {key, value})
  end
  table.sort(items, function(first_item, second_item)
    if first_item[2] > second_item[2] then
      return true
    elseif first_item[2] == second_item[2] and first_item[1] > second_item[1] then
      return true
    else
      return false
    end
  end)
  local i = 0
  return function()
    i = i + 1
    if i <= #items then
      return table.unpack(items[i])
    else
      return nil
    end
  end
end

-- Transform a singular into plural if the count is zero, greater than two, or unspecified.
local function pluralize(singular, count)
  if count == 1 then
    return singular
  else
    local of_index = singular:find(" of ")
    local plural
    if of_index == nil then
      plural = singular .. "s"
    else
      plural = singular:sub(1, of_index - 1) .. "s" .. singular:sub(of_index)
    end
    return plural
  end
end

-- Upper-case the initial letter of a word.
local function titlecase(word)
  assert(#word > 0)
  return string.format("%s%s", word:sub(1, 1):upper(), word:sub(2))
end

-- Format an issue identifier for display.
local function format_issue_identifier(code)
  return code:upper()
end

-- Convert a number to a string with thousand separators.
local function separate_thousands(number)
  local initial_digit, following_digits = string.match(tostring(number), '^(%d)(%d*)$')
  return initial_digit .. following_digits:reverse():gsub('(%d%d%d)', '%1,'):reverse()
end

-- Transform short numbers to words and make long numbers more readable using thousand separators.
local function humanize(number)
  if number == 1 then
    return "one"
  elseif number == 2 then
    return "two"
  elseif number == 3 then
    return "three"
  elseif number == 4 then
    return "four"
  elseif number == 5 then
    return "five"
  elseif number == 6 then
    return "six"
  elseif number == 7 then
    return "seven"
  elseif number == 8 then
    return "eight"
  elseif number == 9 then
    return "nine"
  elseif number == 10 then
    return "ten"
  else
    return separate_thousands(number)
  end
end

-- Strip leading and trailing whitespace in a text string.
local function strip(text)
  return text:gsub("^[%s\n]*", ""):gsub("[%s\n]*$", "")
end

-- Strip leading and trailing whitespace, collapse internal whitespace and optionally shorten issue context.
local function format_context(context, max_length)
  local ellipsis = "..."
  -- Strip any leading or trailing whitespace.
  context = strip(context)
  -- Collapse internal whitespace.
  context = context:gsub("%s+", " ")
  -- Strip all text that exceeds the max length.
  if #context + #ellipsis > max_length then
    return string.format("%s%s", context:sub(1, max_length - #ellipsis), ellipsis)
  end
  return context
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

-- Format a number as a percentage.
local function format_percentage(percentage)
  local formatted_percentage = string.format("%.0f%%", percentage)
  if percentage > 0 and formatted_percentage == "0%" then
    return "<1%"
  else
    return formatted_percentage
  end
end

-- Format a ratio as a percentage.
local function format_ratio(numerator, denominator)
  assert(numerator <= denominator)
  if numerator == denominator then
    return "100%"
  else
    assert(denominator > 0)
    return format_percentage(100.0 * numerator / denominator)
  end
end

-- Print the summary results of analyzing multiple files.
local function print_summary(options, evaluation_results)
  local porcelain, verbose = get_option('porcelain', options), get_option('verbose', options)

  if porcelain then
    return
  end

  local num_files = evaluation_results.num_files
  local num_warnings = evaluation_results.num_warnings
  local num_errors = evaluation_results.num_errors

  io.write(string.format("\n\n%s ", colorize("Total:", BOLD)))

  local errors_message = tostring(num_errors) .. " " .. pluralize("error", num_errors)
  errors_message = colorize(errors_message, BOLD, (num_errors > 0 and RED) or GREEN)
  io.write(errors_message .. ", ")

  local warnings_message = tostring(num_warnings) .. " " .. pluralize("warning", num_warnings)
  warnings_message = colorize(warnings_message, BOLD, (num_warnings > 0 and YELLOW) or GREEN)
  io.write(warnings_message .. " in ")

  io.write(tostring(num_files) .. " " .. pluralize("file", num_files))

  -- Display additional information.
  if verbose then
    print()
    io.write(string.format("\n%s", colorize("Aggregate statistics:", BOLD)))
    -- Display pre-evaluation information.
    local num_total_bytes = evaluation_results.num_total_bytes
    io.write(
      string.format(
        "\n- %s %s total %s",
        colorize("File size:", BOLD),
        titlecase(humanize(num_total_bytes)),
        pluralize("byte", num_total_bytes)
      )
    )
    -- Evaluate the evalution results of the preprocessing.
    local num_expl_bytes = evaluation_results.num_expl_bytes
    if num_expl_bytes == 0 then
      goto skip_remaining_additional_information
    end
    io.write(
      string.format(
        "\n- %s %s expl3 %s (%s of total bytes)",
        colorize("Preprocessing:", BOLD),
        titlecase(humanize(num_expl_bytes)),
        pluralize("byte", num_expl_bytes),
        format_ratio(num_expl_bytes, num_total_bytes)
      )
    )
    -- Evaluate the evalution results of the lexical analysis.
    local num_tokens = evaluation_results.num_tokens
    if num_tokens == 0 then
      goto skip_remaining_additional_information
    end
    io.write(
      string.format(
        "\n- %s %s expl3 %s",
        colorize("Lexical analysis:", BOLD),
        titlecase(humanize(num_tokens)),
        pluralize("token", num_tokens)
      )
    )
    local num_groupings = evaluation_results.num_groupings
    if num_groupings > 0 then
      io.write(string.format(" and %s %s", humanize(num_groupings), pluralize("grouping", num_groupings)))
      local num_unclosed_groupings = evaluation_results.num_unclosed_groupings
      if num_unclosed_groupings > 0 then
        local formatted_grouping_ratio = format_ratio(num_unclosed_groupings, num_groupings)
        io.write(string.format(" (%s unclosed, %s of groupings)", humanize(num_unclosed_groupings), formatted_grouping_ratio))
      end
    end
    -- Evaluate the evalution results of the syntactic and semantic analysis.
    local num_segments_total = evaluation_results.num_segments_total
    local num_calls_total = evaluation_results.num_calls_total
    if num_segments_total == 0 or num_calls_total == 0 then
      goto skip_remaining_additional_information
    end
    io.write(
      string.format(
        "\n- %s %s code %s containing %s %s",
        colorize("Syntactic and semantic analysis:", BOLD),
        titlecase(humanize(num_segments_total)),
        pluralize("segment", num_segments_total),
        humanize(num_calls_total),
        pluralize("call", num_calls_total)
      )
    )
    local num_statements_total = evaluation_results.num_statements_total
    if num_statements_total == 0 then
      goto skip_remaining_additional_information
    end
    if num_statements_total == num_calls_total then
      io.write(string.format(" and %s", pluralize("statement", num_statements_total)))
    else
      io.write(string.format(", %s %s", humanize(num_statements_total), pluralize("statement", num_statements_total)))
    end

    local num_well_understood_tokens = evaluation_results.num_well_understood_tokens
    io.write(string.format("\n- %s ", colorize("Code coverage:", BOLD)))
    if num_well_understood_tokens == 0 then
      io.write(string.format("No well-understood expl3 %s", pluralize("token")))
    else
      io.write(
        string.format(
          "%s well-understood expl3 %s ",
          titlecase(humanize(num_well_understood_tokens)),
          pluralize("token", num_well_understood_tokens)
        )
      )
      if num_expl_bytes == num_total_bytes and num_well_understood_tokens == num_tokens then
        io.write("(all expl3 tokens and bytes)")
      else
        io.write(
          string.format(
            "(%s of expl3 tokens, ~%s of total bytes)",
            format_ratio(num_well_understood_tokens, num_tokens),
            format_ratio(num_well_understood_tokens * num_expl_bytes, num_tokens * num_total_bytes)
          )
        )
      end
    end
  end

  ::skip_remaining_additional_information::

  print()
end

-- Print the results of analyzing a file.
local function print_results(state, options, evaluation_results, is_last_file)
  local pathname, issues, analysis_results = state.pathname, state.issues, state.results
  local porcelain, verbose = get_option('porcelain', options), get_option('verbose', options)
  local line_starting_byte_numbers = analysis_results.line_starting_byte_numbers
  assert(line_starting_byte_numbers ~= nil)
  -- Display an overview.
  local all_issues = {}
  local status
  if(#issues.errors > 0) then
    if not porcelain then
      status = (
        colorize(
          (
            tostring(#issues.errors)
            .. " "
            .. pluralize("error", #issues.errors)
          ), BOLD, RED
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
            ), BOLD, YELLOW
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
          ), BOLD, YELLOW
        )
      end
      table.insert(all_issues, issues.warnings)
    else
      if not porcelain then
        status = colorize("OK", BOLD, GREEN)
      end
    end
  end

  if not porcelain then
    local max_overview_length = get_option('terminal_width', options, pathname)
    local prefix = "Checking "
    local formatted_pathname = format_pathname(
      pathname,
      math.max(
        (
          max_overview_length
          - #prefix
          - #(" ")
          - #decolorize(status)
        ), BOLD
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
          ), BOLD
        )
      )
      .. status
    )
    io.write("\n" .. overview)
  end

  -- Display the errors, followed by warnings.
  if #all_issues > 0 then
    for _, warnings_or_errors in ipairs(all_issues) do
      if not porcelain then
        print()
      end
      -- Display the warnings/errors.
      local sort_issues = require("explcheck-issues").sort_issues
      for _, issue in ipairs(sort_issues(warnings_or_errors)) do
        local code, message, range, context = table.unpack(issue)
        local start_line_number, start_column_number = 1, 1
        local end_line_number, end_column_number = 1, 1
        if range ~= nil then
          start_line_number, start_column_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, range:start())
          end_line_number, end_column_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, range:stop())
          end_column_number = end_column_number
        end
        if not porcelain then
          local position = ":" .. tostring(start_line_number) .. ":" .. tostring(start_column_number) .. ":"
          local max_line_length = get_option('terminal_width', options, pathname)
          local reserved_position_length = 10
          local reserved_message_length = 30
          local reserved_context_length = 20
          local max_context_length = 50
          local label_indent = (" "):rep(4)
          local formatted_message = format_issue_identifier(code) .. " " .. message
          if context ~= nil then
            formatted_message = formatted_message .. ": "
            context = format_context(context, max_context_length)
          else
            context = ""
          end
          local formatted_pathname = format_pathname(
            pathname,
            math.max(
              (
                max_line_length
                - #label_indent
                - reserved_position_length
                - #(" ")
                - math.max(#formatted_message, reserved_message_length)
                - math.max(#context, reserved_context_length)
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
                  - math.max(#formatted_message, reserved_message_length)
                  - math.max(#context, reserved_context_length)
                ), 1
              )
            )
            .. formatted_message
            .. (" "):rep(math.max(reserved_message_length - #formatted_message, 0))
            .. context
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
  end

  -- Display additional information.
  if verbose and not porcelain then
  local line_indent = (" "):rep(4)
    do
      print()
      -- Display pre-evaluation information.
      local num_total_bytes = evaluation_results.num_total_bytes
      if num_total_bytes == 0 then
        io.write(string.format("\n%sEmpty file", line_indent))
        goto skip_remaining_additional_information
      end
      local formatted_file_size = string.format("%s %s", titlecase(humanize(num_total_bytes)), pluralize("byte", num_total_bytes))
      io.write(string.format("\n%s%s %s", line_indent, colorize("File size:", BOLD), formatted_file_size))
      -- Evaluate the evalution results of the preprocessing.
      io.write(string.format("\n\n%s%s", line_indent, colorize("Preprocessing results:", BOLD)))
      local seems_like_latex_style_file = analysis_results.seems_like_latex_style_file
      if seems_like_latex_style_file ~= nil then
        if seems_like_latex_style_file then
          io.write(string.format("\n%s- Seems like a LaTeX style file", line_indent))
        else
          io.write(string.format("\n%s- Doesn't seem like a LaTeX style file", line_indent))
        end
      end
      local num_expl_bytes = evaluation_results.num_expl_bytes
      if num_expl_bytes == 0 or num_expl_bytes == nil then
        io.write(string.format("\n%s- No expl3 material", line_indent))
        goto skip_remaining_additional_information
      end
      local expl_ranges = analysis_results.expl_ranges
      assert(expl_ranges ~= nil)
      assert(#expl_ranges > 0)
      io.write(
        string.format(
          "\n%s- %s %s spanning ",
          line_indent,
          titlecase(humanize(#expl_ranges)),
          pluralize("expl3 part", #expl_ranges)
        )
      )
      if num_expl_bytes == num_total_bytes then
        io.write("the whole file")
      else
        local formatted_expl_bytes = string.format("%s %s", humanize(num_expl_bytes), pluralize("byte", num_expl_bytes))
        local formatted_expl_ratio = format_ratio(num_expl_bytes, num_total_bytes)
        io.write(string.format("%s (%s of file size)", formatted_expl_bytes, formatted_expl_ratio))
        if #expl_ranges == 1 then
          local range = expl_ranges[1]
          local start_line_number, start_column_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, range:start())
          local end_line_number, end_column_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, range:stop())
          local formatted_range_start = string.format("%d:%d", start_line_number, start_column_number)
          local formatted_range_end = string.format("%d:%d", end_line_number, end_column_number)
          io.write(string.format(" between %s and %s", formatted_range_start, formatted_range_end))
        else
          io.write(":")
          for part_number, range in ipairs(expl_ranges) do
            local start_line_number, start_column_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, range:start())
            local end_line_number, end_column_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, range:stop())
            local formatted_range_start = string.format("%d:%d", start_line_number, start_column_number)
            local formatted_range_end = string.format("%d:%d", end_line_number, end_column_number)
            io.write(string.format("\n%s%d. Between ", line_indent:rep(2), part_number))
            io.write(string.format("%s and %s", formatted_range_start, formatted_range_end))
          end
        end
      end
      -- Evaluate the evalution results of the lexical analysis.
      local num_tokens = evaluation_results.num_tokens
      if num_tokens == nil then
        goto skip_remaining_additional_information
      end
      io.write(string.format("\n\n%s%s", line_indent, colorize("Lexical analysis results:", BOLD)))
      if num_tokens == 0 then
        io.write(string.format("\n%s- No tokens in expl3 parts", line_indent))
        goto skip_remaining_additional_information
      end
      io.write(string.format("\n%s- %s %s in expl3 parts", line_indent, titlecase(humanize(num_tokens)), pluralize("token", num_tokens)))
      local num_groupings = evaluation_results.num_groupings
      if num_groupings ~= nil and num_groupings > 0 then
        io.write(string.format("\n%s- %s %s", line_indent, titlecase(humanize(num_groupings)), pluralize("grouping", num_groupings)))
        io.write(" in expl3 parts")
        local num_unclosed_groupings = evaluation_results.num_unclosed_groupings
        assert(num_unclosed_groupings ~= nil)
        if num_unclosed_groupings > 0 then
          local formatted_grouping_ratio = format_ratio(num_unclosed_groupings, num_groupings)
          io.write(string.format(" (%s unclosed, %s of groupings)", humanize(num_unclosed_groupings), formatted_grouping_ratio))
        end
      end
      -- Evaluate the evalution results of the syntactic analysis.
      if evaluation_results.num_segments == nil or evaluation_results.num_calls == nil then
        goto skip_remaining_additional_information
      end
      if evaluation_results.num_statements == nil then
        io.write(string.format("\n\n%s%s", line_indent, colorize("Syntactic analysis results:", BOLD)))
      else
        io.write(string.format("\n\n%s%s", line_indent, colorize("Syntactic and semantic analysis results:", BOLD)))
      end
      local num_segments_total = evaluation_results.num_segments_total
      assert(num_segments_total ~= nil)
      if num_segments_total == 0 then
        io.write(string.format("\n%s- No code %s", line_indent, pluralize("segment")))
        goto skip_remaining_additional_information
      end
      io.write(
        string.format(
          "\n%s- %s code %s:",
          line_indent,
          titlecase(humanize(num_segments_total)),
          pluralize("segment", num_segments_total)
        )
      )
      for segment_type, num_segments in pairs_sorted_by_descending_values(evaluation_results.num_segments) do
        io.write(
          string.format(
            "\n%s%s- %s %s",
            line_indent,
            line_indent,
            titlecase(humanize(num_segments)),
            pluralize(segment_type, num_segments)
          )
        )
      end
      local num_calls_total = evaluation_results.num_calls_total
      assert(num_calls_total ~= nil)
      if num_calls_total == 0 then
        io.write(string.format("\n%s- No %s", line_indent, pluralize("call")))
        goto skip_remaining_additional_information
      end
      io.write(
        string.format(
          "\n%s- %s %s:",
          line_indent,
          titlecase(humanize(num_calls_total)),
          pluralize("call", num_calls_total)
        )
      )
      for call_type, num_call_tokens in pairs_sorted_by_descending_values(evaluation_results.num_call_tokens) do
        local num_calls = evaluation_results.num_calls[call_type]
        assert(num_calls ~= nil)
        io.write(
          string.format(
            "\n%s%s- %s %s spanning %s %s",
            line_indent,
            line_indent,
            titlecase(humanize(num_calls)),
            pluralize(call_type, num_calls),
            humanize(num_call_tokens),
            pluralize("token", num_call_tokens)
          )
        )
      end
      -- Evaluate the evalution results of the semantic analysis.
      if evaluation_results.num_statements == nil then
        goto skip_remaining_additional_information
      end
      local num_statements_total = evaluation_results.num_statements_total
      assert(num_statements_total ~= nil)
      if num_statements_total == 0 then
        io.write(string.format("\n%s- No %s", line_indent, pluralize("statement")))
        goto skip_remaining_additional_information
      end
      io.write(
        string.format(
          "\n%s- %s %s:",
          line_indent,
          titlecase(humanize(num_statements_total)),
          pluralize("statement", num_statements_total)
        )
      )
      for statement_type, num_statement_tokens in pairs_sorted_by_descending_values(evaluation_results.num_statement_tokens) do
        local num_statements = evaluation_results.num_statements[statement_type]
        local num_statement_calls = evaluation_results.num_statement_calls[statement_type]
        assert(num_statements ~= nil)
        assert(num_statement_calls ~= nil)
        io.write(
          string.format(
            "\n%s%s- %s %s spanning %s %s",
            line_indent,
            line_indent,
            titlecase(humanize(num_statements)),
            pluralize(statement_type, num_statements),
            humanize(num_statement_tokens),
            pluralize("token", num_statement_tokens)
          )
        )
        if num_statement_calls ~= num_statements then
          io.write(string.format(" and %s %s", humanize(num_statement_calls), pluralize("call", num_statement_calls)))
        end
      end
      local num_well_understood_tokens = evaluation_results.num_well_understood_tokens
      assert(num_well_understood_tokens ~= nil)
      if num_well_understood_tokens == 0 then
        io.write(string.format("\n%s- No well-understood expl3 %s", line_indent, pluralize("token")))
        goto skip_remaining_additional_information
      end
      io.write(
        string.format(
          "\n%s- %s well-understood expl3 %s ",
          line_indent,
          titlecase(humanize(num_well_understood_tokens)),
          pluralize("token", num_well_understood_tokens)
        )
      )
      if num_expl_bytes == num_total_bytes and num_well_understood_tokens == num_tokens then
        io.write("(all expl3 tokens and bytes)")
      else
        io.write(
          string.format(
            "(%s of expl3 tokens, ~%s of total bytes)",
            format_ratio(num_well_understood_tokens, num_tokens),
            format_ratio(num_well_understood_tokens * num_expl_bytes, num_tokens * num_total_bytes)
          )
        )
      end
    end

    ::skip_remaining_additional_information::

    -- Display early stopping information.
    if analysis_results.stopped_early then
      io.write(
        string.format(
          '\n\n%sProcessing stopped %s because %s.',
          line_indent,
          analysis_results.stopped_early.when,
          analysis_results.stopped_early.reason
        )
      )
    end
  end

  if not porcelain and not is_last_file and (#all_issues > 0 or verbose) then
    print()
  end
end

return {
  format_issue_identifier = format_issue_identifier,
  format_percentage = format_percentage,
  format_ratio = format_ratio,
  humanize = humanize,
  pluralize = pluralize,
  print_results = print_results,
  print_summary = print_summary,
  titlecase = titlecase,
}
