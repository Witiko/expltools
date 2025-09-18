-- The preprocessing step of static analysis determines which parts of the input files contain expl3 code.

local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local parsers = require("explcheck-parsers")
local utils = require("explcheck-utils")

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

local lpeg = require("lpeg")
local B, Cmt, Cp, Ct, Cc, P, V = lpeg.B, lpeg.Cmt, lpeg.Cp, lpeg.Ct, lpeg.Cc, lpeg.P, lpeg.V

-- Preprocess the content and report any issues.
local function analyze_and_report_issues(states, file_number, options)

  local state = states[file_number]

  local pathname = state.pathname
  local content = state.content
  local issues = state.issues
  local results = state.results

  -- Determine the bytes where lines begin.
  local line_starting_byte_numbers = {}

  local function record_line(line_start)
    table.insert(line_starting_byte_numbers, line_start)
  end

  local line_numbers_grammar = (
    Cp() / record_line
    * (
      (
        parsers.linechar^0
        * parsers.newline
        * Cp()
      ) / record_line
    )^0
  )
  lpeg.match(line_numbers_grammar, content)

  -- Strip TeX comments before further analysis.
  local function strip_comments()
    local transformed_index = 0
    local numbers_of_bytes_removed = {}
    local transformed_text_table = {}
    local content_started = false
    for index, text_position in ipairs(lpeg.match(parsers.commented_lines, content)) do
      local span_range = new_range(transformed_index + 1, text_position, EXCLUSIVE + MAYBE_EMPTY, #content)
      if #span_range > 0 then
        if index % 2 == 1 then  -- chunk of text
          local chunk_text = content:sub(span_range:start(), span_range:stop())
          if content_started or chunk_text:find("%S") ~= nil then
            content_started = true
          end
          table.insert(transformed_text_table, chunk_text)
        else  -- comment
          local comment_text = content:sub(span_range:start(), span_range:stop())
          local comment_start, ignored_issues = lpeg.match(parsers.ignored_issues, comment_text)
          -- If a comment specifies ignored issues, register them.
          if ignored_issues ~= nil then
            local comment_range = new_range(span_range:start() + comment_start - 1, span_range:stop(), INCLUSIVE, #content)
            local comment_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, comment_range:start())
            assert(comment_line_number <= #line_starting_byte_numbers)
            -- If the comment appears before any content other than indentation and comments, ignore all issues everywhere.
            local ignored_range = nil
            -- Otherwise, ignore the issues only on this line, except for file-wide issues, which are always ignored everywhere.
            if content_started then
              local ignored_range_start = line_starting_byte_numbers[comment_line_number]
              local ignored_range_end
              if(comment_line_number + 1 <= #line_starting_byte_numbers) then
                ignored_range_end = line_starting_byte_numbers[comment_line_number + 1]
                ignored_range = new_range(ignored_range_start, ignored_range_end, EXCLUSIVE, #content)
              else
                ignored_range_end = #content
                ignored_range = new_range(ignored_range_start, ignored_range_end, INCLUSIVE, #content)
              end
            end
            if #ignored_issues == 0 then  -- ignore all issues
              issues:ignore({range = ignored_range, source_range = comment_range})
            else  -- ignore specific issues
              for _, identifier in ipairs(ignored_issues) do
                issues:ignore({identifier_prefix = identifier, range = ignored_range, source_range = comment_range})
              end
            end
          end
          table.insert(numbers_of_bytes_removed, {transformed_index, #span_range})
        end
        transformed_index = transformed_index + #span_range
      end
    end
    table.insert(transformed_text_table, content:sub(transformed_index + 1, -1))
    local transformed_text = table.concat(transformed_text_table, "")
    local function map_back(index)
      local mapped_index = index
      for _, where_and_number_of_bytes_removed in ipairs(numbers_of_bytes_removed) do
        local where, number_of_bytes_removed = table.unpack(where_and_number_of_bytes_removed)
        if mapped_index > where then
          mapped_index = mapped_index + number_of_bytes_removed
        else
          break
        end
      end
      assert(mapped_index > 0)
      assert(mapped_index <= #content + 1)
      if mapped_index <= #content then
        assert(transformed_text[index] == content[mapped_index])
      end
      return mapped_index
    end
    return transformed_text, map_back
  end

  local transformed_content, map_back = strip_comments()

  -- Determine which parts of the input files contain expl3 code.
  local expl_ranges = {}
  local input_ended = false

  local function capture_range(should_skip, range_start, range_end)
    if not should_skip then
      local range = new_range(range_start, range_end, EXCLUSIVE, #transformed_content, map_back, #content)
      table.insert(expl_ranges, range)
    end
  end

  local function unexpected_pattern(pattern, code, message, test, include_context)
    return Ct(Cp() * pattern * Cp()) / function(range_table)
      local range_start, range_end = range_table[#range_table - 1], range_table[#range_table]
      local context
      if include_context then
        context = transformed_content:sub(range_start, range_end - 1)
      end
      local range = new_range(range_start, range_end, EXCLUSIVE, #transformed_content, map_back, #content)
      if not input_ended and (test == nil or test(range)) then
        issues:add(code, message, range, context)
      end
    end
  end

  local num_provides = 0
  local FirstLineProvides, FirstLineExplSyntaxOn, HeadlessCloser, Head, Any =
    parsers.fail, parsers.fail, parsers.fail, parsers.fail, parsers.any
  local expl3_detection_strategy = get_option('expl3_detection_strategy', options, pathname)
  if expl3_detection_strategy ~= 'never' and expl3_detection_strategy ~= 'always' then
    FirstLineProvides = unexpected_pattern(
      parsers.provides,
      "e104",
      [[multiple delimiters `\ProvidesExpl*` in a single file]],
      function()
        num_provides = num_provides + 1
        return num_provides > 1
      end
    )
    FirstLineExplSyntaxOn = parsers.expl_syntax_on
    HeadlessCloser = (
      parsers.expl_syntax_off
      + parsers.endinput
      / function()
        input_ended = true
      end
    )
    -- (Under)estimate the current TeX grouping level.
    local estimated_grouping_level = 0
    Any = (
      -B(parsers.expl3_catcodes[0])  -- no preceding backslash
      * parsers.expl3_catcodes[1]  -- begin grouping
      * Cmt(
        parsers.success,
        function()
          estimated_grouping_level = estimated_grouping_level + 1
          return true
        end
      )
      + parsers.expl3_catcodes[2]  -- end grouping
      * Cmt(
        parsers.success,
        function()
          estimated_grouping_level = math.max(0, estimated_grouping_level - 1)
          return true
        end
      )
      + parsers.any
    )
    -- Allow indent before a standard delimiter outside a TeX grouping.
    Head = (
      parsers.newline
      + Cmt(
        parsers.success,
        function()
          return estimated_grouping_level == 0
        end
      )
    )
  end

  local expl3like_material_count, expl3like_material_bytes = 0, 0
  local analysis_grammar = P{
    "Root";
    Root = (
      (
        V"FirstLineExplPart" / capture_range
      )^-1
      * (
        V"NonExplPart"
        * V"ExplPart" / capture_range
      )^0
      * V"NonExplPart"
    ),
    NonExplPart = (
      (
        unexpected_pattern(
          (
            V"Head"
            * Cp()
            * V"HeadlessCloser"
          ),
          "w101",
          "unexpected delimiters"
        )
        + unexpected_pattern(
            parsers.expl3like_material,
            "e102",
            "expl3 material in non-expl3 parts",
            function(byte_range)
              expl3like_material_count = expl3like_material_count + 1
              expl3like_material_bytes = expl3like_material_bytes + #byte_range
              return true
            end,
            true
          )
        + (
          V"Any"
          - V"Opener"
        )
      )^0
    ),
    FirstLineExplPart = (
      Cc(input_ended)
      * V"FirstLineOpener"
      * Cp()
      * (
          V"Provides"
          + unexpected_pattern(
            (
              V"Head"
              * Cp()
              * V"FirstLineOpener"
            ),
            "w101",
            "unexpected delimiters"
          )
          + (
            V"Any"
            - V"Closer"
          )
        )^0
      * (
        V"Head"
        * Cp()
        * V"HeadlessCloser"
        + Cp()
        * parsers.eof
      )
    ),
    ExplPart = (
      V"Head"
      * V"FirstLineExplPart"
    ),
    FirstLineProvides = FirstLineProvides,
    Provides = (
      V"Head"
      * V"FirstLineProvides"
    ),
    FirstLineOpener = (
      FirstLineExplSyntaxOn
      + V"FirstLineProvides"
    ),
    Opener = (
      V"Head"
      * V"FirstLineOpener"
    ),
    HeadlessCloser = HeadlessCloser,
    Closer = (
      V"Head"
      * V"HeadlessCloser"
    ),
    Head = Head,
    Any = Any,
  }
  lpeg.match(analysis_grammar, transformed_content)

  -- Determine whether the pathname/content looks like it originates from a LaTeX style file.
  local seems_like_latex_style_file
  local suffix = utils.get_suffix(pathname)
  if suffix == ".cls" or suffix == ".opt" or suffix == ".sty" then
    seems_like_latex_style_file = true
  else
    seems_like_latex_style_file = lpeg.match(parsers.latex_style_file_content, transformed_content) ~= nil
  end

  -- If no expl3 parts were detected, decide whether no part or the whole input file is in expl3.
  if(#expl_ranges == 0 and #content > 0) then
    issues:ignore({identifier_prefix = 'e102', seen = true})
    if expl3_detection_strategy == "precision" or expl3_detection_strategy == "never" then
      -- Assume that no part of the input file is in expl3.
    elseif expl3_detection_strategy == "recall" or expl3_detection_strategy == "always" then
      -- Assume that the whole input file is in expl3.
      if expl3_detection_strategy == "recall" then
        issues:add('w100', 'no standard delimiters')
      end
      local range = new_range(1, #content, INCLUSIVE, #content)
      table.insert(expl_ranges, range)
    elseif expl3_detection_strategy == "auto" then
      -- Use context clues to determine whether no part or the whole
      -- input file is in expl3.
      local expl3like_material_ratio = 0
      if #content > 0 then
        expl3like_material_ratio = expl3like_material_bytes / #content
      end
      if expl3like_material_count >= get_option('min_expl3like_material_count', options, pathname)
          or expl3like_material_ratio >= get_option('min_expl3like_material_ratio', options, pathname) then
        issues:add('w100', 'no standard delimiters')
        local range = new_range(1, #content, INCLUSIVE, #content)
        table.insert(expl_ranges, range)
      end
    else
      assert(false, 'Unknown strategy "' .. expl3_detection_strategy .. '"')
    end
  end

  -- Check for overlong lines within the expl3 parts.
  for _, expl_range in ipairs(expl_ranges) do
    local offset = expl_range:start() - 1

    local function line_too_long(range_start, range_end)
      local range = new_range(offset + range_start, offset + range_end, EXCLUSIVE, #transformed_content, map_back, #content)
      issues:add('s103', 'line too long', range)
    end

    local overline_lines_grammar = (
      (
        Cp() * parsers.linechar^(get_option('max_line_length', options, pathname) + 1) * Cp() / line_too_long
        + parsers.linechar^0
      )
      * parsers.newline
    )^0

    lpeg.match(overline_lines_grammar, transformed_content:sub(expl_range:start(), expl_range:stop()))
  end

  -- Store the intermediate results of the analysis.
  results.line_starting_byte_numbers = line_starting_byte_numbers
  results.expl_ranges = expl_ranges
  results.seems_like_latex_style_file = seems_like_latex_style_file
end

local substeps = {
  analyze_and_report_issues,
}

return {
  is_confused = function() return false end,
  name = "preprocessing",
  substeps = substeps,
}
