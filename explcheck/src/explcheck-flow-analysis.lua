-- The flow analysis step of static analysis determines additional emergent properties of the code.
--
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")

local statement_types = semantic_analysis.statement_types

local PART = syntactic_analysis.segment_types.PART

local FUNCTION_CALL = statement_types.FUNCTION_CALL
local OTHER_TOKENS_COMPLEX = statement_types.OTHER_TOKENS_COMPLEX

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE

local edge_types = {
  AFTER = "pair of successive code chunks",
  FUNCTION_CALL = FUNCTION_CALL,
  FUNCTION_CALL_RETURN = string.format("%s return", FUNCTION_CALL),
}

local AFTER = edge_types.AFTER
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

-- Collect chunks of known statements.
local function collect_chunks(states, file_number, options)  -- luacheck: ignore options
  local state = states[file_number]

  local results = state.results

  for _, segment in ipairs(results.segments or {}) do
    segment.chunks = {}
    local first_statement_number

    -- Record a chunk with a given range of known statements.
    local function record_chunk(last_statement_number, flags)
      if first_statement_number ~= nil then
        local chunk = {
          segment = segment,
          statement_range = new_range(first_statement_number, last_statement_number, flags, #segment.statements),
        }
        table.insert(segment.chunks, chunk)
        first_statement_number = nil
      end
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

-- Draw edges between chunks.
local function draw_edges(states, file_number, options)  -- luacheck: ignore options
  local state = states[file_number]

  local results = state.results
  if results.edges == nil then
    results.edges = {}
  end

  -- Record edges from skipping ahead to the following chunk in a code segment.
  for _, segment in ipairs(results.segments or {}) do
    local previous_chunk
    for _, chunk in ipairs(segment.chunks or {}) do
      if previous_chunk ~= nil then
        local edge = {
          type = AFTER,
          from = previous_chunk,
          to = chunk,
        }
        table.insert(results.edges, edge)
      end
      previous_chunk = chunk
    end
  end

  -- Record edges from skipping ahead to the following expl3 part.
  local previous_part
  for _, segment in ipairs(results.segments or {}) do
    if segment.type == PART and segment.chunks ~= nil and #segment.chunks > 0 then
      if previous_part ~= nil then
        local from_chunk = previous_part.chunks[#previous_part.chunks]
        local from_statement_number = from_chunk.statement_range:stop() + 1
        local to_chunk = segment.chunks[1]
        local to_statement_number = to_chunk.statement_range:start()
        local edge = {
          type = AFTER,
          from = {
            chunk = from_chunk,
            statement_number = from_statement_number,
          },
          to = {
            chunk = to_chunk,
            statement_number = to_statement_number,
          },
        }
        table.insert(results.edges, edge)
      end
      previous_part = segment
    end
  end

  -- Record edges from function calls.
  for _, segment in pairs(results.segments or {}) do
    for _, from_chunk in ipairs(segment.chunks or {}) do
      for from_statement_number, statement in from_chunk.statement_range:enumerate(segment.statements) do
        if statement.type == FUNCTION_CALL then
          for _, nested_segment in ipairs(statement.replacement_text_segments or {}) do
            if nested_segment.chunks ~= nil and #nested_segment.chunks > 0 then
              -- Record the function call itself.
              local to_chunk_start = nested_segment.chunks[1]
              local to_statement_number_start = to_chunk_start.statement_range:start()
              local function_call_edge = {
                type = FUNCTION_CALL,
                from = {
                  chunk = from_chunk,
                  statement_number = from_statement_number,
                },
                to = {
                  chunk = to_chunk_start,
                  statement_number = to_statement_number_start,
                },
              }
              table.insert(results.edges, function_call_edge)
              -- Record the return from the function call.
              local other_file_number = nested_segment.location.file_number
              local other_state = states[other_file_number]
              local other_results = other_state.results
              if other_results.edges == nil then
                other_results.edges = {}
              end
              local to_chunk_end = nested_segment.chunks[#nested_segment.chunks]
              local to_statement_number_end = to_chunk_end.statement_range:stop() + 1
              local function_call_return_edge = {
                type = FUNCTION_CALL_RETURN,
                from = {
                  chunk = to_chunk_end,
                  statement_number = to_statement_number_end,
                },
                to = {
                  chunk = from_chunk,
                  statement_number = from_statement_number + 1,
                },
              }
              table.insert(other_results.edges, function_call_return_edge)
            end
          end
        end
      end
    end
  end
end

local substeps = {
  collect_chunks,
  draw_edges,
}

return {
  edge_types = edge_types,
  is_confused = is_confused,
  name = "flow analysis",
  substeps = substeps,
}
