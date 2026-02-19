-- The flow analysis step of static analysis determines additional emergent properties of the code.
--
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")
local make_shallow_copy = require("explcheck-utils").make_shallow_copy

local format_csname = lexical_analysis.format_csname
local get_token_range_to_byte_range = lexical_analysis.get_token_range_to_byte_range

local segment_types = syntactic_analysis.segment_types
local segment_subtypes = syntactic_analysis.segment_subtypes
local get_call_range_to_token_range = syntactic_analysis.get_call_range_to_token_range

local csname_types = semantic_analysis.csname_types
local statement_types = semantic_analysis.statement_types
local statement_subtypes = semantic_analysis.statement_subtypes

local TF_TYPE_ARGUMENTS = segment_types.TF_TYPE_ARGUMENTS

local T_TYPE_ARGUMENTS = segment_subtypes.TF_TYPE_ARGUMENTS.T_TYPE_ARGUMENTS
local F_TYPE_ARGUMENTS = segment_subtypes.TF_TYPE_ARGUMENTS.F_TYPE_ARGUMENTS

local TEXT = csname_types.TEXT

local FUNCTION_CALL = statement_types.FUNCTION_CALL
local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_UNDEFINITION = statement_types.FUNCTION_UNDEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION

local FUNCTION_DEFINITION_DIRECT = statement_subtypes.FUNCTION_DEFINITION.DIRECT
local FUNCTION_DEFINITION_INDIRECT = statement_subtypes.FUNCTION_DEFINITION.INDIRECT

local OTHER_TOKENS = statement_types.OTHER_TOKENS
local OTHER_TOKENS_COMPLEX = statement_subtypes.OTHER_TOKENS.COMPLEX

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
  NEXT_INTERESTING_STATEMENT = "pair of successive interesting statements",  -- Only used internally in `draw_dynamic_edges()`.
  NEXT_FILE = "potential insertion of another file from the current file group",
  TF_BRANCH = TF_BRANCH,
  TF_BRANCH_RETURN = string.format("return from %s", TF_BRANCH),
  FUNCTION_CALL = FUNCTION_CALL,
  FUNCTION_CALL_RETURN = string.format("%s return", FUNCTION_CALL),
}

local NEXT_CHUNK = edge_types.NEXT_CHUNK
local NEXT_INTERESTING_STATEMENT = edge_types.NEXT_INTERESTING_STATEMENT
local NEXT_FILE = edge_types.NEXT_FILE
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

-- Check whether a file reached the flow analysis.
local function _file_reached_flow_analysis(states, file_number)
  return states[file_number].results.edges ~= nil
end

-- Resolve a chunk and a statement number to a statement.
local function _get_statement(chunk, statement_number)
  local segment = chunk.segment
  assert(statement_number >= chunk.statement_range:start())
  assert(statement_number <= chunk.statement_range:stop())
  local statement = segment.statements[statement_number]
  assert(statement ~= nil)
  return statement
end

-- Get a text representation of a statement or a pseudo-statement "after" a chunk.
local function format_statement(chunk, statement_number)  ---@diagnostic disable-line:unused-function
  local statement_text
  if statement_number == chunk.statement_range:stop() + 1 then
    statement_text = string.format("pseudo-statement #%d after a chunk", statement_number)
  else
    local statement = _get_statement(chunk, statement_number)
    statement_text = string.format("statement #%d (%s) in a chunk", statement_number, statement.subtype or statement.type)
  end
  local segment_text = string.format(
    'from segment "%s" at depth %d', chunk.segment.subtype or chunk.segment.type, chunk.segment.nesting_depth)
  return string.format("%s %s", statement_text, segment_text)
end

-- Get a text representation of an edge.
---@diagnostic disable-next-line:unused-function, unused-local
local function format_edge(edge)  -- luacheck: ignore
  return string.format(
    "%96s  -- %20s (confidence: %3.0f%%) -->  %s",
    format_statement(edge.from.chunk, edge.from.statement_number),
    edge.subtype or edge.type,
    edge.confidence * 100,
    format_statement(edge.to.chunk, edge.to.statement_number)
  )
