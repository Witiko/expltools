-- The flow analysis step of static analysis determines additional emergent properties of the code.
--
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")

local segment_types = syntactic_analysis.segment_types

local csname_types = semantic_analysis.csname_types
local statement_types = semantic_analysis.statement_types

local PART = segment_types.PART
local TF_TYPE_ARGUMENTS = segment_types.TF_TYPE_ARGUMENTS

local TEXT = csname_types.TEXT

local FUNCTION_CALL = statement_types.FUNCTION_CALL
local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION

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
  NEXT_CHUNK = "pair of successive chunks",
  TF_BRANCH = TF_BRANCH,
  TF_BRANCH_RETURN = string.format("return from %s", TF_BRANCH),
  FUNCTION_CALL = FUNCTION_CALL,
  FUNCTION_CALL_RETURN = string.format("%s return", FUNCTION_CALL),
}

local NEXT_CHUNK = edge_types.NEXT_CHUNK
assert(TF_BRANCH == edge_types.TF_BRANCH)
local TF_BRANCH_RETURN = edge_types.TF_BRANCH_RETURN
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
        elseif first_statement_number == nil then
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
          type = NEXT_CHUNK,
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
          type = NEXT_CHUNK,
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

  -- Record edges from conditional functions to their branches and back.
  for _, from_segment in ipairs(results.segments or {}) do
    for _, from_chunk in ipairs(from_segment.chunks or {}) do
      for from_statement_number, from_statement in from_chunk.statement_range:enumerate(from_segment.statements) do
        for _, call in from_statement.call_range:enumerate(from_segment.calls) do
          for _, argument in ipairs(call.arguments or {}) do
            if argument.segment_number ~= nil then
              local to_segment = results.segments[argument.segment_number]
              if to_segment.type == TF_TYPE_ARGUMENTS and #to_segment.chunks > 0 then
                local forward_to_chunk = to_segment.chunks[1]
                local forward_to_statement_number = forward_to_chunk.statement_range:start()
                local forward_edge = {
                  type = TF_BRANCH,
                  from = {
                    chunk = from_chunk,
                    statement_number = from_statement_number,
                  },
                  to = {
                    chunk = forward_to_chunk,
                    statement_number = forward_to_statement_number,
                  },
                  confidence = MAYBE,
                }
                table.insert(results.edges[STATIC], forward_edge)
                local backward_from_chunk = to_segment.chunks[#to_segment.chunks]
                local backward_from_statement_number = forward_to_chunk.statement_range:stop() + 1
                local backward_edge = {
                  type = TF_BRANCH_RETURN,
                  from = {
                    chunk = backward_from_chunk,
                    statement_number = backward_from_statement_number,
                  },
                  to = {
                    chunk = from_chunk,
                    statement_number = from_statement_number + 1,
                  },
                  confidence = DEFINITELY,
                }
                table.insert(results.edges[STATIC], backward_edge)
              end
            end
          end
        end
      end
    end
  end
end

-- Convert an edge into a tuple that can be used to index the edge in a table.
local function edge_as_tuple(edge)
  return
    edge.type,
    edge.from.chunk,
    edge.from.statement_number,
    edge.to.chunk,
    edge.to.statement_number,
    edge.confidence
end

-- Check whether two sets of edges are equivalent.
local function any_edges_changed(first_edges, second_edges)
  -- Quickly check using set cardinalities.
  if #first_edges ~= #second_edges then
    return true
  end

  -- Index the first edges.
  local first_index = {}
  for _, edge in ipairs(first_edges) do
    local current_table = first_index
    for _, value in ipairs({edge_as_tuple(edge)}) do
      if current_table[value] == nil then
        current_table[value] = {}
      end
      current_table = current_table[value]
    end
  end

  -- Compare the second edges with the indexed first edges.
  for _, edge in ipairs(second_edges) do
    local current_table = first_index
    for _, value in ipairs({edge_as_tuple(edge)}) do
      if current_table[value] == nil then
        return true
      end
      current_table = current_table[value]
    end
  end

  return false
end

-- Draw "dynamic" edges between chunks. A dynamic edge requires estimation.
local function draw_dynamic_edges(results)
  assert(results.edges[DYNAMIC] == nil)
  results.edges[DYNAMIC] = {}

  -- Collect lists of function (variant) definition and function call statements.
  -- TODO: Decide whether we need (both of) these.
  local function_statement_indexes, function_statement_lists = {}, {}
  for _, statement_type in ipairs({FUNCTION_CALL, FUNCTION_DEFINITION, FUNCTION_VARIANT_DEFINITION}) do
    function_statement_indexes[statement_type] = {}
    function_statement_lists[statement_type] = {}
  end
  for _, segment in ipairs(results.segments or {}) do
    for _, chunk in ipairs(segment.chunks or {}) do
      for statement_number, statement in chunk.statement_range:enumerate(segment.statements) do
        if function_statement_indexes[statement.type] ~= nil then
          assert(function_statement_lists[statement.type] ~= nil)

          local function_statement_index = function_statement_indexes[statement.type]
          local function_statement_list = function_statement_lists[statement.type]

          if function_statement_index[chunk] == nil then
            function_statement_index[chunk] = {}
          end
          function_statement_index[chunk][statement_number] = true

          table.insert(function_statement_list, {chunk, statement_number})
        end
      end
    end
  end

  -- Record edges from function calls to function definitions, as discussed in <https://witiko.github.io/Expl3-Linter-11.5/>.
  local previous_function_call_edges
  local current_function_call_edges = {}
  repeat
    previous_function_call_edges = current_function_call_edges

    -- Run reaching definitions, see <https://en.wikipedia.org/wiki/Reaching_definition#Worklist_algorithm>.
    local reaching_definitions_lists = {}

    -- First, index all "static" and currently estimated "dynamic" in- and out-edges for each statement.
    -- TODO: For pseudo-statements, produce paths rather that always start and in an actual statement.
    -- TODO: Reword above comment s/in-edge/incoming edge/, s/out-edge/outgoing edge/.
    -- TODO: Move asserts from lines 386 and 387 here.
    local in_edge_index, out_edge_index = {}, {}
    for _, index_and_key in ipairs({{in_edge_index, 'to'}, {out_edge_index, 'from'}}) do
      local index, key = table.unpack(index_and_key)
      for _, edges in ipairs({results.edges[STATIC], results.edges[DYNAMIC], current_function_call_edges}) do
        for _, edge in ipairs(edges) do
          local chunk, statement_number = edge[key].chunk, edge[key].statement_number
          if index[chunk] == nil then
            index[chunk] = {}
          end
          if index[chunk][statement_number] == nil then
            index[chunk][statement_number] = {}
          end
          table.insert(index[chunk][statement_number], edge)
        end
      end
    end

    -- Initialize a stack of changed statements to a list of all statements.
    local changed_statements = {}
    for _, segment in ipairs(results.segments or {}) do
      for _, chunk in ipairs(segment.chunks or {}) do
        local chunk_statements = {chunk = chunk, statement_numbers = {}}
        for statement_number, _ in chunk.statement_range:enumerate(segment.statements) do
          table.insert(chunk_statements.statement_numbers, statement_number)
        end
        table.insert(changed_statements, chunk_statements)
      end
    end

    -- Iterate over the changed statements until convergence.
    while #changed_statements > 0 do
      -- Pick a statement from the stack of changed statements.
      local chunk_statements = changed_statements[#changed_statements]
      local chunk, statement_numbers = chunk_statements.chunk, chunk_statements.statement_numbers
      assert(#statement_numbers > 0)
      local statement_number = statement_numbers[#statement_numbers]
      local statement = chunk.segment.statements[statement_number]

      -- Remove the statement from the stack.
      if #statement_numbers > 1 then
        -- If there are remaining statements from the top chunk of the stack, keep the chunk at the stack.
        statement_numbers[#statement_numbers] = nil
      else
        -- Otherwise, remove the chunk from the stack as well.
        changed_statements[#changed_statements] = nil
      end

      -- Determine add preceding statements.
      local incoming_definitions_list = {}
      local incoming_chunks_and_statement_numbers = {}
      if statement_number - 1 >= chunk.statement_range:start() then
        -- Consider implicit edges from previous statements within a chunk.
        table.insert(incoming_chunks_and_statement_numbers, {chunk, statement_number - 1})
      end
      if in_edge_index[chunk] ~= nil and in_edge_index[chunk][statement_number] ~= nil then
        -- Consider explicit incoming edges.
        for _, edge in ipairs(in_edge_index[chunk][statement_number]) do
           table.insert(incoming_chunks_and_statement_numbers, {edge.from.chunk, edge.from.statement_number})
        end
      end

      -- Determine the reaching definitions from before the current statement.
      for _, incoming_chunk_and_statement_number in ipairs(incoming_chunks_and_statement_numbers) do
        local incoming_chunk, incoming_statement_number = table.unpack(incoming_chunk_and_statement_number)
        -- assert(incoming_statement_number >= chunk.statement_range:start())
        -- assert(incoming_statement_number <= chunk.statement_range:stop())
        if reaching_definitions_lists[incoming_chunk] ~= nil then
          for _, incoming_statement in ipairs(reaching_definitions_lists[incoming_chunk][incoming_statement_number] or {}) do
            table.insert(incoming_definitions_list, incoming_statement)
          end
        end
      end

      -- Determine the definitions from the current statement.
      local current_definitions_list, invalidated_definitions_index = {}, {}
      if statement.type == FUNCTION_DEFINITION or statement.type == FUNCTION_VARIANT_DEFINITION then
        table.insert(current_definitions_list, statement)
        -- Invalidate definitions of the same control sequence names from before the current statement.
        if statement.defined_csname.type == TEXT then
          for _, incoming_statement in ipairs(incoming_definitions_list) do
            if incoming_statement.defined_csname.type == TEXT and
                incoming_statement.confidence == DEFINITELY and
                incoming_statement.defined_csname.payload == statement.defined_csname.payload then
              invalidated_definitions_index[incoming_statement] = true
            end
          end
        end
      end

      -- Determine the reaching definitions after the current statement.
      local updated_reaching_definitions_list, updated_reaching_definitions_index = {}, {}
      for _, definitions_list in ipairs({incoming_definitions_list, current_definitions_list}) do
        for _, reaching_statement in ipairs(definitions_list) do
          if invalidated_definitions_index[reaching_statement] == nil then
            table.insert(updated_reaching_definitions_list, reaching_statement)
            updated_reaching_definitions_index[reaching_statement] = true
          end
        end
      end

      -- Determine whether the reaching definitions after the current statement have changed.
      local function have_reaching_definitions_changed()
        -- Determine the previous set of definitions, if any.
        if reaching_definitions_lists[chunk] == nil then
          return true
        end
        if reaching_definitions_lists[chunk][statement_number] == nil then
          return true
        end
        local previous_reaching_definitions_list = reaching_definitions_lists[chunk][statement_number]
        assert(previous_reaching_definitions_list ~= nil)

        -- Quickly check using set cardinalities.
        if #previous_reaching_definitions_list ~= #updated_reaching_definitions_list then
          return true
        end

        -- Compare the updated definitions with the previous definitions.
        for _, previous_reaching_statement in ipairs(previous_reaching_definitions_list) do
          if updated_reaching_definitions_index[previous_reaching_statement] == nil then
            return true
          end
        end

        return false
      end

      -- Update the stack of changed statements.
      if have_reaching_definitions_changed() then

        -- Determine all successive statements.
        local outgoing_chunks_and_statement_numbers = {}
        if statement_number + 1 <= chunk.statement_range:stop() then
          -- Consider implicit edges to following statements within a chunk.
          table.insert(outgoing_chunks_and_statement_numbers, {chunk, statement_number + 1})
        end
        if out_edge_index[chunk] ~= nil and out_edge_index[chunk][statement_number] ~= nil then
          -- Consider explicit incoming edges.
          for _, edge in ipairs(out_edge_index[chunk][statement_number]) do
             table.insert(incoming_chunks_and_statement_numbers, {edge.to.chunk, edge.to.statement_number})
          end
        end

        -- TODO: Insert the successive statements into the stack of changed statements.
        -- TODO: We'll need to index the positions of chunks in `changed_statements` to prevent potential duplicates.

      end

      -- Update the reaching definitions.
      if reaching_definitions_lists[chunk] == nil then
        reaching_definitions_lists[chunk] = {}
      end
      if reaching_definitions_lists[chunk][statement_number] == nil then
        reaching_definitions_lists[chunk][statement_number] = {}
      end
      reaching_definitions_lists[chunk][statement_number] = updated_reaching_definitions_list
    end

    -- TODO: Update the current estimation of the function call edges.
  until not any_edges_changed(previous_function_call_edges, current_function_call_edges)

  for _, edge in ipairs(current_function_call_edges) do
    table.insert(results.edges[DYNAMIC], edge)
  end
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
