-- The preprocessing step of static analysis determines which parts of the input files contain expl3 code.

local parsers = require("explcheck-parsers")
local utils = require("explcheck-utils")

local lpeg = require("lpeg")
local Cp, Ct, P, V = lpeg.Cp, lpeg.Ct, lpeg.P, lpeg.V

-- Preprocess the content and register any issues.
local function preprocessing(issues, content, options)

  -- Determine the bytes where lines begin.
  local line_starting_byte_numbers = {}

  local function record_line(line_start)
    table.insert(line_starting_byte_numbers, line_start)
  end

  local function line_too_long(range_start, range_end)
    issues:add('s103', 'line too long', range_start, range_end + 1)
  end

  local line_numbers_grammar = (
    Cp() / record_line
    * (
      (
        (
          Cp() * parsers.linechar^(utils.get_option(options, 'max_line_length') + 1) * Cp() / line_too_long
          + parsers.linechar^0
        )
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
    for index, text_position in ipairs(lpeg.match(Ct(parsers.commented_line^1), content)) do
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
            local comment_range_end
            if(comment_line_number + 1 <= #line_starting_byte_numbers) then
              comment_range_end = line_starting_byte_numbers[comment_line_number + 1] - 1
            else
              comment_range_end = #content
            end
            if #ignored_issues == 0 then  -- ignore all issues on this line
              issues:ignore(nil, comment_range_start, comment_range_end)
            else  -- ignore specific issues on this line or everywhere (for file-wide issues)
              for _, identifier in ipairs(ignored_issues) do
                issues:ignore(identifier, comment_range_start, comment_range_end)
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
    range_start, range_end = map_back(range_start), map_back(range_end)
    table.insert(expl_ranges, {range_start, range_end})
  end

  local function unexpected_pattern(pattern, code, message, test)
    return Cp() * pattern * Cp() / function(range_start, range_end)
      range_start, range_end = map_back(range_start), map_back(range_end)
      if test == nil or test() then
        issues:add(code, message, range_start, range_end + 1)
      end
    end
  end

  local num_provides = 0
  local Opener = unexpected_pattern(
    parsers.provides,
    "e104",
    [[multiple delimiters `\ProvidesExpl*` in a single file]],
    function()
      num_provides = num_provides + 1
      return num_provides > 1
    end
  )
  local Closer = parsers.fail
  if not utils.get_option(options, 'expect_expl3_everywhere') then
    Opener = (
      parsers.expl_syntax_on
      + Opener
    )
    Closer = (
      parsers.expl_syntax_off
      + Closer
    )
  end

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
            "expl3 material in non-expl3 parts"
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

  -- If no parts were detected, assume that the whole input file is in expl3.
  if(#expl_ranges == 0 and #content > 0) then
    table.insert(expl_ranges, {1, #content + 1})
    issues:ignore('e102')
    if not utils.get_option(options, 'expect_expl3_everywhere') then
      issues:add('w100', 'no standard delimiters')
    end
  end
  return line_starting_byte_numbers, expl_ranges
end

return preprocessing