end

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
---@diagnostic disable-next-line:unused-local
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
        if statement.type == OTHER_TOKENS and statement.subtype == OTHER_TOKENS_COMPLEX then
          record_chunk(statement_number, EXCLUSIVE)
        elseif first_statement_number == nil then
          first_statement_number = statement_number
        end
      end
      record_chunk(#segment.statements, INCLUSIVE)
    end
  end
end

-- Draw "static" edges between chunks withing a single file. A static edge is known without extra analysis.
---@diagnostic disable-next-line:unused-local
local function draw_file_local_static_edges(states, file_number, options)  -- luacheck: ignore options
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
  for _, part in ipairs(results.parts or {}) do
    if #part.chunks > 0 then
      results.last_part_with_chunks = part
      if previous_part == nil then
        results.first_part_with_chunks = part
      else
        local from_chunk = previous_part.chunks[#previous_part.chunks]
        local from_statement_number = from_chunk.statement_range:stop() + 1
        local to_chunk = part.chunks[1]
        local to_statement_number = to_chunk.statement_range:start()
        -- Determine whether the parts are immediately adjacent.
        local previous_outer_range = results.outer_expl_ranges[previous_part.location.part_number]
        local outer_range = results.outer_expl_ranges[part.location.part_number]
        assert(previous_outer_range:stop() < outer_range:start())
        local are_adjacent = previous_outer_range:stop() + 1 == outer_range:start()
        local edge_confidence = are_adjacent and DEFINITELY or MAYBE
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
          confidence = edge_confidence,
        }
        table.insert(results.edges[STATIC], edge)
      end
      previous_part = part
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
                local branch_edge_to_chunk = to_segment.chunks[1]
                local branch_edge_to_statement_number = branch_edge_to_chunk.statement_range:start()
                local branch_edge = {
                  type = TF_BRANCH,
                  from = {
                    chunk = from_chunk,
                    statement_number = from_statement_number,
                  },
                  to = {
                    chunk = branch_edge_to_chunk,
                    statement_number = branch_edge_to_statement_number,
                  },
                  confidence = DEFINITELY,
                  -- The following attribute is specific to the type.
                  subtype = edge_subtype,
                }
                local return_edge_from_chunk = to_segment.chunks[#to_segment.chunks]
                local return_edge_from_statement_number = branch_edge_to_chunk.statement_range:stop() + 1
                local return_edge = {
                  type = TF_BRANCH_RETURN,
                  from = {
                    chunk = return_edge_from_chunk,
                    statement_number = return_edge_from_statement_number,
                  },
                  to = {
                    chunk = from_chunk,
                    statement_number = from_statement_number + 1,
                  },
                  confidence = DEFINITELY,
                  -- The following attribute is specific to the type.
                  subtype = edge_subtype,
                }
                -- The following attributes are specific to the type.
                branch_edge.return_edge = return_edge
                return_edge.branch_edge = branch_edge
                table.insert(results.edges[STATIC], branch_edge)
                table.insert(results.edges[STATIC], return_edge)
              end
            end
          end
        end
      end
    end
  end
end

-- Draw "static" edges between chunks between all files in a file group. A static edge is known without extra analysis.
---@diagnostic disable-next-line:unused-local
local function draw_group_wide_static_edges(states, _, options)  -- luacheck: ignore options
  -- Draw static edges once between all files in the file group, not just individual files.
  if states.drew_static_edges ~= nil then
    return
  end
  states.drew_static_edges = true

  -- Check whether a file in the current group reached the flow analysis.
  local function file_reached_flow_analysis(file_number)
    return _file_reached_flow_analysis(states, file_number)
  end

  -- Record edges from potentially inputting a file from the file group after every other file from the file group.
  for file_number, state in ipairs(states) do
    if not file_reached_flow_analysis(file_number) then
      goto next_file
    end
    if state.results.last_part_with_chunks == nil then
      goto next_file
    end
    local from_segment = state.results.last_part_with_chunks
    local from_chunk = from_segment.chunks[#from_segment.chunks]
    assert(from_chunk ~= nil)
    local from_statement_number = from_chunk.statement_range:stop() + 1
    for other_file_number, other_state in ipairs(states) do
      if not file_reached_flow_analysis(other_file_number) then
        goto next_other_file
      end
      if file_number == other_file_number then
        goto next_other_file
      end
      if other_state.results.first_part_with_chunks == nil then
        goto next_other_file
      end
      local to_segment = other_state.results.first_part_with_chunks
      local to_chunk = to_segment.chunks[1]
      assert(to_chunk ~= nil)
      local to_statement_number = to_chunk.statement_range:start()
      local edge = {
        type = NEXT_FILE,
        from = {
          chunk = from_chunk,
          statement_number = from_statement_number,
        },
        to = {
          chunk = to_chunk,
          statement_number = to_statement_number,
        },
        confidence = MAYBE,
      }
      table.insert(state.results.edges[STATIC], edge)
      ::next_other_file::
    end
    ::next_file::
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

-- Index an edge in an edge index.
local function _index_edge(states, edge_index, index_key, edge)
  assert(_file_reached_flow_analysis(states, edge.from.chunk.segment.location.file_number))
  assert(_file_reached_flow_analysis(states, edge.to.chunk.segment.location.file_number))
  local chunk, statement_number = edge[index_key].chunk, edge[index_key].statement_number
  if edge_index[chunk] == nil then
    edge_index[chunk] = {}
  end
  if edge_index[chunk][statement_number] == nil then
    edge_index[chunk][statement_number] = {}
  end
  table.insert(edge_index[chunk][statement_number], edge)
end

-- Check whether a function (variant) definition or a function call statement is "well-behaved".
-- A statement is well-behaved when we know its control sequence names precisely and not just as a probabilistic pattern.
local function is_well_behaved(statement)
  local result
  if statement.type == FUNCTION_CALL then
    result = statement.used_csname.type == TEXT
  elseif statement.type == FUNCTION_DEFINITION then
    result = statement.defined_csname.type == TEXT
  elseif statement.type == FUNCTION_UNDEFINITION then
    result = statement.undefined_csname.type == TEXT
  elseif statement.type == FUNCTION_VARIANT_DEFINITION then
    result = statement.base_csname.type == TEXT or statement.defined_csname.type == TEXT
  else
    error('Unexpected statement type "' .. statement.type .. '"')
  end
  return result
end

-- Draw "dynamic" edges between chunks between all files in a file group. A dynamic edge requires estimation.
local function draw_group_wide_dynamic_edges(states, _, options)
  -- Draw dynamic edges once between all files in the file group, not just individual files.
  if states.drew_dynamic_edges ~= nil then
    return
  end
  states.drew_dynamic_edges = true

  -- Check whether a file in the current group reached the flow analysis.
  local function file_reached_flow_analysis(file_number)
    return _file_reached_flow_analysis(states, file_number)
  end

  -- Index an edge in an edge index.
  local function index_edge(edge_index, index_key, edge)
    return _index_edge(states, edge_index, index_key, edge)
  end

  -- Resolve a chunk and a statement number to a statement.
  local function get_statement(chunk, statement_number)
    assert(file_reached_flow_analysis(chunk.segment.location.file_number))
    return _get_statement(chunk, statement_number)
  end

  -- Collect a list of well-behaved function definition and call statements.
  local function_call_list, function_definition_list = {}, {}
  for file_number, state in ipairs(states) do
    -- Skip statements from files in the current file group that haven't reached the flow analysis.
    if not file_reached_flow_analysis(file_number) then
      goto next_file
    end
    for _, segment in ipairs(state.results.segments or {}) do
      for _, chunk in ipairs(segment.chunks or {}) do
        for statement_number, statement in chunk.statement_range:enumerate(segment.statements) do
          if statement.type ~= FUNCTION_CALL and
              statement.type ~= FUNCTION_DEFINITION then
            goto next_statement
          end
          if not is_well_behaved(statement) then
            goto next_statement
          end
          if statement.type == FUNCTION_CALL then
            table.insert(function_call_list, {chunk, statement_number})
          elseif statement.type == FUNCTION_DEFINITION then
            table.insert(function_definition_list, {chunk, statement_number})
          else
            error('Unexpected statement type "' .. statement.type .. '"')
          end
          ::next_statement::
        end
      end
    end
    ::next_file::
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
    --
    -- First of, we will track the reaching definitions themselves.
    local reaching_definition_lists, reaching_definition_indexes = {}, {}

    -- Index all explicit "static" and currently estimated "dynamic" incoming and outgoing edges for each statement.
    local explicit_in_edge_index, explicit_out_edge_index = {}, {}
    local edge_lists = {current_function_call_edges}
    for _, state in ipairs(states) do
      local edge_category_list = {}
      for edge_category, _ in pairs(state.results.edges or {}) do
        table.insert(edge_category_list, edge_category)
      end
      table.sort(edge_category_list)
      for _, edge_category in ipairs(edge_category_list) do
        local edges = state.results.edges[edge_category]
        assert(edges ~= nil)
        table.insert(edge_lists, edges)
      end
    end
    for _, edges in ipairs(edge_lists) do
      for _, edge in ipairs(edges) do
        index_edge(explicit_in_edge_index, 'to', edge)
        index_edge(explicit_out_edge_index, 'from', edge)
      end
    end

    -- Check whether a statement is "interesting". A statement is interesting if it has the potential to consume or affect
    -- the reaching definitions other than just passing along the definitions from the previous statement in the chunk.
    local function is_interesting(chunk, statement_number)
      -- Chunk boundaries are interesting.
      if statement_number == chunk.statement_range:start() or statement_number == chunk.statement_range:stop() + 1 then
        return true
      end
      -- (Pseudo-)statements with incoming or outgoing explicit edges are interesting.
      if explicit_in_edge_index[chunk] ~= nil and explicit_in_edge_index[chunk][statement_number] ~= nil
          or explicit_out_edge_index[chunk] ~= nil and explicit_out_edge_index[chunk][statement_number] ~= nil then
        return true
      end
      -- Well-behaved statements are interesting.
      local statement = get_statement(chunk, statement_number)
      if (
            statement.type == FUNCTION_CALL or
            statement.type == FUNCTION_DEFINITION or
            statement.type == FUNCTION_UNDEFINITION or
            statement.type == FUNCTION_VARIANT_DEFINITION
          )
          and is_well_behaved(statement) then
        return true
      end
      return false
    end

    -- Index all implicit incoming and outgoing pseudo-edges as well.
    local implicit_in_edge_index, implicit_out_edge_index = {}, {}
    for file_number, state in ipairs(states) do
      -- Skip statements from files in the current file group that haven't reached the flow analysis.
      if not file_reached_flow_analysis(file_number) then
        goto next_file
      end
      for _, segment in ipairs(state.results.segments or {}) do
        for _, chunk in ipairs(segment.chunks or {}) do
          local previous_interesting_statement_number
          local edge_confidence = DEFINITELY

          -- Add an implicit pseudo-edge between pairs of successive interesting statements.
          local function record_interesting_statement(statement_number)
            assert(is_interesting(chunk, statement_number))
            if previous_interesting_statement_number ~= nil then
              local edge = {
                type = NEXT_INTERESTING_STATEMENT,
                from = {
                  chunk = chunk,
                  statement_number = previous_interesting_statement_number,
                },
                to = {
                  chunk = chunk,
                  statement_number = statement_number,
                },
                confidence = edge_confidence,
              }
              index_edge(implicit_in_edge_index, 'to', edge)
              index_edge(implicit_out_edge_index, 'from', edge)
            end
            previous_interesting_statement_number = statement_number
            edge_confidence = DEFINITELY
          end

          for statement_number, statement in chunk.statement_range:enumerate(segment.statements) do
            if is_interesting(chunk, statement_number) then
              record_interesting_statement(statement_number)

              -- For potential function calls, reduce the confidence of the implicit pseudo-edge towards the next interesting
              -- statement, since we'll maybe not take that pseudo-edge and make the function call instead.
              if statement.type == FUNCTION_CALL then
                edge_confidence = MAYBE
                goto next_statement
              end

              local has_t_branch, has_f_branch = false, false
              if explicit_out_edge_index[chunk] ~= nil and explicit_out_edge_index[chunk][statement_number] ~= nil then
                for _, edge in ipairs(explicit_out_edge_index[chunk][statement_number]) do
                  -- For fully-resolved function calls, cancel the implicit pseudo-edge towards the next interesting statement;
                  -- instead, the reaching definitions will be routed through the replacement text of the function, at whose end
                  -- we'll return to the (interesting) statement following the function call.
                  if edge.type == FUNCTION_CALL and edge.confidence == DEFINITELY then
                    previous_interesting_statement_number = nil
                    goto next_statement
                  end
                  -- For outgoing T- and F-branches of conditional functions, the behavior depends on whether both branches
                  -- are present. If the conditional function has a function call edge, we use the previously described behavior.
                  if edge.type == TF_BRANCH then
                    if edge.subtype == T_BRANCH then
                      has_t_branch = true
                    else
                      assert(edge.subtype == F_BRANCH)
                      has_f_branch = true
                    end
                  end
                end
                -- If the conditional function has no function call edge and has both a T- and an F-branch, cancel the implicit
                -- pseudo-edge towards the next interesting statement; instead, the reaching definitions will be routed through
                -- the branches, at whose end we'll return to the (interesting) statement following the conditional function call.
                if has_t_branch and has_f_branch then
                  previous_interesting_statement_number = nil
                end
              end
            end
            ::next_statement::
          end
          record_interesting_statement(chunk.statement_range:stop() + 1)
        end
      end
      ::next_file::
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

      -- Collect reaching definitions from the incoming edges.
      local incoming_edge_list = {}
      for _, in_edge_index in ipairs({explicit_in_edge_index, implicit_in_edge_index}) do
        if in_edge_index[chunk] ~= nil and in_edge_index[chunk][statement_number] ~= nil then
          for _, edge in ipairs(in_edge_index[chunk][statement_number]) do
            table.insert(incoming_edge_list, edge)
          end
        end
      end

      -- Determine the reaching definitions from before the current statement.
      local incoming_definition_list = {}
      do
        local original_incoming_definition_list, original_incoming_definition_index = {}, {}
        local original_incoming_definition_edge_confidence_lists = {}
        local in_degree = 0
        for _, in_edge_index in ipairs({explicit_in_edge_index, implicit_in_edge_index}) do
          if in_edge_index[chunk] ~= nil and in_edge_index[chunk][statement_number] ~= nil then
            for _, edge in ipairs(in_edge_index[chunk][statement_number]) do
              if reaching_definition_lists[edge.from.chunk] ~= nil and
                  reaching_definition_lists[edge.from.chunk][edge.from.statement_number] ~= nil then
                in_degree = in_degree + 1
                local reaching_definition_list = reaching_definition_lists[edge.from.chunk][edge.from.statement_number]
                for _, definition in ipairs(reaching_definition_list) do
                  -- Record the different incoming definitions together with the corresponding edge confidences.
                  if original_incoming_definition_index[definition] == nil then
                    assert(original_incoming_definition_edge_confidence_lists[definition] == nil)
                    table.insert(original_incoming_definition_list, definition)
                    original_incoming_definition_index[definition] = #original_incoming_definition_list
                    table.insert(original_incoming_definition_edge_confidence_lists, {})
                    assert(#original_incoming_definition_edge_confidence_lists == #original_incoming_definition_list)
                  end
                  local definition_number = original_incoming_definition_index[definition]
                  table.insert(original_incoming_definition_edge_confidence_lists[definition_number], edge.confidence)
                end
              end
            end
          end
        end
        for definition_number, definition in ipairs(original_incoming_definition_list) do
          local definition_edge_confidence_list = original_incoming_definition_edge_confidence_lists[definition_number]

          -- Determine the weakened confidence of a definition.
          local combined_edge_confidence
          if #definition_edge_confidence_list == in_degree then
            -- If a definition reaches all the incoming edges, use the maximum over the edge confidences as the combined edge
            -- confidence.
            combined_edge_confidence = math.max(table.unpack(definition_edge_confidence_list))
          else
            -- Otherwise, always use the combined edge confidence of `MAYBE`, regardless of the actual edge confidences.
            combined_edge_confidence = MAYBE
          end
          assert(combined_edge_confidence >= MAYBE, "Edges shouldn't have confidences less than MAYBE")
          -- Weaken the definition confidence with the combined edge confidence.
          local updated_definition
          if combined_edge_confidence < definition.confidence then
            updated_definition = make_shallow_copy(definition)
            updated_definition.weakened_confidence = combined_edge_confidence
          else
            updated_definition = definition
          end
          table.insert(incoming_definition_list, updated_definition)
        end
      end

      -- Determine the definitions and undefinitions from the current statement.
      local current_definition_list = {}
      local invalidated_statement_index, invalidated_statement_list = {}, {}
      if statement_number <= chunk.statement_range:stop() then  -- Unless this is a pseudo-statement "after" a chunk.
        local statement = get_statement(chunk, statement_number)
        if statement.type ~= FUNCTION_DEFINITION and
            statement.type ~= FUNCTION_UNDEFINITION and
            statement.type ~= FUNCTION_VARIANT_DEFINITION then
          goto next_statement
        end
        if not is_well_behaved(statement) then
          goto next_statement
        end
        local defined_or_undefined_csname
        if statement.type == FUNCTION_DEFINITION or statement.type == FUNCTION_VARIANT_DEFINITION then
          -- Record function and function variant definitions.
          assert(statement.defined_csname.type == TEXT)
          defined_or_undefined_csname = statement.defined_csname.payload
          local definition = {
            csname = statement.defined_csname.payload,
            confidence = statement.confidence,
            statement_number = statement_number,
            chunk = chunk,
          }
          assert(definition.confidence >= MAYBE, "Function definitions shouldn't have confidences less than MAYBE")
          table.insert(current_definition_list, definition)
        elseif statement.type == FUNCTION_UNDEFINITION then
          defined_or_undefined_csname = statement.undefined_csname.payload
        else
          error('Unexpected statement type "' .. statement.type .. '"')
        end
        if statement.confidence == DEFINITELY then
          -- Invalidate definitions of the same control sequence names from before the current statement.
          for _, incoming_definition in ipairs(incoming_definition_list) do
            local incoming_statement = get_statement(incoming_definition.chunk, incoming_definition.statement_number)
            if incoming_statement.defined_csname.payload == defined_or_undefined_csname and
                incoming_statement ~= statement then
              if invalidated_statement_index[incoming_statement] == nil then
                table.insert(invalidated_statement_list, incoming_statement)
              end
              invalidated_statement_index[incoming_statement] = true
            end
          end
        end
        ::next_statement::
      end

      -- Determine the reaching definitions after the current statement.
      local updated_definition_list, updated_definition_index = {}, {}
      local current_reaching_statement_index = {}
      for _, definition_list in ipairs({incoming_definition_list, current_definition_list}) do
        for _, definition in ipairs(definition_list) do
          local statement = get_statement(definition.chunk, definition.statement_number)
          assert(is_well_behaved(statement))
          -- Skip invalidated definitions.
          if invalidated_statement_index[statement] ~= nil then
            goto next_definition
          end
          -- Record the first occurrence of a definition.
          if current_reaching_statement_index[statement] == nil then
            table.insert(updated_definition_list, definition)
            -- Also index the reaching definitions by defined control sequence names.
            if updated_definition_index[definition.csname] == nil then
              updated_definition_index[definition.csname] = {}
            end
            table.insert(updated_definition_index[definition.csname], definition)
            current_reaching_statement_index[statement] = {
              #updated_definition_list,
              #updated_definition_index[definition.csname],
            }
          -- For repeated occurrences of a definition, keep the ones with the highest confidence.
          else
            local other_definition_list_number, other_definition_index_number = table.unpack(current_reaching_statement_index[statement])
            -- If the current occurrence has a higher confidence, replace the previous occurrence with it.
            local other_definition = updated_definition_list[other_definition_list_number]
            if definition.confidence > other_definition.confidence then
              updated_definition_list[other_definition_list_number] = definition
              updated_definition_index[definition.csname][other_definition_index_number] = definition
            end
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
        local previous_definition_list = reaching_definition_lists[chunk][statement_number]
        assert(previous_definition_list ~= nil)
        assert(#previous_definition_list <= #updated_definition_list)

        -- Quickly check for inequality using set cardinalities.
        if #previous_definition_list ~= #updated_definition_list then
          return true
        end

        -- Check that the definitions and their confidences are the same.
        for _, previous_definition in ipairs(previous_definition_list) do
          local statement = get_statement(previous_definition.chunk, previous_definition.statement_number)
          if current_reaching_statement_index[statement] == nil then
            return true
          end
          local updated_definition_list_number, _ = table.unpack(current_reaching_statement_index[statement])
          local updated_definition = updated_definition_list[updated_definition_list_number]
          if previous_definition.confidence ~= updated_definition.confidence then
            return true
          end
        end

        return false
      end

      -- Update the stack of changed statements.
      if have_reaching_definitions_changed() then
        -- Insert the successive statements into the stack of changed statements.
        for _, out_edge_index in ipairs({explicit_out_edge_index, implicit_out_edge_index}) do
          if out_edge_index[chunk] ~= nil and out_edge_index[chunk][statement_number] ~= nil then
            for _, edge in ipairs(out_edge_index[chunk][statement_number]) do
              add_changed_statement(edge.to.chunk, edge.to.statement_number)
            end
          end
        end

        -- Update the reaching definitions.
        if reaching_definition_lists[chunk] == nil then
          assert(reaching_definition_indexes[chunk] == nil)
          reaching_definition_lists[chunk] = {}
          reaching_definition_indexes[chunk] = {}
        end
        if reaching_definition_lists[chunk][statement_number] == nil then
          assert(reaching_definition_indexes[chunk][statement_number] == nil)
          reaching_definition_lists[chunk][statement_number] = {}
          reaching_definition_indexes[chunk][statement_number] = {}
        end
        reaching_definition_lists[chunk][statement_number] = updated_definition_list
        reaching_definition_indexes[chunk][statement_number] = updated_definition_index
      end

      inner_loop_number = inner_loop_number + 1
    end

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
      local reaching_function_and_variant_definition_list = {}
      local reaching_definition_index = reaching_definition_indexes[function_call_chunk][function_call_statement_number]
      local used_csname = function_call_statement.used_csname.payload
      for _, definition in ipairs(reaching_definition_index[used_csname] or {}) do
        assert(definition.csname == used_csname)
        table.insert(reaching_function_and_variant_definition_list, definition)
      end

      -- Then, resolve all function variant calls to the originating function definitions.
      local reaching_definition_number, seen_reaching_statements = 1, {}
      local reaching_function_definition_list = {}
      while reaching_definition_number <= #reaching_function_and_variant_definition_list do
        local definition = reaching_function_and_variant_definition_list[reaching_definition_number]
        local chunk, statement_number = definition.chunk, definition.statement_number
        local statement = get_statement(chunk, statement_number)
        assert(is_well_behaved(statement))
        -- Detect any loops within the graph.
        if seen_reaching_statements[statement] ~= nil then
          goto next_reaching_statement
        end
        if statement.type == FUNCTION_DEFINITION and statement.subtype == FUNCTION_DEFINITION_DIRECT then
          -- Simply record the direct function definitions.
          table.insert(reaching_function_definition_list, definition)
        elseif statement.type == FUNCTION_DEFINITION and statement.subtype == FUNCTION_DEFINITION_INDIRECT
            or statement.type == FUNCTION_VARIANT_DEFINITION then
          -- Resolve the indirect function definitions and function variant definitions.
          if reaching_definition_lists[chunk] ~= nil and reaching_definition_lists[chunk][statement_number] ~= nil then
            local other_reaching_definition_index = reaching_definition_indexes[chunk][statement_number]
            local base_csname = statement.base_csname.payload
            for _, other_definition in ipairs(other_reaching_definition_index[base_csname] or {}) do
              local other_chunk, other_statement_number = other_definition.chunk, other_definition.statement_number
              local other_statement = get_statement(other_chunk, other_statement_number)
              assert(is_well_behaved(other_statement))
              assert(other_definition.csname == base_csname)
              -- Weaken the base function definition confidence with the function variant definition confidence.
              local combined_definition
              if definition.confidence < other_definition.confidence then
                combined_definition = make_shallow_copy(other_definition)
                combined_definition.confidence = definition.confidence
              else
                combined_definition = other_definition
              end
              table.insert(reaching_function_and_variant_definition_list, combined_definition)
            end
          end
        else
          error('Unexpected statement type and "' .. statement.type .. '" and subtype "' .. statement.subtype .. '"')
        end
        ::next_reaching_statement::
        seen_reaching_statements[statement] = true
        reaching_definition_number = reaching_definition_number + 1
      end

      -- Draw the function call edges.
      for _, function_definition in ipairs(reaching_function_definition_list) do
        local function_definition_statement = get_statement(function_definition.chunk, function_definition.statement_number)
        assert(is_well_behaved(function_definition_statement))
        assert(function_definition_statement.subtype == FUNCTION_DEFINITION_DIRECT)
        assert(function_definition_statement.type == FUNCTION_DEFINITION)

        -- Determine the segment of the function definition replacement text.
        local results = states[function_definition.chunk.segment.location.file_number].results
        local to_segment_number = function_definition_statement.replacement_text_argument.segment_number
        if to_segment_number == nil then
          goto next_function_definition
        end
        local to_segment = results.segments[to_segment_number]

        -- Elide function calls with empty replacement texts.
        if to_segment.chunks == nil or #to_segment.chunks == 0 then
          goto next_function_definition
        end

        -- Determine the edge confidence.
        local edge_confidence
        if #reaching_function_definition_list > 1 then
          -- If there are multiple definitions for this function call, then it's uncertain which one will be used.
          edge_confidence = MAYBE
        else
          -- Otherwise, use the minimum of the function definition statement confidence and the edge confidences along
          -- the maximum-confidence path from the function definition statement to the function call statement.
          edge_confidence = function_definition.confidence
        end
        assert(edge_confidence >= MAYBE, "Function call edges shouldn't have confidences less than MAYBE")

        -- Draw the edges.
        local call_edge_to_chunk = to_segment.chunks[1]
        local call_edge_to_statement_number = call_edge_to_chunk.statement_range:start()
        local call_edge = {
          type = FUNCTION_CALL,
          from = {
            chunk = function_call_chunk,
            statement_number = function_call_statement_number,
          },
          to = {
            chunk = call_edge_to_chunk,
            statement_number = call_edge_to_statement_number,
          },
          confidence = edge_confidence,
        }
        local return_edge_from_chunk = to_segment.chunks[#to_segment.chunks]
        local return_edge_from_statement_number = return_edge_from_chunk.statement_range:stop() + 1
        local return_edge = {
          type = FUNCTION_CALL_RETURN,
          from = {
            chunk = return_edge_from_chunk,
            statement_number = return_edge_from_statement_number,
          },
          to = {
            chunk = function_call_chunk,
            statement_number = function_call_statement_number + 1,
          },
          confidence = edge_confidence,
        }
        -- The following attributes are specific to the edge types.
        call_edge.return_edge = return_edge
        return_edge.call_edge = call_edge
        table.insert(current_function_call_edges, call_edge)
        table.insert(current_function_call_edges, return_edge)
        ::next_function_definition::
      end
      ::next_function_call::
    end

    outer_loop_number = outer_loop_number + 1
  until not any_edges_changed(previous_function_call_edges, current_function_call_edges)

  -- Record edges.
  for _, edge in ipairs(current_function_call_edges) do
    local results = states[edge.from.chunk.segment.location.file_number].results
    assert(results.edges ~= nil)
    if results.edges[DYNAMIC] == nil then
      results.edges[DYNAMIC] = {}
    end
    table.insert(results.edges[DYNAMIC], edge)
  end
end

-- Report any issues.
local function report_issues(states, file_number, _)
  local state = states[file_number]

  local content = state.content
  local results = state.results
  assert(results.edges ~= nil)

  local issues = state.issues

  -- Index an edge in an edge index.
  local function index_edge(edge_index, index_key, edge)
    return _index_edge(states, edge_index, index_key, edge)
  end

  -- Collect a list of well-behaved function call statements.
  local function_call_list = {}
  for _, segment in ipairs(results.segments or {}) do
    for _, chunk in ipairs(segment.chunks or {}) do
      for statement_number, statement in chunk.statement_range:enumerate(segment.statements) do
        if statement.type ~= FUNCTION_CALL then
          goto next_statement
        end
        if not is_well_behaved(statement) then
          goto next_statement
        end
        if statement.type == FUNCTION_CALL then
          table.insert(function_call_list, {chunk, statement_number})
        else
          error('Unexpected statement type "' .. statement.type .. '"')
        end
        ::next_statement::
      end
    end
  end

  -- Collect a list of function call edges.
  local function_call_edge_index = {}
  for _, edge in ipairs(results.edges[DYNAMIC] or {}) do
    if edge.type == FUNCTION_CALL then
      index_edge(function_call_edge_index, 'from', edge)
    end
  end

  -- Get the byte range of a statement.
  local function statement_to_byte_range(chunk, statement_number)
    local segment = chunk.segment
    assert(segment.location.file_number == file_number)

    local part_number = segment.location.part_number

    local tokens = results.tokens[part_number]

    local call_range_to_token_range = get_call_range_to_token_range(chunk.segment.calls, #tokens)
    local token_range_to_byte_range = get_token_range_to_byte_range(tokens, #content)

    local statement = _get_statement(chunk, statement_number)

    local token_range = call_range_to_token_range(statement.call_range)
    local byte_range = token_range_to_byte_range(token_range)

    return byte_range
  end

  -- Report calling an undefined function.
  for _, chunk_and_statement_number in ipairs(function_call_list) do
    local chunk, statement_number = table.unpack(chunk_and_statement_number)
    if function_call_edge_index[chunk] == nil or function_call_edge_index[chunk][statement_number] == nil then
      local statement = _get_statement(chunk, statement_number)
      local byte_range = statement_to_byte_range(chunk, statement_number)
      local csname = statement.used_csname

      issues:add("e505", "calling an undefined function", byte_range, format_csname(csname.transcript))
    else
      assert(#function_call_edge_index[chunk][statement_number] > 0)
    end
  end
end

local substeps = {
  collect_chunks,
  draw_file_local_static_edges,
  draw_group_wide_static_edges,
  draw_group_wide_dynamic_edges,
  report_issues,
}

return {
  edge_types = edge_types,
  is_confused = is_confused,
  name = "flow analysis",
  substeps = substeps,
}
