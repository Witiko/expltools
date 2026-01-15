-- The flow analysis step of static analysis determines additional emergent properties of the code.
--
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")
local get_basename = require("explcheck-utils").get_basename

local segment_types = syntactic_analysis.segment_types
local segment_subtypes = syntactic_analysis.segment_subtypes

local csname_types = semantic_analysis.csname_types
local statement_types = semantic_analysis.statement_types
local statement_subtypes = semantic_analysis.statement_subtypes

local PART = segment_types.PART
local TF_TYPE_ARGUMENTS = segment_types.TF_TYPE_ARGUMENTS

local T_TYPE_ARGUMENTS = segment_subtypes.TF_TYPE_ARGUMENTS.T_TYPE_ARGUMENTS
local F_TYPE_ARGUMENTS = segment_subtypes.TF_TYPE_ARGUMENTS.F_TYPE_ARGUMENTS

local TEXT = csname_types.TEXT

local FUNCTION_CALL = statement_types.FUNCTION_CALL
local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION

local FUNCTION_DEFINITION_DIRECT = statement_subtypes.FUNCTION_DEFINITION.DIRECT

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
local FUNCTION_CALL_RETURN = edge_types.FUNCTION_CALL_RETURN

local edge_subtypes = {
  TF_BRANCH = {
    T_BRANCH = "(return from) T-branch of conditional function",
    F_BRANCH = "(return from) F-branch of conditional function",
  },
}

