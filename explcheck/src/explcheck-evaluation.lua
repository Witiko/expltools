-- Evaluation the analysis results, both for individual files and in aggregate.

local semantic_analysis = require("explcheck-semantic-analysis")

local token_types = require("explcheck-lexical-analysis").token_types
local statement_types = semantic_analysis.statement_types
local statement_subtypes = semantic_analysis.statement_subtypes

local ARGUMENT = token_types.ARGUMENT

local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_DEFINITION_DIRECT = statement_subtypes.FUNCTION_DEFINITION.DIRECT

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

-- Count the number of all top-level calls in analysis results.
local function count_top_level_calls(analysis_results)
  local num_calls, num_call_tokens, num_calls_total
  if analysis_results.calls ~= nil then
    num_calls, num_call_tokens = {}, {}
    num_calls_total = 0
    for _, part_calls in ipairs(analysis_results.calls) do
      for _, call in ipairs(part_calls) do
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
  -- Evaluate the results of the syntactic analysis.
  local num_calls, num_call_tokens, num_calls_total = count_top_level_calls(analysis_results)
  local num_replacement_text_calls, num_replacement_text_call_tokens
  local num_replacement_text_calls_total
  if analysis_results.replacement_texts ~= nil then
    num_replacement_text_calls, num_replacement_text_call_tokens = {}, {}
    num_replacement_text_calls_total = 0
    for _, part_replacement_texts in ipairs(analysis_results.replacement_texts) do
      for _, replacement_text_calls in ipairs(part_replacement_texts.calls) do
        for _, call in pairs(replacement_text_calls) do
          if num_replacement_text_calls[call.type] == nil then
            assert(num_replacement_text_call_tokens[call.type] == nil)
            num_replacement_text_calls[call.type] = 0
            num_replacement_text_call_tokens[call.type] = 0
          end
          num_replacement_text_calls[call.type] = num_replacement_text_calls[call.type] + 1
          num_replacement_text_call_tokens[call.type] = num_replacement_text_call_tokens[call.type] + #call.token_range
          num_replacement_text_calls_total = num_replacement_text_calls_total + 1
        end
      end
    end
  end
  -- Evaluate the results of the semantic analysis.
  local num_statements, num_statement_tokens
  local num_statements_total
  if analysis_results.statements ~= nil then
    num_statements, num_statement_tokens = {}, {}
    num_statements_total = 0
    for part_number, part_statements in ipairs(analysis_results.statements) do
      local seen_call_numbers = {}
      local part_calls = analysis_results.calls[part_number]
      for _, statement in ipairs(part_statements) do
        if num_statements[statement.type] == nil then
          assert(num_statement_tokens[statement.type] == nil)
          num_statements[statement.type] = 0
          num_statement_tokens[statement.type] = 0
        end
        num_statements[statement.type] = num_statements[statement.type] + 1
        for call_number, call in statement.call_range:enumerate(part_calls) do
          if seen_call_numbers[call_number] == nil then
            seen_call_numbers[call_number] = true
            num_statement_tokens[statement.type] = num_statement_tokens[statement.type] + #call.token_range
          end
        end
        num_statements_total = num_statements_total + 1
      end
    end
  end
  local num_replacement_text_statements, num_replacement_text_statement_tokens
  local num_replacement_text_statements_total, replacement_text_max_nesting_depth
  local seen_replacement_text_call_numbers = {}
  if analysis_results.replacement_texts ~= nil then
    num_replacement_text_statements, num_replacement_text_statement_tokens = {}, {}
    num_replacement_text_statements_total = 0
    replacement_text_max_nesting_depth = {}

    for _, part_replacement_texts in ipairs(analysis_results.replacement_texts) do
      for replacement_text_number, replacement_text_statements in ipairs(part_replacement_texts.statements) do
        seen_replacement_text_call_numbers[replacement_text_number] = {}
        local nesting_depth = part_replacement_texts.nesting_depth[replacement_text_number]
        for _, statement in pairs(replacement_text_statements) do
          if num_replacement_text_statements[statement.type] == nil then
            assert(num_replacement_text_statement_tokens[statement.type] == nil)
            num_replacement_text_statements[statement.type] = 0
            num_replacement_text_statement_tokens[statement.type] = 0
            replacement_text_max_nesting_depth[statement.type] = 0
          end
          num_replacement_text_statements[statement.type] = num_replacement_text_statements[statement.type] + 1
          if nesting_depth == 1 or statement.type ~= FUNCTION_DEFINITION or statement.subtype ~= FUNCTION_DEFINITION_DIRECT then
            -- prevent counting overlapping tokens from nested function definitions several times
            for call_number, call in statement.call_range:enumerate(part_replacement_texts.calls[replacement_text_number]) do
              if seen_replacement_text_call_numbers[replacement_text_number][call_number] == nil then
                seen_replacement_text_call_numbers[replacement_text_number][call_number] = true
                num_replacement_text_statement_tokens[statement.type]
                  = num_replacement_text_statement_tokens[statement.type] + #call.token_range
              end
            end
          end
          num_replacement_text_statements_total = num_replacement_text_statements_total + 1
          replacement_text_max_nesting_depth[statement.type]
            = math.max(replacement_text_max_nesting_depth[statement.type], nesting_depth)
        end
      end
    end
  end
  -- Initialize the class.
  self.num_total_bytes = num_total_bytes
  self.num_warnings = num_warnings
  self.num_errors = num_errors
  self.num_expl_bytes = num_expl_bytes
  self.num_tokens = num_tokens
  self.num_groupings = num_groupings
  self.num_unclosed_groupings = num_unclosed_groupings
  self.num_calls = num_calls
  self.num_call_tokens = num_call_tokens
  self.num_calls_total = num_calls_total
  self.num_replacement_text_calls = num_replacement_text_calls
  self.num_replacement_text_call_tokens = num_replacement_text_call_tokens
  self.num_replacement_text_calls_total = num_replacement_text_calls_total
  self.num_statements = num_statements
  self.num_statement_tokens = num_statement_tokens
  self.num_statements_total = num_statements_total
  self.num_replacement_text_statements = num_replacement_text_statements
  self.num_replacement_text_statement_tokens = num_replacement_text_statement_tokens
  self.num_replacement_text_statements_total = num_replacement_text_statements_total
  self.replacement_text_max_nesting_depth = replacement_text_max_nesting_depth
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
  self.num_calls = {}
  self.num_call_tokens = {}
  self.num_calls_total = 0
  self.num_replacement_text_calls = {}
  self.num_replacement_text_call_tokens = {}
  self.num_replacement_text_calls_total = 0
  self.num_statements = {}
  self.num_statement_tokens = {}
  self.num_statements_total = 0
  self.num_replacement_text_statements = {}
  self.num_replacement_text_statement_tokens = {}
  self.num_replacement_text_statements_total = 0
  self.replacement_text_max_nesting_depth = {_how = math.max}
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
