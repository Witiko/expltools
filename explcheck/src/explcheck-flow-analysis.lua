-- The flow analysis step of static analysis determines additional emergent properties of the code.
--
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")

local statement_types = semantic_analysis.statement_types
local statement_confidences = semantic_analysis.statement_confidences  -- luacheck: ignore

local PART = syntactic_analysis.segment_types.PART

local FUNCTION_CALL = statement_types.FUNCTION_CALL
local OTHER_TOKENS_COMPLEX = statement_types.OTHER_TOKENS_COMPLEX

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE

local edge_types = {
  LATER_CODE = string.format("later code after skipping a %s or from a following %s", OTHER_TOKENS_COMPLEX, PART),
  FUNCTION_CALL = FUNCTION_CALL,
  FUNCTION_CALL_RETURN = string.format("return from a %s", FUNCTION_CALL),
}

local LATER_CODE = edge_types.LATER_CODE  -- luacheck: ignore
assert(FUNCTION_CALL == edge_types.FUNCTION_CALL)
local FUNCTION_CALL_RETURN = edge_types.FUNCTION_CALL_RETURN  -- luacheck: ignore

-- Determine whether the semantic analysis step is too confused by the results
-- of the previous steps to run.
local function is_confused(pathname, results, options)
  local format_percentage = require("explcheck-format").format_percentage
  local evaluation = require("explcheck-evaluation")
  local count_tokens = evaluation.count_tokens
  local num_tokens = count_tokens(results)
  assert(num_tokens ~= nil)
  if num_tokens == 0 then
    return false
  end
  assert(num_tokens > 0)
  local count_well_understood_tokens = evaluation.count_well_understood_tokens
  local num_well_understood_tokens = count_well_understood_tokens(results)
  assert(num_well_understood_tokens ~= nil)
  local min_code_coverage = get_option('min_code_coverage', options, pathname)
  local code_coverage = num_well_understood_tokens / num_tokens
  if code_coverage < min_code_coverage then
    local reason = string.format(
      "the code coverage was too low (%s < %s)",
      format_percentage(100.0 * code_coverage),
      format_percentage(100.0 * min_code_coverage)
    )
    return true, reason
  end
  return false
end

-- Detect chunks of known statements.
local function detect_chunks(states, file_number, options)  -- luacheck: ignore options
  local state = states[file_number]

  local pathname = state.pathname  -- luacheck: ignore pathname
  local content = state.content  -- luacheck: ignore content
  local issues = state.issues  -- luacheck: ignore issues
  local results = state.results

  for _, segment in ipairs(results.segments or {}) do
    segment.chunks = {}
    local first_statement_number

    local function record_chunk(last_statement_number, flags)
      if first_statement_number ~= nil then
        local chunk = new_range(first_statement_number, last_statement_number, flags, #segment.statements)
        table.insert(segment.chunks, chunk)
      end
      first_statement_number = nil
    end

    if segment.statements ~= nil then
      for statement_number, statement in ipairs(segment.statements or {}) do
        if statement.type == OTHER_TOKENS_COMPLEX then
          record_chunk(statement_number, EXCLUSIVE)
        else
          first_statement_number = statement_number
        end
      end
      record_chunk(#segment.statements, INCLUSIVE)
    end
  end
end

local substeps = {
  detect_chunks,
}

return {
  edge_types = edge_types,
  is_confused = is_confused,
  name = "flow analysis",
  substeps = substeps,
}
