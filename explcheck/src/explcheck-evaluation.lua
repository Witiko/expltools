-- Evaluation the analysis results, both for individual files and in aggregate.

local token_types = require("explcheck-lexical-analysis").token_types
local statement_confidences = require("explcheck-semantic-analysis").statement_confidences

local ARGUMENT = token_types.ARGUMENT

local DEFINITELY = statement_confidences.DEFINITELY
local NONE = statement_confidences.NONE

local FileEvaluationResults = {}
local AggregateEvaluationResults = {}

-- Count the number of all expl3 bytes in analysis results.
local function count_expl3_bytes(analysis_results)
  local num_expl_bytes
  if analysis_results.expl_ranges ~= nil then
    num_expl_bytes = 0
    for _, range in ipairs(analysis_results.expl_ranges) do
      num_expl_bytes = num_expl_bytes + #range
    end
  end
  return num_expl_bytes
end

-- Count the number of all and unclosed groupings in analysis results.
local function count_groupings(analysis_results)
  local num_groupings, num_unclosed_groupings
  if analysis_results.groupings ~= nil then
    num_groupings, num_unclosed_groupings = 0, 0
    for _, part_groupings in ipairs(analysis_results.groupings) do
      for _, grouping in pairs(part_groupings) do
        num_groupings = num_groupings + 1
        if grouping.stop == nil then
          num_unclosed_groupings = num_unclosed_groupings + 1
        end
      end
    end
  end
  return num_groupings, num_unclosed_groupings
end

-- Count the number of all tokens in analysis results.
local function count_tokens(analysis_results)
  local num_tokens
  if analysis_results.tokens ~= nil then
    num_tokens = 0
    for _, part_tokens in ipairs(analysis_results.tokens) do
      for _, token in ipairs(part_tokens) do
        assert(token.type ~= ARGUMENT)
        num_tokens = num_tokens + 1
      end
    end
  end
  return num_tokens
end

-- Count the number of segments in analysis results.
local function count_segments(analysis_results)
  local num_segments
  local num_segments_total
  if analysis_results.tokens ~= nil then
    num_segments = {}
    num_segments_total = 0
    for _, segment in ipairs(analysis_results.segments) do
      if num_segments[segment.type] == nil then
        num_segments[segment.type] = 0
      end
      num_segments[segment.type] = num_segments[segment.type] + 1
      num_segments_total = num_segments_total + 1
    end
  end
  return num_segments, num_segments_total
end

-- Count the number of calls in analysis results.
local function count_calls(analysis_results)
  local num_calls, num_call_tokens
  local num_calls_total
  for _, segment in ipairs(analysis_results.segments or {}) do
    if segment.calls ~= nil then
      if num_calls == nil then
        assert(num_call_tokens == nil)
        assert(num_calls_total == nil)
        num_calls, num_call_tokens = {}, {}
        num_calls_total = 0
      end
      for _, call in ipairs(segment.calls) do
        if num_calls[call.type] == nil then
          assert(num_call_tokens[call.type] == nil)
          num_calls[call.type] = 0
          num_call_tokens[call.type] = 0
        end
        num_calls[call.type] = num_calls[call.type] + 1
        num_call_tokens[call.type] = num_call_tokens[call.type] + #call.token_range
        num_calls_total = num_calls_total + 1
      end
    end
  end
  return num_calls, num_call_tokens, num_calls_total
end

-- Count the number of statements in analysis results.
local function count_statements(analysis_results)
  local num_statements, num_statement_tokens, num_statement_calls
  local num_statements_total
  for _, segment in ipairs(analysis_results.segments or {}) do
    if segment.statements ~= nil then
      if num_statements == nil then
        assert(num_statement_tokens == nil)
        assert(num_statement_calls == nil)
        assert(num_statements_total == nil)
        num_statements, num_statement_tokens, num_statement_calls = {}, {}, {}
        num_statements_total = 0
      end
      local seen_call_numbers = {}
      for _, statement in ipairs(segment.statements) do
        if num_statements[statement.type] == nil then
          assert(num_statement_tokens[statement.type] == nil)
          assert(num_statement_calls[statement.type] == nil)
          num_statements[statement.type] = 0
          num_statement_tokens[statement.type] = 0
          num_statement_calls[statement.type] = 0
        end
        for call_number, call in statement.call_range:enumerate(segment.calls) do
          if seen_call_numbers[call_number] == nil then
            seen_call_numbers[call_number] = true
            num_statement_tokens[statement.type] = num_statement_tokens[statement.type] + #call.token_range
            num_statement_calls[statement.type] = num_statement_calls[statement.type] + 1
          end
        end
        num_statements[statement.type] = num_statements[statement.type] + 1
        num_statements_total = num_statements_total + 1
      end
    end
  end
  return num_statements, num_statement_tokens, num_statement_calls, num_statements_total
end