local T_BRANCH = edge_subtypes.TF_BRANCH.T_BRANCH
local F_BRANCH = edge_subtypes.TF_BRANCH.F_BRANCH

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
local function draw_static_edges(states, file_number, options)  -- luacheck: ignore options
  local state = states[file_number]

  local results = state.results

  assert(results.edges == nil)
  results.edges = {}
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
                local edge_subtype
                if to_segment.subtype == T_TYPE_ARGUMENTS then
                  edge_subtype = T_BRANCH
                elseif to_segment.subtype == F_TYPE_ARGUMENTS then
                  edge_subtype = F_BRANCH
                else
                  error('Unexpected segment subtype "' .. to_segment.subtype .. '"')
                end
                local forward_to_chunk = to_segment.chunks[1]
                local forward_to_statement_number = forward_to_chunk.statement_range:start()
                local forward_edge = {
                  type = TF_BRANCH,
                  subtype = edge_subtype,
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
                  subtype = edge_subtype,
                  from = {
                    chunk = backward_from_chunk,
                    statement_number = backward_from_statement_number,
                  },
                  to = {
                    chunk = from_chunk,
                    statement_number = from_statement_number + 1,
                  },
                  -- TODO: Use the same confidence for the backward edge instead of always using DEFINITELY. Rationale: A function
                  -- defined only in a single branch should not propagate to the (pseudo-)statement after the conditional function
                  -- with the confidence DEFINITELY.
                  -- TODO: Also update <https://witiko.github.io/Expl3-Linter-11.5/>, which also makes this mistake.
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
local function draw_dynamic_edges(states, file_number, options)  -- luacheck: ignore file_number
  -- Skip `expl3-code.tex` to see if the processing converges on other files from TeX Live.
  --
  -- TODO: Revert commit 1a6f825.
  local pathname_group = {}
  for _, state in ipairs(states) do
    local basename = get_basename(state.pathname)
    if basename == "expl3-code.tex" or basename == "acro-examples.sty" then
      return
    end
    table.insert(pathname_group, state.pathname)
  end

  -- Draw dynamic edges once between all files in the file group, not just individual files.
  if states.drew_dynamic_edges ~= nil then
    return
  end
  states.drew_dynamic_edges = true

  -- Check whether a function (variant) definition or a function call statement is well-behaved in the sense that we know its
  -- control sequence names precisely and not just as a probabilistic pattern.
  --
  -- TODO: Skip statements from files in the current file group that have never reached the flow analysis. We can check this
  -- by also passing in `chunk` and checking that `states[chunk.segment.location.file_number].results.edges ~= nil`. We should
  -- likely also check this in all `for _, state in ipairs(states) do`-loops by continuing if `state.results.edges == nil`.
  local function is_well_behaved(statement)
    local result
    if statement.type == FUNCTION_CALL then
      result = statement.used_csname.type == TEXT
    elseif statement.type == FUNCTION_DEFINITION then
      result = statement.defined_csname.type == TEXT and statement.subtype == FUNCTION_DEFINITION_DIRECT
    elseif statement.type == FUNCTION_VARIANT_DEFINITION then
      result = statement.base_csname.type == TEXT or statement.defined_csname.type == TEXT
    else
      error('Unexpected statement type "' .. statement.type .. '"')
    end
    return result
  end

  -- Collect a list of function (variant) definition and call statements.
  local function_call_list, function_definition_list = {}, {}
  for _, state in ipairs(states) do
    for _, segment in ipairs(state.results.segments or {}) do
      for _, chunk in ipairs(segment.chunks or {}) do
        for statement_number, statement in chunk.statement_range:enumerate(segment.statements) do
          if statement.type ~= FUNCTION_CALL and
              statement.type ~= FUNCTION_DEFINITION and
              statement.type ~= FUNCTION_VARIANT_DEFINITION then
            goto next_statement
          end
          if not is_well_behaved(statement) then
            goto next_statement
          end
          if statement.type == FUNCTION_CALL then
            table.insert(function_call_list, {chunk, statement_number})
          elseif statement.type == FUNCTION_DEFINITION or
             statement.type == FUNCTION_VARIANT_DEFINITION then
            table.insert(function_definition_list, {chunk, statement_number})
          else
            error('Unexpected statement type "' .. statement.type .. '"')
          end
          ::next_statement::
        end
      end
    end
  end

  -- Collect lists of function (variant) definition and function call statements.
  local function_statement_indexes, function_statement_lists = {}, {}
  for _, statement_type in ipairs({FUNCTION_CALL, FUNCTION_DEFINITION, FUNCTION_VARIANT_DEFINITION}) do
    function_statement_indexes[statement_type] = {}
    function_statement_lists[statement_type] = {}
  end
  for _, state in ipairs(states) do
    for _, segment in ipairs(state.results.segments or {}) do
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
  end

  -- Determine edges from function calls to function definitions, as discussed in <https://witiko.github.io/Expl3-Linter-11.5/>.
  local previous_function_call_edges
  local current_function_call_edges = {}
  local max_reaching_definition_inner_loops = get_option('max_reaching_definition_inner_loops', options)
  local max_reaching_definition_outer_loops = get_option('max_reaching_definition_outer_loops', options)
  local outer_loop_number = 1
  repeat
    -- Guard against long (infinite?) loops.
    if outer_loop_number > max_reaching_definition_outer_loops then
      error(
        string.format(
          "Reaching definitions took more than %d outer loops, try increasing the `max_reaching_definition_outer_loops` Lua option",
          max_reaching_definition_outer_loops
        )
      )
    end

    -- Run reaching definitions, see <https://en.wikipedia.org/wiki/Reaching_definition#Worklist_algorithm>.
    local reaching_definition_lists, reaching_definition_confidence_lists = {}, {}
    local reaching_definition_indexes, reaching_definition_confidence_indexes = {}, {}

    -- First, index all "static" and currently estimated "dynamic" incoming and outgoing edges for each statement.
    local in_edge_index, out_edge_index = {}, {}
    local edge_lists = {current_function_call_edges}
    for _, state in ipairs(states) do
      if state.results.edges ~= nil and state.results.edges[STATIC] ~= nil then
        table.insert(edge_lists, state.results.edges[STATIC])
      end
    end
    for _, edge_index_and_key in ipairs({
          {in_edge_index, 'to'},
          {out_edge_index, 'from'},
        }) do
      local edge_index, key = table.unpack(edge_index_and_key)
      for _, edges in ipairs(edge_lists) do
        for _, edge in ipairs(edges) do
          local chunk, statement_number = edge[key].chunk, edge[key].statement_number
          if edge_index[chunk] == nil then
            edge_index[chunk] = {}
          end
          if edge_index[chunk][statement_number] == nil then
            edge_index[chunk][statement_number] = {}
          end
          table.insert(edge_index[chunk][statement_number], edge)
        end
      end
    end

    -- Record which statements may immediately continue to the following statements and which may not.
    --
    -- TODO: Add a MAYBE edge from conditional functions with only a T- or an F-type argument, not both. Idea: Instead of recording
    -- the lack of an implicit edge, record the edge confidence with a default of DEFINITELY by the way of a metatable.
    local lacks_implicit_out_edges = {}
    for _, state in ipairs(states) do
      for _, segment in ipairs(state.results.segments or {}) do
        for _, chunk in ipairs(segment.chunks or {}) do
          if out_edge_index[chunk] == nil then
            goto next_chunk
          end
          for statement_number, _ in chunk.statement_range:enumerate(segment.statements) do
            if out_edge_index[chunk][statement_number] == nil then
              goto next_statement
            end

            local has_f_branch, has_t_branch = false
            for _, edge in ipairs(out_edge_index[chunk][statement_number]) do
              -- Statements with outgoing function calls may not immediately continue to the following statements.
              if edge.type == FUNCTION_CALL and edge.confidence == DEFINITELY then
                goto lacks_implicit_out_edge
              end

              -- Statements with outgoing both T- and F-branches may not immediately continue to the following statements.
              if edge.type == TF_BRANCH then
                if edge.subtype == T_BRANCH then
                  has_t_branch = true
                elseif edge.subtype == F_BRANCH then
                  has_f_branch = true
                else
                  error('Unexpected edge subtype "' .. edge.subtype .. '"')
                end
                if has_t_branch and has_f_branch then
                  goto lacks_implicit_out_edge
                end
              end
            end

            goto next_statement

            ::lacks_implicit_out_edge::

            if lacks_implicit_out_edges[chunk] == nil then
              lacks_implicit_out_edges[chunk] = {}
            end
            lacks_implicit_out_edges[chunk][statement_number] = true

            ::next_statement::
          end
          ::next_chunk::
        end
      end
    end

    -- Initialize a stack of changed statements to all well-behaved function (variant) definitions.
    local changed_statements_list, changed_statements_index = {}, {}

    -- Pop a changed statement off the top of stack.
    local function pop_changed_statement()
      -- Pick a statement from the stack of changed statements.
      local chunk_statements = changed_statements_list[#changed_statements_list]
      local chunk = chunk_statements.chunk
      local statement_numbers_list = chunk_statements.statement_numbers_list
      local statement_numbers_index = chunk_statements.statement_numbers_index
      assert(#statement_numbers_list > 0)
      local statement_number = statement_numbers_list[#statement_numbers_list]

      -- Remove the statement from the stack.
      if #statement_numbers_list > 1 then
        -- If there are remaining statements from the top chunk of the stack, keep the chunk at the stack.
        table.remove(statement_numbers_list)
        statement_numbers_index[statement_number] = nil
      else
        -- Otherwise, remove the chunk from the stack as well.
        table.remove(changed_statements_list)
        changed_statements_index[chunk] = nil
      end

      return chunk, statement_number
    end

    -- Add a changed statement on the top of the stack.
    local function add_changed_statement(chunk, statement_number)
      -- Get the stack of statements for the given chunk, inserting it if it doesn't exist.
      local chunk_statements
      if changed_statements_index[chunk] == nil then
        chunk_statements = {
          chunk = chunk,
          statement_numbers_list = {},
          statement_numbers_index = {},
        }
        table.insert(changed_statements_list, chunk_statements)
        changed_statements_index[chunk] = #changed_statements_list
      else
        chunk_statements = changed_statements_list[changed_statements_index[chunk]]
      end

      -- Insert the statement to the stack if it isn't there already.
      local statement_numbers_list = chunk_statements.statement_numbers_list
      local statement_numbers_index = chunk_statements.statement_numbers_index
      if statement_numbers_index[statement_number] == nil then
        table.insert(statement_numbers_list, statement_number)
        statement_numbers_index[statement_number] = #statement_numbers_list
      end
    end

    for _, chunk_and_statement_number in ipairs(function_definition_list) do
      local chunk, statement_number = table.unpack(chunk_and_statement_number)
      add_changed_statement(chunk, statement_number)
    end

    -- Resolve a chunk and a statement number to a statement.
    local function get_statement(chunk, statement_number)
      local segment = chunk.segment
      assert(statement_number >= chunk.statement_range:start())
      assert(statement_number <= chunk.statement_range:stop())
      local statement = segment.statements[statement_number]
      assert(statement ~= nil)
      return statement
    end

    -- Iterate over the changed statements until convergence.
    local inner_loop_number = 1
    while #changed_statements_list > 0 do
      -- Guard against long (infinite?) loops.
      if inner_loop_number > max_reaching_definition_inner_loops then
        error(
          string.format(
            "Reaching definitions took more than %d inner loops, try increasing the `max_reaching_definition_inner_loops` Lua option",
            max_reaching_definition_inner_loops
          )
        )
      end

      -- Pick a statement from the stack of changed statements.
      local chunk, statement_number = pop_changed_statement()
      local results = states[chunk.segment.location.file_number].results  -- luacheck: ignore results

      -- Determine source statements from incoming edges.
      --
      -- Note: Some of these statements may be pseudo-statements from after a chunk. This would be a problem if we needed
      -- actual statements to be there but for the purpose of the reaching definitions algorithm, we don't really care.
      local incoming_edge_confidences_chunks_and_statement_numbers = {}
      if statement_number - 1 >= chunk.statement_range:start() then
        -- Consider implicit edges from previous statements within a chunk.
        --
        -- TODO: Add a MAYBE edge from conditional functions with only a T- or an F-type argument, not both.
        if lacks_implicit_out_edges[chunk] == nil or lacks_implicit_out_edges[chunk][statement_number - 1] == nil then
          table.insert(
            incoming_edge_confidences_chunks_and_statement_numbers,
            {DEFINITELY, chunk, statement_number - 1}
          )
        end
      end
      --if statement_number == 1 and chunk.segment == results.parts[1] then
      --  -- Consider implicit edges from pseudo-statements after parts of all files in the file group to the first part
      --  -- of the current file.
      --  --
      --  -- TODO: Revert commit 6b55ef8.
      --  -- TODO: Only consider implicit edges from pseudo-statements after the last top-level statements of all files in
      --  -- the current file group to the first top-level statement of the current file.
      --  for other_file_number, state in ipairs(states) do
      --    if other_file_number == chunk.segment.location.file_number then
      --      goto next_file
      --    end
      --    for _, part_segment in ipairs(state.results.parts or {}) do
      --      if part_segment.chunks == nil or #part_segment.chunks == 0 then
      --        goto next_part
      --      end
      --      local part_chunk = part_segment.chunks[1]
      --      table.insert(
      --        incoming_edge_confidences_chunks_and_statement_numbers,
      --        {MAYBE, part_chunk, part_chunk.statement_range:stop() + 1}
      --      )
      --      ::next_part::
      --    end
      --    ::next_file::
      --  end
      --end
      if in_edge_index[chunk] ~= nil and in_edge_index[chunk][statement_number] ~= nil then
        -- Consider explicit incoming edges.
        for _, edge in ipairs(in_edge_index[chunk][statement_number]) do
          table.insert(
            incoming_edge_confidences_chunks_and_statement_numbers,
            {edge.confidence, edge.from.chunk, edge.from.statement_number}
          )
        end
      end

      -- Determine the reaching definitions from before the current statement.
      --
      -- TODO: Special-case reaching definitions from T- and F-branches of conditional functions thus: If reaching definitions
      -- for the same statement comes from both T- and F-branches, disregard the edge confidences and record only a single reaching
      -- definition for the statement with a confidence that corresponds to the minimum confidence of both definitions.
      -- After this change, function definitions from before a conditional function call should reach the (pseudo)-statements after
      -- the call with confidence `DEFINITELY` rather than just `MAYBE`, as they do now.
      local incoming_definition_list, incoming_definition_confidence_list = {}, {}
      for _, incoming_edge_confidence_chunk_and_statement_number in ipairs(incoming_edge_confidences_chunks_and_statement_numbers) do
        local incoming_edge_confidence, incoming_chunk, incoming_statement_number
          = table.unpack(incoming_edge_confidence_chunk_and_statement_number)
        if reaching_definition_lists[incoming_chunk] ~= nil and
            reaching_definition_lists[incoming_chunk][incoming_statement_number] ~= nil then
          local reaching_definition_list = reaching_definition_lists[incoming_chunk][incoming_statement_number]
          local reaching_definition_confidence_list = reaching_definition_confidence_lists[incoming_chunk][incoming_statement_number]
          for definition_number, incoming_definition in ipairs(reaching_definition_list) do
            local incoming_definition_confidence = reaching_definition_confidence_list[definition_number]
            local incoming_confidence = math.min(incoming_edge_confidence, incoming_definition_confidence)
            table.insert(incoming_definition_list, incoming_definition)
            table.insert(incoming_definition_confidence_list, incoming_confidence)
          end
        end
      end

      -- Determine the definitions from the current statement.
      local current_definition_list, current_definition_confidence_list = {}, {}
      local invalidated_statement_index, invalidated_statement_list = {}, {}
      if statement_number <= chunk.statement_range:stop() then  -- Unless this is a pseudo-statement after a chunk.
        local statement = get_statement(chunk, statement_number)
        if (statement.type == FUNCTION_DEFINITION or statement.type == FUNCTION_VARIANT_DEFINITION) and is_well_behaved(statement) then
          local definition = {
            defined_csname = statement.defined_csname,
            statement_number = statement_number,
            chunk = chunk,
          }
          table.insert(current_definition_list, definition)
          table.insert(current_definition_confidence_list, statement.confidence)
          -- Invalidate definitions of the same control sequence names from before the current statement.
          if statement.defined_csname.type == TEXT then
            for _, incoming_definition in ipairs(incoming_definition_list) do
              local incoming_statement = get_statement(incoming_definition.chunk, incoming_definition.statement_number)
              if incoming_statement.confidence == DEFINITELY and
                  incoming_statement.defined_csname.payload == statement.defined_csname.payload and
                  incoming_statement ~= statement then
                if invalidated_statement_index[incoming_statement] == nil then
                  table.insert(invalidated_statement_list, incoming_statement)
                end
                invalidated_statement_index[incoming_statement] = true
              end
            end
          end
        end
      end

      -- Determine the reaching definitions after the current statement.
      local updated_reaching_definition_list, updated_reaching_definition_confidence_list = {}, {}
      local updated_reaching_definition_index, updated_reaching_definition_confidence_index = {}, {}
      local current_reaching_statement_index = {}
      for _, definition_and_definition_confidence_list in ipairs({
            {incoming_definition_list, incoming_definition_confidence_list},
            {current_definition_list, current_definition_confidence_list},
          }) do
        local definition_list, definition_confidence_list = table.unpack(definition_and_definition_confidence_list)
        for definition_number, definition in ipairs(definition_list) do
          local definition_confidence = definition_confidence_list[definition_number]
          local statement = get_statement(definition.chunk, definition.statement_number)
          assert(is_well_behaved(statement))
          local defined_csname = definition.defined_csname.payload
          if invalidated_statement_index[statement] ~= nil then
            goto next_definition
          end
          if current_reaching_statement_index[statement] == nil then
            table.insert(updated_reaching_definition_list, definition)
            table.insert(updated_reaching_definition_confidence_list, definition_confidence)
            assert(#updated_reaching_definition_list == #updated_reaching_definition_confidence_list)
            -- Also index the reaching definitions by defined control sequence names.
            if updated_reaching_definition_index[defined_csname] == nil then
              assert(updated_reaching_definition_confidence_index[defined_csname] == nil)
              updated_reaching_definition_index[defined_csname] = {}
              updated_reaching_definition_confidence_index[defined_csname] = {}
            end
            table.insert(updated_reaching_definition_index[defined_csname], definition)
            table.insert(updated_reaching_definition_confidence_index[defined_csname], definition_confidence)
            assert(#updated_reaching_definition_index[defined_csname] == #updated_reaching_definition_confidence_index[defined_csname])
            current_reaching_statement_index[statement] = {
              #updated_reaching_definition_list,
              #updated_reaching_definition_index[defined_csname],
            }
          else
            -- For repeated definitions, record the maximum confidence.
            local other_definition_list_number, other_definition_index_number = table.unpack(current_reaching_statement_index[statement])
            local other_definition_confidence = updated_reaching_definition_confidence_list[other_definition_list_number]
            local combined_confidence = math.max(definition_confidence, other_definition_confidence)
            updated_reaching_definition_confidence_list[other_definition_list_number] = combined_confidence
            updated_reaching_definition_confidence_index[defined_csname][other_definition_index_number] = combined_confidence
          end
          ::next_definition::
        end
      end

      -- Determine whether the reaching definitions after the current statement have changed.
      local function have_reaching_definitions_changed()
        -- Determine the previous set of definitions, if any.
        if reaching_definition_lists[chunk] == nil then
          return true
        end
        if reaching_definition_lists[chunk][statement_number] == nil then
          return true
        end
        local previous_reaching_definition_list = reaching_definition_lists[chunk][statement_number]
        assert(previous_reaching_definition_list ~= nil)
        assert(#previous_reaching_definition_list <= #updated_reaching_definition_list)

        -- Quickly check using set cardinalities.
        if #previous_reaching_definition_list ~= #updated_reaching_definition_list then
          return true
        end

        -- We don't need to compare the updated definitions with the previous definitions, since we only ever add new definitions.
        -- Therefore, the cardinality check is enough.

        -- TODO: Also check whether the definition confidences have changed. While this should affect correctness, check the number
        -- of iterations of the reaching definitions algo with and without checking. The number of iterations should increase with
        -- checking.

        return false
      end

      -- Update the stack of changed statements.
      if have_reaching_definitions_changed() then
        -- Determine destination statements of outgoing edges.
        --
        -- Note: Some of these statements may be pseudo-statements from after a chunk. This would be a problem if we needed
        -- actual statements to be there but for the purpose of the reaching definitions algorithm, we don't really care.
        local outgoing_chunks_and_statement_numbers = {}
        if statement_number <= chunk.statement_range:stop() then
          -- Consider implicit edges to following statements within a chunk and pseudo-statements after a chunk.
          --
          -- TODO: Add a MAYBE edge from conditional functions with only a T- or an F-type argument, not both.
          if lacks_implicit_out_edges[chunk] == nil or lacks_implicit_out_edges[chunk][statement_number] == nil then
            table.insert(outgoing_chunks_and_statement_numbers, {chunk, statement_number + 1})
          end
        end
        --if statement_number == chunk.statement_range:stop() + 1 and chunk.segment.type == PART then
        --  -- Consider implicit edges from pseudo-statements after a part of the current file to the first parts of all other
        --  -- files in the file group.
        --  --
        --  -- TODO: Revert commit 6b55ef8.
        --  -- TODO: Only consider implicit edges from pseudo-statements after the last top-level statement of the current file
        --  -- to the first top-level statements of all other files in the current file group.
        --  for other_file_number, state in ipairs(states) do
        --    if other_file_number == chunk.segment.location.file_number then
        --      goto next_file
        --    end
        --    if state.results.parts == nil then
        --      goto next_file
        --    end
        --    local first_part_segment = state.results.parts[1]
        --    if first_part_segment.chunks == nil or #first_part_segment.chunks == 0 then
        --      goto next_file
        --    end
        --    local first_part_chunk = first_part_segment.chunks[1]
        --    table.insert(outgoing_chunks_and_statement_numbers, {first_part_chunk, first_part_chunk.statement_range:start()})
        --    ::next_file::
        --  end
        --end
        if out_edge_index[chunk] ~= nil and out_edge_index[chunk][statement_number] ~= nil then
          -- Consider explicit outgoing edges.
          for _, edge in ipairs(out_edge_index[chunk][statement_number]) do
             table.insert(outgoing_chunks_and_statement_numbers, {edge.to.chunk, edge.to.statement_number})
          end
        end

        -- Insert the successive statements into the stack of changed statements.
        for _, outgoing_chunk_and_statement_number in ipairs(outgoing_chunks_and_statement_numbers) do
          local outgoing_chunk, outgoing_statement_number = table.unpack(outgoing_chunk_and_statement_number)
          add_changed_statement(outgoing_chunk, outgoing_statement_number)
        end
      end

      -- Update the reaching definitions.
      if reaching_definition_lists[chunk] == nil then
        assert(reaching_definition_indexes[chunk] == nil)
        assert(reaching_definition_confidence_lists[chunk] == nil)
        assert(reaching_definition_confidence_indexes[chunk] == nil)
        reaching_definition_lists[chunk] = {}
        reaching_definition_indexes[chunk] = {}
        reaching_definition_confidence_lists[chunk] = {}
        reaching_definition_confidence_indexes[chunk] = {}
      end
      if reaching_definition_lists[chunk][statement_number] == nil then
        assert(reaching_definition_indexes[chunk][statement_number] == nil)
        assert(reaching_definition_confidence_lists[chunk][statement_number] == nil)
        assert(reaching_definition_confidence_indexes[chunk][statement_number] == nil)
        reaching_definition_lists[chunk][statement_number] = {}
        reaching_definition_indexes[chunk][statement_number] = {}
        reaching_definition_confidence_lists[chunk][statement_number] = {}
        reaching_definition_confidence_indexes[chunk][statement_number] = {}
      end
      reaching_definition_lists[chunk][statement_number] = updated_reaching_definition_list
      reaching_definition_indexes[chunk][statement_number] = updated_reaching_definition_index
      reaching_definition_confidence_lists[chunk][statement_number] = updated_reaching_definition_confidence_list
      reaching_definition_confidence_indexes[chunk][statement_number] = updated_reaching_definition_confidence_index

      inner_loop_number = inner_loop_number + 1
    end

    -- Record the numbers of inner loops in a file.
  --
  -- TODO: Revert commit 1a6f825.
    local inner_loop_numbers_file = assert(io.open("/tmp/inner-loop-numbers.txt", "a"))
    assert(
      inner_loop_numbers_file:write(
        string.format(
          "%d %s\n",
          inner_loop_number - 1,
          table.concat(pathname_group, ', ')
        )
      )
    )
    assert(inner_loop_numbers_file:close())

    -- Make a copy of the current estimation of the function call edges.
    previous_function_call_edges = {}
    for _, edge in ipairs(current_function_call_edges) do
      table.insert(previous_function_call_edges, edge)
    end

    -- Update the current estimation of the function call edges.
    current_function_call_edges = {}
    for _, function_call_chunk_and_statement_number in ipairs(function_call_list) do
      -- For each function call, first copy relevant reaching definitions to a temporary list.
      local function_call_chunk, function_call_statement_number = table.unpack(function_call_chunk_and_statement_number)
      if reaching_definition_indexes[function_call_chunk] == nil or
          reaching_definition_indexes[function_call_chunk][function_call_statement_number] == nil then
        goto next_function_call
      end
      local function_call_statement = get_statement(function_call_chunk, function_call_statement_number)
      assert(is_well_behaved(function_call_statement))
      local reaching_function_and_variant_definition_list, reaching_function_and_variant_definition_confidence_list = {}, {}
      local reaching_definition_index = reaching_definition_indexes[function_call_chunk][function_call_statement_number]
      local reaching_definition_confidence_index
        = reaching_definition_confidence_indexes[function_call_chunk][function_call_statement_number]
      local used_csname = function_call_statement.used_csname.payload
      for definition_number, definition in ipairs(reaching_definition_index[used_csname] or {}) do
        assert(definition.defined_csname.payload == used_csname)
        table.insert(reaching_function_and_variant_definition_list, definition)
        local definition_confidence = reaching_definition_confidence_index[used_csname][definition_number]
        table.insert(reaching_function_and_variant_definition_confidence_list, definition_confidence)
      end

      -- Then, resolve all function variant calls to the originating function definitions.
      local reaching_definition_number, seen_reaching_statements = 1, {}
      local reaching_function_definition_list, reaching_function_definition_confidence_list = {}, {}
      while reaching_definition_number <= #reaching_function_and_variant_definition_list do
        local definition = reaching_function_and_variant_definition_list[reaching_definition_number]
        local definition_confidence = reaching_function_and_variant_definition_confidence_list[reaching_definition_number]
        local chunk, statement_number = definition.chunk, definition.statement_number
        local statement = get_statement(chunk, statement_number)
        assert(is_well_behaved(statement))
        -- Detect any loops within the graph.
        if seen_reaching_statements[statement] ~= nil then
          goto next_reaching_statement
        end
        if statement.type == FUNCTION_DEFINITION then
          -- Simply record the function definitions.
          table.insert(reaching_function_definition_list, definition)
          table.insert(reaching_function_definition_confidence_list, definition_confidence)
          assert(#reaching_function_definition_list == #reaching_function_definition_confidence_list)
        elseif statement.type == FUNCTION_VARIANT_DEFINITION then
          -- Resolve the function variant definitions.
          if reaching_definition_lists[chunk] ~= nil and reaching_definition_lists[chunk][statement_number] ~= nil then
            local other_reaching_definition_index = reaching_definition_indexes[chunk][statement_number]
            local other_reaching_definition_confidence_index = reaching_definition_confidence_indexes[chunk][statement_number]
            local base_csname = statement.base_csname.payload
            for other_definition_number, other_definition in ipairs(other_reaching_definition_index[base_csname] or {}) do
              local other_definition_confidence = other_reaching_definition_confidence_index[base_csname][other_definition_number]
              local other_chunk, other_statement_number = other_definition.chunk, other_definition.statement_number
              local other_statement = get_statement(other_chunk, other_statement_number)
              assert(is_well_behaved(other_statement))
              assert(other_definition.defined_csname.payload == base_csname)
              table.insert(reaching_function_and_variant_definition_list, other_definition)
              local combined_confidence = math.min(definition_confidence, other_definition_confidence)
              table.insert(reaching_function_and_variant_definition_confidence_list, combined_confidence)
              assert(#reaching_function_and_variant_definition_list, reaching_function_and_variant_definition_confidence_list)
            end
          end
        else
          error('Unexpected statement type "' .. statement.type .. '"')
        end
        ::next_reaching_statement::
        seen_reaching_statements[statement] = true
        reaching_definition_number = reaching_definition_number + 1
      end

      -- Draw the function call edges.
      for function_definition_number, function_definition in ipairs(reaching_function_definition_list) do
        local function_definition_statement = get_statement(function_definition.chunk, function_definition.statement_number)
        assert(is_well_behaved(function_definition_statement))

        -- Determine the segment of the function definition replacement text.
        local results = states[function_definition.chunk.segment.location.file_number].results
        local to_segment_number = function_definition_statement.replacement_text_argument.segment_number
        if to_segment_number == nil then
          goto next_function_definition
        end
        local to_segment = results.segments[to_segment_number]
        if to_segment.chunks == nil or #to_segment.chunks == 0 then
          goto next_function_definition
        end

        -- Determine the edge confidence.
        --
        -- TODO: Use the same confidence for the backward edge instead of always using MAYBE. Rationale: We must not confuse
        -- multiplicity of potential call sites with confidence: A function defined during a function call will _always_ propagate
        -- to _all_ call sites if the calls themselves have the confidence DEFINITELY, regardless of how many there are.
        -- TODO: Also update <https://witiko.github.io/Expl3-Linter-11.5/>, which also makes this mistake.
        local forward_edge_confidence
        if #reaching_function_definition_list > 1 then
          -- If there are multiple definitions for this function call, then it's uncertain which one will be used.
          forward_edge_confidence = MAYBE
        else
          -- Otherwise, use the minimum of the function definition statement confidence and the edge confidences along
          -- the maximum-confidence path from the function definition statement to the function call statement.
          forward_edge_confidence = reaching_function_definition_confidence_list[function_definition_number]
        end

        -- Draw the edges.
        local forward_to_chunk = to_segment.chunks[1]
        local forward_to_statement_number = forward_to_chunk.statement_range:start()
        local forward_edge = {
          type = FUNCTION_CALL,
          from = {
            chunk = function_call_chunk,
            statement_number = function_call_statement_number,
          },
          to = {
            chunk = forward_to_chunk,
            statement_number = forward_to_statement_number,
          },
          confidence = forward_edge_confidence,
        }
        table.insert(current_function_call_edges, forward_edge)
        local backward_from_chunk = to_segment.chunks[#to_segment.chunks]
        local backward_from_statement_number = forward_to_chunk.statement_range:stop() + 1
        local backward_edge = {
          type = FUNCTION_CALL_RETURN,
          from = {
            chunk = backward_from_chunk,
            statement_number = backward_from_statement_number,
          },
          to = {
            chunk = function_call_chunk,
            statement_number = function_call_statement_number + 1,
          },
          confidence = MAYBE,
        }
        table.insert(current_function_call_edges, backward_edge)
        ::next_function_definition::
      end
      ::next_function_call::
    end

    outer_loop_number = outer_loop_number + 1
  until not any_edges_changed(previous_function_call_edges, current_function_call_edges)

  -- Record the numbers of outer loops in a file.
  --
  -- TODO: Revert commit 1a6f825.
  local outer_loop_numbers_file = assert(io.open("/tmp/outer-loop-numbers.txt", "a"))
  assert(
    outer_loop_numbers_file:write(
      string.format(
        "%d %s\n",
        outer_loop_number - 1,
        table.concat(pathname_group, ', ')
      )
    )
  )
  assert(outer_loop_numbers_file:close())

  -- Record edges.
  for _, edge in ipairs(current_function_call_edges) do
    local results = states[edge.from.chunk.segment.location.file_number].results
    if results.edges == nil then
      results.edges = {}
    end
    if results.edges[DYNAMIC] == nil then
      results.edges[DYNAMIC] = {}
    end
    table.insert(results.edges[DYNAMIC], edge)
  end
end

local substeps = {
  collect_chunks,
  draw_static_edges,
  draw_dynamic_edges,
}

return {
  edge_types = edge_types,
  is_confused = is_confused,
  name = "flow analysis",
  substeps = substeps,
}
