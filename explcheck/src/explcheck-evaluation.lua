-- Evaluation the analysis results, both for individual files and in aggregate.

local token_types = require("explcheck-lexical-analysis").token_types

local ARGUMENT = token_types.ARGUMENT

local FileEvaluationResults = {}
local AggregateEvaluationResults = {}

-- Create a new evaluation results for the analysis results of an individual file.
function FileEvaluationResults.new(cls, content, analysis_results, issues)
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
  local num_expl_bytes
  if analysis_results.expl_ranges ~= nil then
    num_expl_bytes = 0
    for _, range in ipairs(analysis_results.expl_ranges) do
      num_expl_bytes = num_expl_bytes + #range
    end
  end
  -- Evaluate the results of the lexical analysis.
  local num_tokens
  if analysis_results.tokens ~= nil then
    num_tokens = 0
    for _, part_tokens in ipairs(analysis_results.tokens) do
      for _, token in ipairs(part_tokens) do
        assert(token[1] ~= ARGUMENT)
        num_tokens = num_tokens + 1
      end
    end
  end
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
  -- Evaluate the results of the syntactic analysis.
  local num_calls, num_call_tokens
  local num_calls_total
  if analysis_results.calls ~= nil then
    num_calls, num_call_tokens = {}, {}
    num_calls_total = 0
    for _, part_calls in ipairs(analysis_results.calls) do
      for _, call in ipairs(part_calls) do
        local call_type, call_tokens, _, _ = table.unpack(call)
        if num_calls[call_type] == nil then
          assert(num_call_tokens[call_type] == nil)
          num_calls[call_type] = 0
          num_call_tokens[call_type] = 0
        end
        num_calls[call_type] = num_calls[call_type] + 1
        num_call_tokens[call_type] = num_call_tokens[call_type] + #call_tokens
        num_calls_total = num_calls_total + 1
      end
    end
  end
  local num_replacement_text_calls, num_replacement_text_call_tokens
  local num_replacement_text_calls_total
  if analysis_results.replacement_texts ~= nil then
    num_replacement_text_calls, num_replacement_text_call_tokens = {}, {}
    num_replacement_text_calls_total = 0
    for _, part_replacement_texts in ipairs(analysis_results.replacement_texts) do
      for _, replacement_text in ipairs(part_replacement_texts) do
        for _, call in pairs(replacement_text.calls) do
          local call_type, call_tokens, _, _ = table.unpack(call)
          if num_replacement_text_calls[call_type] == nil then
            assert(num_replacement_text_call_tokens[call_type] == nil)
            num_replacement_text_calls[call_type] = 0
            num_replacement_text_call_tokens[call_type] = 0
          end
          num_replacement_text_calls[call_type] = num_replacement_text_calls[call_type] + 1
          num_replacement_text_call_tokens[call_type] = num_replacement_text_call_tokens[call_type] + #call_tokens
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
      local part_calls = analysis_results.calls[part_number]
      for statement_number, statement in ipairs(part_statements) do
        local statement_type = table.unpack(statement)
        local call_type, call_tokens = table.unpack(part_calls[statement_number])
        if num_statements[call_type] == nil then
          assert(num_statement_tokens[call_type] == nil)
          num_statements[call_type] = {}
          num_statement_tokens[call_type] = {}
        end
        if num_statements[call_type][statement_type] == nil then
          assert(num_statement_tokens[call_type][statement_type] == nil)
          num_statements[call_type][statement_type] = 0
          num_statement_tokens[call_type][statement_type] = 0
        end
        num_statements[call_type][statement_type] = num_statements[call_type][statement_type] + 1
        num_statement_tokens[call_type][statement_type] = num_statement_tokens[call_type][statement_type] + #call_tokens
        num_statements_total = num_statements_total + 1
      end
    end
  end
  local num_replacement_text_statements, num_replacement_text_statement_tokens
  local num_replacement_text_statements_total, replacement_text_max_depth
  if analysis_results.replacement_texts ~= nil then
    num_replacement_text_statements, num_replacement_text_statement_tokens = {}, {}
    num_replacement_text_statements_total, replacement_text_max_depth = 0, 0
    for _, part_replacement_texts in ipairs(analysis_results.replacement_texts) do
      for _, replacement_text in ipairs(part_replacement_texts) do
        replacement_text_max_depth = math.max(replacement_text_max_depth, replacement_text.max_depth)
        for statement_number, statement in pairs(replacement_text.statements) do
          local statement_type = table.unpack(statement)
          local call_type, call_tokens = table.unpack(replacement_text.call[statement_number])
          if num_replacement_text_statements[call_type] == nil then
            assert(num_replacement_text_statement_tokens[call_type] == nil)
            num_replacement_text_statements[call_type] = {}
            num_replacement_text_statement_tokens[call_type] = {}
          end
          if num_replacement_text_statements[call_type][statement_type] == nil then
            assert(num_replacement_text_statement_tokens[call_type][statement_type] == nil)
            num_replacement_text_statements[call_type][statement_type] = 0
            num_replacement_text_statement_tokens[call_type][statement_type] = 0
          end
          num_replacement_text_statements[call_type][statement_type]
            = num_replacement_text_statements[call_type][statement_type] + 1
          num_replacement_text_statement_tokens[call_type][statement_type]
            = num_replacement_text_statement_tokens[call_type][statement_type] + #call_tokens
          num_replacement_text_statements_total = num_replacement_text_statements_total + 1
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
  self.replacement_text_max_depth = replacement_text_max_depth
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
  self.replacement_text_max_depth = 0
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
        if key == "replacement_text_max_depth" then
          self_table[key] = math.max(self_table[key], value)
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
  new_file_results = function(...)
    return FileEvaluationResults:new(...)
  end,
  new_aggregate_results = function(...)
    return AggregateEvaluationResults:new(...)
  end
}