-- Determine how many tokens are "well-understood" from analysis results.
--
-- Let S be a set of all statements that contain a token T and originate from a maximally nested segment. Then, T is
-- "well-understood" if the maximum confidence among these statements is 1.0.
--
local function count_well_understood_tokens(analysis_results)
  -- Since segments are ordered from the least to the most nested, there is no need to track the "nesting level".
  -- Instead, the confidence can be accumulated as a minimum over the segments and as a maximum within these segments.
  local is_token_well_understood_outer_accumulator = {}
  local is_empty = true
  for _, segment in ipairs(analysis_results.segments or {}) do
    local part_number = segment.location.part_number
    local tokens = analysis_results.tokens[part_number]
    local is_token_well_understood_inner_accumulator = {}
    for _, statement in ipairs(segment.statements or {}) do
      is_empty = false
      for _, call in statement.call_range:enumerate(segment.calls) do
        for token_number, _ in call.token_range:enumerate(tokens) do
          if is_token_well_understood_inner_accumulator[token_number] == nil then
            is_token_well_understood_inner_accumulator[token_number] = NONE
          end
          is_token_well_understood_inner_accumulator[token_number]
            = math.max(is_token_well_understood_inner_accumulator[token_number], statement.confidence)
        end
      end
    end
    for token_number, confidence in pairs(is_token_well_understood_inner_accumulator) do
      if is_token_well_understood_outer_accumulator[part_number] == nil then
        is_token_well_understood_outer_accumulator[part_number] = {}
      end
      if is_token_well_understood_outer_accumulator[part_number][token_number] == nil then
        is_token_well_understood_outer_accumulator[part_number][token_number] = DEFINITELY
      end
      is_token_well_understood_outer_accumulator[part_number][token_number]
        = math.min(is_token_well_understood_outer_accumulator[part_number][token_number], confidence)
    end
  end
  local num_well_understood_tokens
  if not is_empty then
    num_well_understood_tokens = 0
    for _, confidences in pairs(is_token_well_understood_outer_accumulator) do
      for _, confidence in pairs(confidences) do
        if confidence == DEFINITELY then
          num_well_understood_tokens = num_well_understood_tokens + 1
        end
      end
    end
  end
  return num_well_understood_tokens
end

-- Create a new evaluation results for the analysis results of an individual file.
function FileEvaluationResults.new(cls, state)
  local content, analysis_results, issues = state.content, state.results, state.issues
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Evaluate the pre-analysis information.
  local num_total_bytes = #content
  -- Evaluate the issues.
  local num_warnings = #issues.warnings
  local num_errors = #issues.errors
  -- Evaluate the results of the preprocessing.
  local num_expl_bytes = count_expl3_bytes(analysis_results)
  -- Evaluate the results of the lexical analysis.
  local num_tokens = count_tokens(analysis_results)
  local num_groupings, num_unclosed_groupings = count_groupings(analysis_results)
  -- Evaluate the results of the syntactic and semantic analyses.
  local num_segments, num_segments_total = count_segments(analysis_results)
  local num_calls, num_call_tokens, num_calls_total = count_calls(analysis_results)
  local num_statements, num_statement_tokens, num_statement_calls, num_statements_total = count_statements(analysis_results)
  local num_well_understood_tokens = count_well_understood_tokens(analysis_results)
  -- Initialize the class.
  self.num_total_bytes = num_total_bytes
  self.num_warnings = num_warnings
  self.num_errors = num_errors
  self.num_expl_bytes = num_expl_bytes
  self.num_tokens = num_tokens
  self.num_groupings = num_groupings
  self.num_unclosed_groupings = num_unclosed_groupings
  self.num_segments = num_segments
  self.num_segments_total = num_segments_total
  self.num_calls = num_calls
  self.num_call_tokens = num_call_tokens
  self.num_calls_total = num_calls_total
  self.num_statements = num_statements
  self.num_statement_tokens = num_statement_tokens
  self.num_statement_calls = num_statement_calls
  self.num_statements_total = num_statements_total
  self.num_well_understood_tokens = num_well_understood_tokens
  return self
end

-- Create an aggregate evaluation results.
function AggregateEvaluationResults.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.num_files = 0
  self.num_total_bytes = 0
  self.num_warnings = 0
  self.num_errors = 0
  self.num_expl_bytes = 0
  self.num_tokens = 0
  self.num_groupings = 0
  self.num_unclosed_groupings = 0
  self.num_segments = {}
  self.num_segments_total = 0
  self.num_calls = {}
  self.num_call_tokens = {}
  self.num_calls_total = 0
  self.num_statements = {}
  self.num_statement_tokens = {}
  self.num_statement_calls = {}
  self.num_statements_total = 0
  self.num_well_understood_tokens = 0
  return self
end

-- Add evaluation results of an individual file to the aggregate.
function AggregateEvaluationResults:add(evaluation_results)
  local function aggregate_table(self_table, evaluation_result_table)
    for key, value in pairs(evaluation_result_table) do
      if type(value) == "number" then  -- a simple count
        if self_table[key] == nil then
          self_table[key] = 0
        end
        assert(key ~= "_how")
        if self_table._how ~= nil then
          self_table[key] = self_table._how(self_table[key], value)
        else
          self_table[key] = self_table[key] + value
        end
      elseif type(value) == "table" then  -- a table of counts
        if self_table[key] == nil then
          self_table[key] = {}
        end
        aggregate_table(self_table[key], value)
      else
        error('Unexpected field type "' .. type(value) .. '"')
      end
    end
  end

  self.num_files = self.num_files + 1
  aggregate_table(self, evaluation_results)
end

return {
  count_expl3_bytes = count_expl3_bytes,
  count_groupings = count_groupings,
  count_tokens = count_tokens,
  new_file_results = function(...)
    return FileEvaluationResults:new(...)
  end,
  new_aggregate_results = function(...)
    return AggregateEvaluationResults:new(...)
  end,
}
