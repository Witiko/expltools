-- Evaluation the analysis results, both for individual files and in aggregate.

local call_types = require("explcheck-syntactic-analysis").call_types

local CALL = call_types.CALL

local FileEvaluationResult = {}
local AggregateEvaluationResult = {}

local filetype_flags = {
  LATEX = "LaTeX style file",
  OTHER = "other",
}

local LATEX = filetype_flags.LATEX
local OTHER = filetype_flags.OTHER

-- Create a new evaluation result for the analysis results of an individual file.
function FileEvaluationResult.new(cls, content, analysis_results, issues)
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
  local filetype
  if analysis_results.seems_like_latex_style_file ~= nil then
    if analysis_results.seems_like_latex_style_file then
      filetype = LATEX
    else
      filetype = OTHER
    end
  end
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
  local num_calls
  local num_call_tokens
  if analysis_results.calls ~= nil then
    num_calls = 0
    num_call_tokens = 0
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
  self.filetype = filetype
  self.num_expl_bytes = num_expl_bytes
  self.num_tokens = num_tokens
  self.num_calls = num_calls
  self.num_call_tokens = num_call_tokens
  return self
end

-- Create an aggregate evaluation result.
function AggregateEvaluationResult.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.num_files = 0
  self.num_total_bytes = 0
  self.num_warnings = 0
  self.num_errors = 0
  self.filetypes = {}
  self.num_expl_bytes = 0
  self.num_tokens = 0
  self.num_calls = 0
  self.num_call_tokens = 0
  return self
end

-- Add evaluation result of an individual file to the aggregate.
function AggregateEvaluationResult:add(evaluation_result)
  self.num_files = self.num_files + 1
  self.num_total_bytes = self.num_total_bytes + evaluation_result.num_total_bytes
  self.num_warnings = self.num_warnings + evaluation_result.num_warnings
  self.num_errors = self.num_errors + evaluation_result.num_errors
  if evaluation_result.filetype ~= nil then
    if self.filetypes[evaluation_result.filetype] == nil then
      self.filetypes[evaluation_result.filetype] = 0
    end
    self.filetypes[evaluation_result.filetype] = (
      self.filetypes[evaluation_result.filetype]
      + evaluation_result.num_total_bytes
    )
  end
  if evaluation_result.num_expl_bytes ~= nil then
    self.num_expl_bytes = self.num_expl_bytes + evaluation_result.num_expl_bytes
  end
  if evaluation_result.num_tokens ~= nil then
    self.num_tokens = self.num_tokens + evaluation_result.num_tokens
  end
  if evaluation_result.num_calls ~= nil then
    self.num_calls = self.num_calls + evaluation_result.num_calls
  end
  if evaluation_result.num_call_tokens ~= nil then
    self.num_call_tokens = self.num_call_tokens + evaluation_result.num_call_tokens
  end
end

return {
  new_file_result = function(...)
    return FileEvaluationResult:new(...)
  end,
  new_aggregate_result = function(...)
    return AggregateEvaluationResult:new(...)
  end,
  filetype_flags = filetype_flags,
}
