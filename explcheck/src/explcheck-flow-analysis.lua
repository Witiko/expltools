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

local statement_confidences = semantic_analysis.statement_confidences

local MAYBE = statement_confidences.MAYBE
local DEFINITELY = statement_confidences.DEFINITELY

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE

local edge_categories = {
  STATIC = "static",
  DYNAMIC = "dynamic",
}

local STATIC = edge_categories.STATIC
local DYNAMIC = edge_categories.DYNAMIC

local TF_BRANCH = "T- or F-branch of conditional function"

local edge_types = {
  AFTER = "pair of successive code chunks",
  TF_BRANCH = TF_BRANCH,
  TF_BRANCH_RETURN = string.format("return from %s", TF_BRANCH),
  FUNCTION_CALL = FUNCTION_CALL,
  FUNCTION_CALL_RETURN = string.format("%s return", FUNCTION_CALL),
}

local AFTER = edge_types.AFTER
assert(TF_BRANCH == edge_types.TF_BRANCH)
local TF_BRANCH_RETURN = edge_types.TF_BRANCH_RETURN  -- luacheck: ignore
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

-- Draw "static" edges between chunks. A static edge is known without extra analysis.
local function draw_static_edges(results)
  assert(results.edges[STATIC] == nil)
  results.edges[STATIC] = {}

  -- Record edges from skipping ahead to the following chunk in a code segment.
  for _, segment in ipairs(results.segments or {}) do
    local previous_chunk
    for _, chunk in ipairs(segment.chunks or {}) do
      if previous_chunk ~= nil then
        local from_statement_number = previous_chunk.statement_range:stop() + 1
        local to_statement_number = chunk.statement_range:start()
        local edge = {
          type = AFTER,
          from = {
            chunk = previous_chunk,
            statement_number = from_statement_number,
          },
          to = {
            chunk = chunk,
            statement_number = to_statement_number,
          },
          confidence = MAYBE,
        }
        table.insert(results.edges[STATIC], edge)
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
        -- Determine whether the parts are immediately adjacent.
        local previous_outer_range = results.outer_expl_ranges[previous_part.location.part_number]
        local outer_range = results.outer_expl_ranges[segment.location.part_number]
        assert(previous_outer_range:stop() < outer_range:start())
        local are_adjacent = previous_outer_range:stop() + 1 == outer_range:start()
        local confidence = are_adjacent and DEFINITELY or MAYBE
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
          confidence = confidence,
        }
        table.insert(results.edges[STATIC], edge)
      end
      previous_part = segment
    end
  end

  -- TODO: Record edges from conditional functions to their branches and back.
end

-- Draw "dynamic" edges between chunks. A dynamic edge requires estimation.
local function draw_dynamic_edges(results)
  assert(results.edges[DYNAMIC] == nil)
  results.edges[DYNAMIC] = {}

  -- TODO: Record edges from function calls, as discussed in <https://witiko.github.io/Expl3-Linter-11.5/>.
end

-- Draw edges between chunks.
local function draw_edges(states, file_number, options)  -- luacheck: ignore options
  local state = states[file_number]

  local results = state.results

  assert(results.edges == nil)
  results.edges = {}

  draw_static_edges(results)
  draw_dynamic_edges(results)
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
