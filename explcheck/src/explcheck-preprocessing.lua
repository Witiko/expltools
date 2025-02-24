-- The preprocessing step of static analysis determines which parts of the input files contain expl3 code.

local get_option = require("explcheck-config")
local new_range = require("explcheck-ranges")
local parsers = require("explcheck-parsers")
local utils = require("explcheck-utils")

local lpeg = require("lpeg")
local Cp, P, V = lpeg.Cp, lpeg.P, lpeg.V

-- Preprocess the content and register any issues.
local function preprocessing(issues, pathname, content, options)

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
    for index, text_position in ipairs(lpeg.match(parsers.commented_lines, content)) do
      local span_size = text_position - transformed_index - 1
      if span_size > 0 then
        if index % 2 == 1 then  -- chunk of text
          table.insert(transformed_text_table, content:sub(transformed_index + 1, text_position - 1))
        else  -- comment
          local comment_text = content:sub(transformed_index + 2, text_position - 1)
          local ignored_issues = lpeg.match(parsers.ignored_issues, comment_text)
          -- If a comment specifies ignored issues, register them.
          if ignored_issues ~= nil then
            local comment_line_number = utils.convert_byte_to_line_and_column(line_starting_byte_numbers, transformed_index + 1)
            assert(comment_line_number <= #line_starting_byte_numbers)
            local comment_range_start = line_starting_byte_numbers[comment_line_number]
            local comment_range_end, comment_range
            if(comment_line_number + 1 <= #line_starting_byte_numbers) then
              comment_range_end = line_starting_byte_numbers[comment_line_number + 1]
              comment_range = new_range(comment_range_start, comment_range_end, "exclusive", #content)
            else
              comment_range_end = #content
              comment_range = new_range(comment_range_start, comment_range_end, "inclusive", #content)
            end
            if #ignored_issues == 0 then  -- ignore all issues on this line
              issues:ignore(nil, comment_range)
            else  -- ignore specific issues on this line or everywhere (for file-wide issues)
              for _, identifier in ipairs(ignored_issues) do
                issues:ignore(identifier, comment_range)
              end
            end
          end
          table.insert(numbers_of_bytes_removed, {transformed_index, span_size})
        end
        transformed_index = transformed_index + span_size
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

  local function capture_range(range_start, range_end)
    local range = new_range(range_start, range_end, "exclusive", #transformed_content, map_back, #content)
    table.insert(expl_ranges, range)
  end

  local function unexpected_pattern(pattern, code, message, test)
    return Cp() * pattern * Cp() / function(range_start, range_end)
      local range = new_range(range_start, range_end, "exclusive", #transformed_content, map_back, #content)
      if test == nil or test() then
        issues:add(code, message, range)
      end
    end
  end

  local num_provides = 0
  local Opener, Closer = parsers.fail, parsers.fail
  local expl3_detection_strategy = get_option('expl3_detection_strategy', options, pathname)
  if expl3_detection_strategy ~= 'never' and expl3_detection_strategy ~= 'always' then
    Opener = (
      parsers.expl_syntax_on
      + unexpected_pattern(
        parsers.provides,
        "e104",
        [[multiple delimiters `\ProvidesExpl*` in a single file]],
        function()
          num_provides = num_provides + 1
          return num_provides > 1
        end
      )
    )
    Closer = parsers.expl_syntax_off
  end

  local has_expl3like_material = false
  local analysis_grammar = P{
    "Root";
    Root = (
      (
        V"NonExplPart"
        * V"ExplPart" / capture_range
      )^0
      * V"NonExplPart"
    ),
    NonExplPart = (
      (
        unexpected_pattern(
          V"Closer",
          "w101",
          "unexpected delimiters"
        )
        + unexpected_pattern(
            parsers.expl3like_material,
            "e102",
            "expl3 material in non-expl3 parts",
            function()
              has_expl3like_material = true
              return true
            end
          )
        + (parsers.any - V"Opener")
      )^0
    ),
    ExplPart = (
      V"Opener"
      * Cp()
      * (
          unexpected_pattern(
            V"Opener",
            "w101",
            "unexpected delimiters"
          )
          + (parsers.any - V"Closer")
        )^0
      * Cp()
      * (V"Closer" + parsers.eof)
    ),
    Opener = Opener,
    Closer = Closer,
  }
  lpeg.match(analysis_grammar, transformed_content)

  -- Determine whether the pathname/content looks like it originates from a LaTeX style file.
  local seems_like_latex_style_file
  local suffix = utils.get_suffix(pathname)
  if suffix == ".cls" or suffix == ".opt" or suffix == ".sty" then
    seems_like_latex_style_file = true
  else
    seems_like_latex_style_file = lpeg.match(parsers.latex_style_file_content, transformed_content)
  end

  -- If no expl3 parts were detected, decide whether no part or the whole input file is in expl3.
  if(#expl_ranges == 0 and #content > 0) then
    issues:ignore('e102')
    if expl3_detection_strategy == "precision" or expl3_detection_strategy == "never" then
      -- Assume that no part of the input file is in expl3.
    elseif expl3_detection_strategy == "recall" or expl3_detection_strategy == "always" then
      -- Assume that the whole input file is in expl3.
      if expl3_detection_strategy == "recall" then
        issues:add('w100', 'no standard delimiters')
      end
      local range = new_range(1, #content, "inclusive", #content)
      table.insert(expl_ranges, range)
    elseif expl3_detection_strategy == "auto" then
      -- Use context clues to determine whether no part or the whole
      -- input file is in expl3.
      if has_expl3like_material then
        issues:add('w100', 'no standard delimiters')
        local range = new_range(1, #content, "inclusive", #content)
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
      local range = new_range(offset + range_start, offset + range_end, "exclusive", #transformed_content, map_back, #content)
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

  return line_starting_byte_numbers, expl_ranges, seems_like_latex_style_file
end

return preprocessing
