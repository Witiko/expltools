-- Evaluation the analysis results, both for individual files and in aggregate.

local call_types = require("explcheck-syntactic-analysis").call_types

local CALL = call_types.CALL

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
      num_tokens = num_tokens + #part_tokens
    end
  end
  -- Evaluate the results of the syntactic analysis.
  local num_calls, num_call_tokens
  if analysis_results.calls ~= nil then
    num_calls, num_call_tokens = 0, 0
    for _, part_calls in ipairs(analysis_results.calls) do
      for _, call in ipairs(part_calls) do
        local call_type, call_tokens, _, _ = table.unpack(call)
        if call_type == CALL then
          num_calls = num_calls + 1
          num_call_tokens = num_call_tokens + #call_tokens
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
  self.num_calls = num_calls
  self.num_call_tokens = num_call_tokens
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
  self.num_calls = 0
  self.num_call_tokens = 0
  return self
end

-- Add evaluation results of an individual file to the aggregate.
function AggregateEvaluationResults:add(evaluation_results)
  self.num_files = self.num_files + 1
  self.num_total_bytes = self.num_total_bytes + evaluation_results.num_total_bytes
  self.num_warnings = self.num_warnings + evaluation_results.num_warnings
  self.num_errors = self.num_errors + evaluation_results.num_errors
  if evaluation_results.num_expl_bytes ~= nil then
    self.num_expl_bytes = self.num_expl_bytes + evaluation_results.num_expl_bytes
  end
  if evaluation_results.num_tokens ~= nil then
    self.num_tokens = self.num_tokens + evaluation_results.num_tokens
  end
  if evaluation_results.num_calls ~= nil then
    self.num_calls = self.num_calls + evaluation_results.num_calls
  end
  if evaluation_results.num_call_tokens ~= nil then
    self.num_call_tokens = self.num_call_tokens + evaluation_results.num_call_tokens
  end
end

return {
  new_file_results = function(...)
    return FileEvaluationResults:new(...)
  end,
  new_aggregate_results = function(...)
    return AggregateEvaluationResults:new(...)
  end
}
