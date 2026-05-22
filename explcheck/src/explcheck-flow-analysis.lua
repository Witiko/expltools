-- The flow analysis step of static analysis determines additional emergent properties of the code.
--
local get_option = require("explcheck-config").get_option
local ranges = require("explcheck-ranges")
local lexical_analysis = require("explcheck-lexical-analysis")
local syntactic_analysis = require("explcheck-syntactic-analysis")
local semantic_analysis = require("explcheck-semantic-analysis")
local make_shallow_copy = require("explcheck-utils").make_shallow_copy
local parsers = require("explcheck-parsers")

local format_csname = lexical_analysis.format_csname
local get_token_range_to_byte_range = lexical_analysis.get_token_range_to_byte_range

local segment_types = syntactic_analysis.segment_types
local segment_subtypes = syntactic_analysis.segment_subtypes
local get_call_range_to_token_range = syntactic_analysis.get_call_range_to_token_range

local name_types = semantic_analysis.name_types
local statement_types = semantic_analysis.statement_types
local statement_subtypes = semantic_analysis.statement_subtypes

local PART = segment_types.PART
local TF_TYPE_ARGUMENTS = segment_types.TF_TYPE_ARGUMENTS

local T_TYPE_ARGUMENTS = segment_subtypes.TF_TYPE_ARGUMENTS.T_TYPE_ARGUMENTS
local F_TYPE_ARGUMENTS = segment_subtypes.TF_TYPE_ARGUMENTS.F_TYPE_ARGUMENTS

local TEXT = name_types.TEXT

local FUNCTION_CALL = statement_types.FUNCTION_CALL
local FUNCTION_DEFINITION = statement_types.FUNCTION_DEFINITION
local FUNCTION_UNDEFINITION = statement_types.FUNCTION_UNDEFINITION
local FUNCTION_VARIANT_DEFINITION = statement_types.FUNCTION_VARIANT_DEFINITION

local VARIABLE_DECLARATION = statement_types.VARIABLE_DECLARATION
local VARIABLE_DEFINITION = statement_types.VARIABLE_DEFINITION
local VARIABLE_USE = statement_types.VARIABLE_USE

local FUNCTION_DEFINITION_DIRECT = statement_subtypes.FUNCTION_DEFINITION.DIRECT
local FUNCTION_DEFINITION_INDIRECT = statement_subtypes.FUNCTION_DEFINITION.INDIRECT
local VARIABLE_DEFINITION_DIRECT = statement_subtypes.VARIABLE_DEFINITION.DIRECT
local VARIABLE_DEFINITION_INDIRECT = statement_subtypes.VARIABLE_DEFINITION.INDIRECT

local OTHER_TOKENS = statement_types.OTHER_TOKENS
local OTHER_TOKENS_COMPLEX = statement_subtypes.OTHER_TOKENS.COMPLEX

local statement_confidences = semantic_analysis.statement_confidences

local MAYBE = statement_confidences.MAYBE
local DEFINITELY = statement_confidences.DEFINITELY

local new_range = ranges.new_range
local range_flags = ranges.range_flags

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE

local lpeg = require("lpeg")

local macro_statement_types = {
  FUNCTION_AND_VARIABLE_DEFINITIONS = "block of csname declarations and (un)definitions",
}

local FUNCTION_AND_VARIABLE_DEFINITIONS = macro_statement_types.FUNCTION_AND_VARIABLE_DEFINITIONS

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
  VARIABLE_USE = VARIABLE_USE,
  VARIABLE_USE_RETURN = string.format("%s return", VARIABLE_USE),
}

local NEXT_CHUNK = edge_types.NEXT_CHUNK
local NEXT_INTERESTING_STATEMENT = edge_types.NEXT_INTERESTING_STATEMENT
local NEXT_FILE = edge_types.NEXT_FILE
assert(TF_BRANCH == edge_types.TF_BRANCH)
local TF_BRANCH_RETURN = edge_types.TF_BRANCH_RETURN
assert(FUNCTION_CALL == edge_types.FUNCTION_CALL)
local FUNCTION_CALL_RETURN = edge_types.FUNCTION_CALL_RETURN
assert(VARIABLE_USE == edge_types.VARIABLE_USE)
local VARIABLE_USE_RETURN = edge_types.VARIABLE_USE_RETURN

local edge_subtypes = {
  TF_BRANCH = {
    T_BRANCH = "(return from) T-branch of conditional function",
    F_BRANCH = "(return from) F-branch of conditional function",
  },
}

local T_BRANCH = edge_subtypes.TF_BRANCH.T_BRANCH
local F_BRANCH = edge_subtypes.TF_BRANCH.F_BRANCH

local reaching_definition_types = {
  REACHING_DECLARATIONS = "variable/constant declarations",
  REACHING_DEFINITIONS = "function/variant/variable/constant definitions",
}

local REACHING_DECLARATIONS = reaching_definition_types.REACHING_DECLARATIONS
local REACHING_DEFINITIONS = reaching_definition_types.REACHING_DEFINITIONS

-- Merge selected statements into macro-statements, a more useful form for the following analyses.
-- In the following, we will refer to statements and macro-statements interchangeably.
local function merge_statements(states, file_number, _)
  local state = states[file_number]

  local results = state.results

  for _, segment in ipairs(results.segments or {}) do
    -- Skip segment types that only contain calls, not statements.
    if segment.statements == nil then
      goto next_segment
    end
    local macro_statements, previous_macro_statement = {}, nil
    for _, statement in ipairs(segment.statements) do
      if (
            statement.type == FUNCTION_DEFINITION or
            statement.type == FUNCTION_UNDEFINITION or
            statement.type == FUNCTION_VARIANT_DEFINITION or
            statement.type == VARIABLE_DECLARATION or
            statement.type == VARIABLE_DEFINITION
          ) then
        if previous_macro_statement == nil
            or previous_macro_statement.type ~= FUNCTION_AND_VARIABLE_DEFINITIONS then
          local macro_statement = {
            type = FUNCTION_AND_VARIABLE_DEFINITIONS,
            -- The following attributes are specific to the type.
            statements = {},
          }
          table.insert(macro_statements, macro_statement)
          previous_macro_statement = macro_statement
        end
        table.insert(previous_macro_statement.statements, statement)
      else
        table.insert(macro_statements, statement)
        previous_macro_statement = statement
      end
    end
    assert(#macro_statements <= #segment.statements)
    segment.macro_statements = macro_statements
    ::next_segment::
  end
end

-- Determine whether a statement is a macro-statement or not.
local function is_macro_statement(statement)
  if statement.statements ~= nil then
    assert(statement.call_range == nil)
    return true
  else
    assert(statement.call_range ~= nil)
    return false
  end
end

-- Resolve a chunk, a macro-statement number, and optionally a statement number to a (macro-)statement.
local function _get_statement(chunk, macro_statement_number, statement_number)
  local segment = chunk.segment
  assert(macro_statement_number >= chunk.statement_range:start())
  assert(macro_statement_number <= chunk.statement_range:stop())
  local macro_statement = segment.macro_statements[macro_statement_number]
  assert(macro_statement ~= nil)
  if statement_number == nil then
    return macro_statement
  else
    assert(is_macro_statement(macro_statement))
    assert(statement_number <= #macro_statement.statements)
    local statement = macro_statement.statements[statement_number]
    return statement
  end
end

-- Resolve a chunk and a statement number to a statement, with extra invariants checked.
local function get_statement(states, chunk, macro_statement_number, statement_number)
  assert(not states[chunk.segment.location.file_number].results.stopped_early)
  return _get_statement(chunk, macro_statement_number, statement_number)
end

-- Get a text representation of a statement or a pseudo-statement "after" a chunk.
---@diagnostic disable-next-line:unused-function
local function format_statement(chunk, macro_statement_number, statement_number)
  local statement_text
  if macro_statement_number == chunk.statement_range:stop() + 1 then
    statement_text = string.format(
      "pseudo-statement #%d after a chunk",
      macro_statement_number
    )
  else
    local statement = _get_statement(chunk, macro_statement_number, statement_number)
    if statement_number == nil then
      statement_text = string.format(
        "statement #%d (%s) in a chunk",
        macro_statement_number,
        statement.subtype or statement.type
      )
    else
      statement_text = string.format(
        "statement #%d/#%d (%s) in a chunk",
        macro_statement_number,
        statement_number,
        statement.subtype or statement.type
      )
    end
  end
  local segment_text = string.format(
    'from segment "%s" at depth %d',
    chunk.segment.subtype or chunk.segment.type,
    chunk.segment.nesting_depth
  )
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
local function collect_chunks(states, file_number, _)
  local state = states[file_number]

  local results = state.results

  for _, segment in ipairs(results.segments or {}) do
    -- Skip segment types that only contain calls, not statements.
    if segment.macro_statements == nil then
      goto next_segment
    end

    segment.chunks = {}
    local first_statement_number

    -- Record a chunk with a given range of known statements.
    local function record_chunk(last_statement_number, flags)
      if first_statement_number ~= nil then
        local chunk = {
          segment = segment,
          statement_range = new_range(first_statement_number, last_statement_number, flags, #segment.macro_statements),
        }
        table.insert(segment.chunks, chunk)
        first_statement_number = nil
      end
    end

    for statement_number, statement in ipairs(segment.macro_statements) do
      if statement.type == OTHER_TOKENS and statement.subtype == OTHER_TOKENS_COMPLEX then
        record_chunk(statement_number, EXCLUSIVE)
      elseif first_statement_number == nil then
        first_statement_number = statement_number
      end
    end
    record_chunk(#segment.macro_statements, INCLUSIVE)

    ::next_segment::
  end
end

-- Draw "static" edges between chunks withing a single file. A static edge is known without extra analysis.
local function draw_file_local_static_edges(states, file_number, _)
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
  for _, part in ipairs(results.segment_type_index and results.segment_type_index[PART] or {}) do
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
      for from_statement_number, from_statement in from_chunk.statement_range:enumerate(from_segment.macro_statements) do
        if is_macro_statement(from_statement) then
          -- Avoid edges between statements within a macro-statement, so that we can map macro-statements to vertices of
          -- the flow graph in the following analyses and ignore the nested statements.
          goto next_statement
        end
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
                table.insert(results.edges[STATIC], branch_edge)
                table.insert(results.edges[STATIC], return_edge)
              end
            end
          end
        end
        ::next_statement::
      end
    end
  end
end

-- Draw "static" edges between chunks between all files in a file group. A static edge is known without extra analysis.
local function draw_group_wide_static_edges(states, _, _)
  -- Draw static edges once between all files in the file group, not just individual files.
  if states.results.drew_static_edges ~= nil then
    return
  end
  states.results.drew_static_edges = true

  -- Record edges from potentially inputting a file from the file group after every other file from the file group.
  for file_number, state in ipairs(states) do
    if state.results.stopped_early then
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
      if other_state.results.stopped_early then
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
local function __index_edge(reaching_definition_type, states, edge_index_name, index_key, edge)
  assert(not states[edge.from.chunk.segment.location.file_number].results.stopped_early)
  assert(not states[edge.to.chunk.segment.location.file_number].results.stopped_early)
  local edge_index = states.results.edge_indexes[reaching_definition_type][edge_index_name]
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
    result = statement.defined_csname.type == TEXT and (statement.maybe_used or statement.maybe_multiply_defined)
  elseif statement.type == FUNCTION_UNDEFINITION then
    result = statement.undefined_csname.type == TEXT and (statement.maybe_used or statement.maybe_multiply_defined)
  elseif statement.type == FUNCTION_VARIANT_DEFINITION then
    result = statement.defined_csname.type == TEXT and (statement.maybe_used or statement.maybe_multiply_defined)
  elseif statement.type == VARIABLE_DECLARATION then
    result = statement.declared_csname.type == TEXT and (statement.maybe_multiply_declared or statement.maybe_used)
  elseif statement.type == VARIABLE_DEFINITION then
    result = statement.defined_csname.type == TEXT and statement.maybe_used
  elseif statement.type == VARIABLE_USE then
    result = statement.used_csname.type == TEXT
  else
    error('Unexpected statement type "' .. statement.type .. '"')
  end
  return result
end

-- Check whether a statement is "interesting". A statement is interesting if it has the potential to consume or affect
-- the reaching definitions other than just passing along the definitions from the previous statement in the chunk.
local function _is_interesting(reaching_definition_type, states, chunk, macro_statement_number)
  -- Chunk boundaries are interesting.
  if macro_statement_number == chunk.statement_range:start() or macro_statement_number == chunk.statement_range:stop() + 1 then
    return true
  end
  -- (Pseudo-)statements with incoming or outgoing explicit edges are interesting.
  local edge_indexes = states.results.edge_indexes[reaching_definition_type]
  if edge_indexes.explicit_in[chunk] ~= nil and edge_indexes.explicit_in[chunk][macro_statement_number] ~= nil or
      edge_indexes.explicit_out[chunk] ~= nil and edge_indexes.explicit_out[chunk][macro_statement_number] ~= nil then
    return true
  end
  -- Well-behaved statements are interesting.
  local macro_statement = get_statement(states, chunk, macro_statement_number)
  if reaching_definition_type == REACHING_DEFINITIONS
      and (macro_statement.type == FUNCTION_CALL or macro_statement.type == VARIABLE_USE)
      and is_well_behaved(macro_statement) then
    return true
  end
  -- Macro-statements containing at least one interesting statement are interesting.
  local any_well_behaved_statements = false
  for _, statement in ipairs(macro_statement.statements or {macro_statement}) do
    assert(not is_macro_statement(statement))
    if reaching_definition_type == REACHING_DECLARATIONS then
      if (
            statement.type == VARIABLE_DECLARATION or
            statement.type == VARIABLE_DEFINITION or
            statement.type == FUNCTION_UNDEFINITION
          ) and is_well_behaved(statement) then
        any_well_behaved_statements = true
        goto skip_remaining_statements
      end
    elseif reaching_definition_type == REACHING_DEFINITIONS then
      if (
            statement.type == FUNCTION_DEFINITION or
            statement.type == FUNCTION_UNDEFINITION or
            statement.type == FUNCTION_VARIANT_DEFINITION or
            statement.type == VARIABLE_DEFINITION
          ) and is_well_behaved(statement) then
        any_well_behaved_statements = true
        goto skip_remaining_statements
      end
    else
      error('Unexpected reaching definition type "' .. reaching_definition_type .. '"')
    end
  end
  ::skip_remaining_statements::
  if any_well_behaved_statements then
    return true
  end
  return false
end

-- Determine the reaching definitions from before the current statement.
local function get_incoming_reaching_definitions(reaching_definition_type, states, chunk, macro_statement_number)
  local reaching_definitions = states.results.reaching_definitions[reaching_definition_type]
  local incoming_definition_list, incoming_definition_index = {}, {}
  do
    local original_incoming_definition_list, original_incoming_definition_index = {}, {}
    local original_incoming_definition_edge_confidence_lists = {}
    local in_degree = 0
    local edge_indexes = states.results.edge_indexes[reaching_definition_type]
    for _, in_edge_index in ipairs({edge_indexes.explicit_in, edge_indexes.implicit_in}) do
      if in_edge_index[chunk] ~= nil and in_edge_index[chunk][macro_statement_number] ~= nil then
        for _, edge in ipairs(in_edge_index[chunk][macro_statement_number]) do
          if reaching_definitions.lists[edge.from.chunk] ~= nil and
              reaching_definitions.lists[edge.from.chunk][edge.from.statement_number] ~= nil then
            in_degree = in_degree + 1
            local reaching_definition_list = reaching_definitions.lists[edge.from.chunk][edge.from.statement_number]
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
      assert(combined_edge_confidence >= MAYBE)
      -- Weaken the definition confidence with the combined edge confidence.
      local updated_definition
      if combined_edge_confidence < definition.confidence then
        updated_definition = make_shallow_copy(definition)
        updated_definition.confidence = combined_edge_confidence
      else
        updated_definition = definition
      end
      table.insert(incoming_definition_list, updated_definition)
      if incoming_definition_index[updated_definition.csname] == nil then
        incoming_definition_index[updated_definition.csname] = {}
      end
      table.insert(incoming_definition_index[updated_definition.csname], #incoming_definition_list)
    end
  end
  return incoming_definition_list, incoming_definition_index
end

-- Determine the declarations and definitions from the current statement.
local function get_current_reaching(
  reaching_definition_type,
  states,
  chunk,
  macro_statement_number,
  incoming_definition_list,
  incoming_definition_index,
  max_statement_number
)
  local current_definition_list, current_definition_index = {}, {}
  local invalidated_statement_index = {}
  if macro_statement_number <= chunk.statement_range:stop() then  -- Unless this is a pseudo-statement "after" a chunk.
    local macro_statement = get_statement(states, chunk, macro_statement_number)
    if macro_statement.type ~= FUNCTION_AND_VARIABLE_DEFINITIONS then
      goto next_macro_statement
    end
    for statement_number, statement in ipairs(macro_statement.statements or {macro_statement}) do
      assert(not is_macro_statement(statement))
      if max_statement_number ~= nil and statement_number > max_statement_number then
        break
      end
      if reaching_definition_type == REACHING_DECLARATIONS then
        if statement.type ~= VARIABLE_DECLARATION and
            statement.type ~= FUNCTION_UNDEFINITION then
          goto next_statement
        end
      elseif reaching_definition_type == REACHING_DEFINITIONS then
        if statement.type ~= FUNCTION_DEFINITION and
            statement.type ~= FUNCTION_UNDEFINITION and
            statement.type ~= FUNCTION_VARIANT_DEFINITION and
            statement.type ~= VARIABLE_DEFINITION then
          goto next_statement
        end
      else
        error('Unexpected reaching definition type "' .. reaching_definition_type .. '"')
      end
      if not is_well_behaved(statement) then
        goto next_statement
      end
      local declared_defined_or_undefined_csname
      if statement.type == FUNCTION_DEFINITION
        or statement.type == FUNCTION_VARIANT_DEFINITION
        or statement.type == VARIABLE_DECLARATION
        or statement.type == VARIABLE_DEFINITION
      then
        -- Record function, function variant, and constant/variable declarations/definitions.
        if statement.type == VARIABLE_DECLARATION then
          assert(reaching_definition_type == REACHING_DECLARATIONS)
          declared_defined_or_undefined_csname = statement.declared_csname
        else
          assert(reaching_definition_type == REACHING_DEFINITIONS)
          declared_defined_or_undefined_csname = statement.defined_csname
        end
        assert(declared_defined_or_undefined_csname.type == TEXT)
        local definition = {
          csname = declared_defined_or_undefined_csname.payload,
          confidence = statement.confidence,
          chunk = chunk,
          macro_statement_number = macro_statement_number,
          statement_number = is_macro_statement(macro_statement) and statement_number or nil,
        }
        assert(definition.confidence >= MAYBE)
        table.insert(current_definition_list, definition)
        if current_definition_index[definition.csname] == nil then
          current_definition_index[definition.csname] = {}
        end
        table.insert(current_definition_index[definition.csname], #current_definition_list)
      elseif statement.type == FUNCTION_UNDEFINITION then
        declared_defined_or_undefined_csname = statement.undefined_csname
      else
        error('Unexpected statement type "' .. statement.type .. '"')
      end
      if statement.confidence == DEFINITELY then
        -- Invalidate definitions of the same control sequence names from before the current statement.
        for _, definition_list_and_index in ipairs({
              {incoming_definition_list, incoming_definition_index},
              {current_definition_list, current_definition_index},
            }) do
          local definition_list, definition_index = table.unpack(definition_list_and_index)
          for _, incoming_definition_number in ipairs(definition_index[declared_defined_or_undefined_csname.payload] or {}) do
            local incoming_definition = definition_list[incoming_definition_number]
            assert(incoming_definition.csname == declared_defined_or_undefined_csname.payload)
            local incoming_statement = get_statement(
              states,
              incoming_definition.chunk,
              incoming_definition.macro_statement_number,
              incoming_definition.statement_number
            )
            local incoming_declared_or_defined_csname
            if incoming_statement.type == VARIABLE_DECLARATION then
              incoming_declared_or_defined_csname = incoming_statement.declared_csname
            else
              incoming_declared_or_defined_csname = incoming_statement.defined_csname
            end
            assert(incoming_declared_or_defined_csname.type == TEXT)
            assert(incoming_declared_or_defined_csname.payload == declared_defined_or_undefined_csname.payload)
            if incoming_statement ~= statement and not invalidated_statement_index[incoming_statement] then
              invalidated_statement_index[incoming_statement] = true
            end
          end
        end
      end
      -- If we previously invalidated a definition that originates from the current statement but reached us from before the
      -- current statement due to a cycle in the flow-graph, undo the invalidation.
      invalidated_statement_index[statement] = false
      ::next_statement::
    end
    ::next_macro_statement::
  end
  return current_definition_list, current_definition_index, invalidated_statement_index
end

-- Determine the reaching definitions after the current statement.
local function get_outgoing_reaching_definitions(states, incoming_definition_list, current_definition_list, invalidated_statement_index)
  local updated_definition_list, updated_definition_index = {}, {}
  local current_reaching_statement_index = {}
  for _, definition_list in ipairs({incoming_definition_list, current_definition_list}) do
    for _, definition in ipairs(definition_list) do
      local statement = get_statement(states, definition.chunk, definition.macro_statement_number, definition.statement_number)
      assert(is_well_behaved(statement))
      -- Skip invalidated definitions.
      if invalidated_statement_index[statement] then
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
  return updated_definition_list, updated_definition_index, current_reaching_statement_index
end

-- Determine whether the reaching definitions after the current statement have changed.
local function have_reaching_changed(
  reaching_definition_type,
  states,
  chunk,
  statement_number,
  updated_definition_list,
  current_reaching_statement_index
)
  local reaching_definitions = states.results.reaching_definitions[reaching_definition_type]

  -- Determine the previous set of definitions, if any.
  if reaching_definitions.lists[chunk] == nil then
    return true
  end
  if reaching_definitions.lists[chunk][statement_number] == nil then
    return true
  end
  local previous_definition_list = reaching_definitions.lists[chunk][statement_number]
  assert(previous_definition_list ~= nil)
  assert(#previous_definition_list <= #updated_definition_list)

  -- Quickly check for inequality using set cardinalities.
  if #previous_definition_list ~= #updated_definition_list then
    return true
  end

  -- Check that the definitions and their confidences are the same.
  for _, previous_definition in ipairs(previous_definition_list) do
    local statement = get_statement(
      states,
      previous_definition.chunk,
      previous_definition.macro_statement_number,
      previous_definition.statement_number
    )
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

-- Draw "dynamic" edges between chunks between all files in a file group. A dynamic edge requires estimation.
local function draw_group_wide_dynamic_edges(states, _, options)
  -- Draw dynamic edges once between all files in the file group, not just individual files.
  if states.results.drew_dynamic_edges ~= nil then
    return
  end
  states.results.drew_dynamic_edges = true

  -- Index an edge in an edge index.
  local function _index_edge(reaching_definition_type, edge_index_name, index_key, edge)
    return __index_edge(reaching_definition_type, states, edge_index_name, index_key, edge)
  end

  -- Collect a list of well-behaved csname definitions/uses and variable declarations.
  local function_call_list, csname_definition_list, variable_declaration_list, variable_use_list = {}, {}, {}, {}
  for _, state in ipairs(states) do
    -- Skip statements from files in the current file group that haven't reached the flow analysis.
    if states.results.stopped_early then
      goto next_file
    end
    for _, segment in ipairs(state.results.segments or {}) do
      for _, chunk in ipairs(segment.chunks or {}) do
        for statement_number, macro_statement in chunk.statement_range:enumerate(segment.macro_statements) do
          if macro_statement.type == FUNCTION_CALL and is_well_behaved(macro_statement) then
            table.insert(function_call_list, {chunk, statement_number})
          elseif macro_statement.type == VARIABLE_USE and is_well_behaved(macro_statement) then
            table.insert(variable_use_list, {chunk, statement_number})
          elseif macro_statement.type == FUNCTION_AND_VARIABLE_DEFINITIONS then
            local any_well_behaved_csname_definitions, any_well_behaved_variable_declarations = false, false
            for _, statement in ipairs(macro_statement.statements) do
              if not is_well_behaved(statement) then
                goto next_statement
              end
              if statement.type == FUNCTION_DEFINITION or
                  statement.type == VARIABLE_DEFINITION or
                  statement.type == FUNCTION_VARIANT_DEFINITION then
                any_well_behaved_csname_definitions = true
              elseif statement.type == VARIABLE_DECLARATION then
                any_well_behaved_variable_declarations = true
              end
              if any_well_behaved_csname_definitions and any_well_behaved_variable_declarations then
                goto skip_remaining_statements
              end
              ::next_statement::
            end
            ::skip_remaining_statements::
            if any_well_behaved_csname_definitions then
              table.insert(csname_definition_list, {chunk, statement_number})
            end
            if any_well_behaved_variable_declarations then
              table.insert(variable_declaration_list, {chunk, statement_number})
            end
          end
        end
      end
    end
    ::next_file::
  end

  -- Run reaching definitions multiple types for different definition types.
  local reaching_definition_type_list = {}
  for _, reaching_definition_type in pairs(reaching_definition_types) do
    table.insert(reaching_definition_type_list, reaching_definition_type)
  end
  table.sort(reaching_definition_type_list)

  -- Determine edges from function calls and variable uses to function/variable definitions, as discussed in
  -- <https://witiko.github.io/Expl3-Linter-11.5/>.
  local previous_function_call_edges, previous_variable_use_edges
  local current_function_call_edges, current_variable_use_edges = {}, {}
  local max_inner_loops = get_option('max_reaching_definition_inner_loops', options)
  local max_outer_loops = get_option('max_reaching_definition_outer_loops', options)
  local num_outer_loops, max_theoretical_outer_loops = 0, #function_call_list + #variable_use_list
  repeat
    -- Guard against infinite loops.
    assert(num_outer_loops <= max_theoretical_outer_loops)

    -- Guard against too many loops, making the processing unbearably slow.
    if max_outer_loops ~= false and num_outer_loops > max_outer_loops then
      break
    end

    -- Run reaching definitions, see <https://en.wikipedia.org/wiki/Reaching_definition#Worklist_algorithm>.
    states.results.reaching_definitions, states.results.edge_indexes = {}, {}
    for _, reaching_definition_type in ipairs(reaching_definition_type_list) do
      -- First of, we will track the reaching definitions themselves.
      states.results.reaching_definitions[reaching_definition_type] = {
        lists = {},
        indexes = {},
      }
      local reaching_definitions = states.results.reaching_definitions[reaching_definition_type]

      -- Index an edge in an edge index.
      local function index_edge(edge_index_name, index_key, edge)
        return _index_edge(reaching_definition_type, edge_index_name, index_key, edge)
      end

      -- Index all explicit "static" and currently estimated "dynamic" incoming and outgoing edges for each statement.
      states.results.edge_indexes[reaching_definition_type] = {}
      local edge_indexes = states.results.edge_indexes[reaching_definition_type]
      edge_indexes.explicit_in, edge_indexes.explicit_out = {}, {}
      local edge_lists = {current_function_call_edges, current_variable_use_edges}
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
          index_edge('explicit_in', 'to', edge)
          index_edge('explicit_out', 'from', edge)
        end
      end

      -- Check whether a statement is "interesting". A statement is interesting if it has the potential to consume or affect
      -- the reaching definitions other than just passing along the definitions from the previous statement in the chunk.
      local function is_interesting(chunk, macro_statement_number)
        return _is_interesting(reaching_definition_type, states, chunk, macro_statement_number)
      end

      -- Index all implicit incoming and outgoing pseudo-edges as well.
      edge_indexes.implicit_in, edge_indexes.implicit_out = {}, {}
      local num_interesting_statements, interesting_statement_index = 0, {}
      for _, state in ipairs(states) do
        -- Skip statements from files in the current file group that haven't reached the flow analysis.
        if state.results.stopped_early then
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
                index_edge('implicit_in', 'to', edge)
                index_edge('implicit_out', 'from', edge)
              end
              if interesting_statement_index[chunk] == nil then
                interesting_statement_index[chunk] = {}
              end
              if interesting_statement_index[chunk][statement_number] == nil then
                interesting_statement_index[chunk][statement_number] = true
                num_interesting_statements = num_interesting_statements + 1
              end
              previous_interesting_statement_number = statement_number
              edge_confidence = DEFINITELY
            end

            for statement_number, statement in chunk.statement_range:enumerate(segment.macro_statements) do
              if is_interesting(chunk, statement_number) then
                record_interesting_statement(statement_number)

                -- For potential function calls, reduce the confidence of the implicit pseudo-edge towards the next interesting
                -- statement, since we'll maybe not take that pseudo-edge and make the function call instead.
                if statement.type == FUNCTION_CALL then
                  edge_confidence = MAYBE
                  goto next_statement
                end

                local has_t_branch, has_f_branch = false, false
                if edge_indexes.explicit_out[chunk] ~= nil and edge_indexes.explicit_out[chunk][statement_number] ~= nil then
                  for _, edge in ipairs(edge_indexes.explicit_out[chunk][statement_number]) do
                    -- For fully-resolved function calls and variable uses, cancel the implicit pseudo-edge towards the next
                    -- interesting statement; instead, the reaching definitions will be routed through the replacement/definition text
                    -- of the function/variable, at whose end we'll return to the (interesting) statement following the function call.
                    if (edge.type == FUNCTION_CALL or edge.type == VARIABLE_USE) and edge.confidence == DEFINITELY then
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
      interesting_statement_index = nil

      -- Initialize a stack of changed statements to all well-behaved function (variant) definitions.
      local changed_statements_list, changed_statements_index = {}, {}

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

      -- Record the initial changed statements based on the current type of reaching definitions.
      local initial_changed_statements
      if reaching_definition_type == REACHING_DEFINITIONS then
        initial_changed_statements = csname_definition_list
      elseif reaching_definition_type == REACHING_DECLARATIONS then
        initial_changed_statements = variable_declaration_list
      else
        error('Unexpected reaching definition type "' .. reaching_definition_type .. '"')
      end
      for _, chunk_and_statement_number in ipairs(initial_changed_statements) do
        local chunk, statement_number = table.unpack(chunk_and_statement_number)
        add_changed_statement(chunk, statement_number)
      end

      -- Iterate over the changed statements until convergence.
      local num_inner_loops, max_theoretical_inner_loops = 0, num_interesting_statements * num_interesting_statements
      while #changed_statements_list > 0 do
        -- Guard against infinite loops.
        assert(num_inner_loops <= max_theoretical_inner_loops)

        -- Guard against too many loops, making the processing unbearably slow.
        if max_inner_loops ~= false and num_inner_loops > max_inner_loops then
          break
        end

        -- Pick a statement from the stack of changed statements.
        local chunk, statement_number = pop_changed_statement()

        -- Determine the reaching definitions from before the current statement.
        local incoming_definition_list, incoming_definition_index
          = get_incoming_reaching_definitions(reaching_definition_type, states, chunk, statement_number)

        -- Determine the definitions and undefinitions from the current statement.
        local current_definition_list, _, invalidated_statement_index
          = get_current_reaching(
              reaching_definition_type,
              states,
              chunk,
              statement_number,
              incoming_definition_list,
              incoming_definition_index
            )

        -- Determine the reaching definitions after the current statement.
        local updated_definition_list, updated_definition_index, current_reaching_statement_index
          = get_outgoing_reaching_definitions(
              states,
              incoming_definition_list,
              current_definition_list,
              invalidated_statement_index
            )

        -- Update the stack of changed statements.
        if have_reaching_changed(
            reaching_definition_type, states, chunk, statement_number, updated_definition_list, current_reaching_statement_index) then
          -- Insert the successive statements into the stack of changed statements.
          for _, out_edge_index in ipairs({edge_indexes.explicit_out, edge_indexes.implicit_out}) do
            if out_edge_index[chunk] ~= nil and out_edge_index[chunk][statement_number] ~= nil then
              for _, edge in ipairs(out_edge_index[chunk][statement_number]) do
                add_changed_statement(edge.to.chunk, edge.to.statement_number)
              end
            end
          end

          -- Update the reaching definitions.
          if reaching_definitions.lists[chunk] == nil then
            assert(reaching_definitions.indexes[chunk] == nil)
            reaching_definitions.lists[chunk] = {}
            reaching_definitions.indexes[chunk] = {}
          end
          if reaching_definitions.lists[chunk][statement_number] == nil then
            assert(reaching_definitions.indexes[chunk][statement_number] == nil)
            reaching_definitions.lists[chunk][statement_number] = {}
            reaching_definitions.indexes[chunk][statement_number] = {}
          end
          reaching_definitions.lists[chunk][statement_number] = updated_definition_list
          reaching_definitions.indexes[chunk][statement_number] = updated_definition_index
        end

        num_inner_loops = num_inner_loops + 1
      end
    end

    -- Make a copy of the current estimation of the function call and variable use edges.
    previous_function_call_edges, previous_variable_use_edges = {}, {}
    for _, previous_and_current_edges in ipairs({
      {previous_function_call_edges, current_function_call_edges},
      {previous_variable_use_edges, current_variable_use_edges},
    }) do
      local previous_edges, current_edges = table.unpack(previous_and_current_edges)
      for _, edge in ipairs(current_edges) do
        table.insert(previous_edges, edge)
      end
    end

    -- Update the current estimation of the function call and variable use edges.
    local reaching_definitions = states.results.reaching_definitions[REACHING_DEFINITIONS]
    current_function_call_edges, current_variable_use_edges = {}, {}
    states.results.csname_definition_in_edge_index = {}
    states.results.elided_csname_use_out_edge_index = {}
    for _, edge_types_statement_list_and_current_edges in ipairs({
      {FUNCTION_CALL, FUNCTION_CALL_RETURN, function_call_list, current_function_call_edges},
      {VARIABLE_USE, VARIABLE_USE_RETURN, variable_use_list, current_variable_use_edges},
    }) do
      local outgoing_edge_type, incoming_edge_type, statement_list, current_edges
        = table.unpack(edge_types_statement_list_and_current_edges)
      assert(type(statement_list) == "table")
      assert(type(current_edges) == "table")
      for _, csname_use_chunk_and_statement_number in ipairs(statement_list) do
        -- For each function call and variable use, first copy relevant reaching definitions to a temporary list.
        local csname_use_chunk, csname_use_statement_number = table.unpack(csname_use_chunk_and_statement_number)
        if reaching_definitions.indexes[csname_use_chunk] == nil or
            reaching_definitions.indexes[csname_use_chunk][csname_use_statement_number] == nil then
          goto next_csname_use
        end
        local csname_use_statement = get_statement(states, csname_use_chunk, csname_use_statement_number)
        assert(is_well_behaved(csname_use_statement))
        local intermediate_reaching_definition_list = {}
        local reaching_definition_index = reaching_definitions.indexes[csname_use_chunk][csname_use_statement_number]
        local used_csname = csname_use_statement.used_csname.payload
        for _, definition in ipairs(reaching_definition_index[used_csname] or {}) do
          assert(definition.csname == used_csname)
          table.insert(intermediate_reaching_definition_list, definition)
        end

        -- Then, resolve all function variant and indirect function/variable definitions to the originating direct function/variable
        -- declarations/definitions, if any.
        local reaching_definition_number, seen_reaching_statements = 1, {}
        local reaching_definition_list = {}
        while reaching_definition_number <= #intermediate_reaching_definition_list do
          local definition = intermediate_reaching_definition_list[reaching_definition_number]
          local chunk, macro_statement_number, statement_number
            = definition.chunk, definition.macro_statement_number, definition.statement_number
          local statement = get_statement(states, chunk, macro_statement_number, statement_number)
          assert(is_well_behaved(statement))
          -- Detect any loops within the graph.
          if seen_reaching_statements[statement] ~= nil then
            goto next_reaching_statement
          end
          seen_reaching_statements[statement] = true
          if statement.type == FUNCTION_DEFINITION and statement.subtype == FUNCTION_DEFINITION_DIRECT
              or statement.type == VARIABLE_DEFINITION and statement.subtype == VARIABLE_DEFINITION_DIRECT then
            -- Simply record the direct function/variable definitions.
            table.insert(reaching_definition_list, definition)
          elseif statement.type == FUNCTION_DEFINITION and statement.subtype == FUNCTION_DEFINITION_INDIRECT
              or statement.type == VARIABLE_DEFINITION and statement.subtype == VARIABLE_DEFINITION_INDIRECT
              or statement.type == FUNCTION_VARIANT_DEFINITION then
            -- Resolve the indirect function definitions and function variant definitions.
            if reaching_definitions.lists[chunk] ~= nil and
                reaching_definitions.lists[chunk][macro_statement_number] ~= nil then
              local other_reaching_definition_index = reaching_definitions.indexes[chunk][macro_statement_number]
              local base_csname = statement.base_csname.payload
              -- Elide calls to indirect function/variable definitions and index those definitions.
              states.results.elided_csname_use_out_edge_index[csname_use_statement] = true
              states.results.csname_definition_in_edge_index[statement] = true
              for _, other_definition in ipairs(other_reaching_definition_index[base_csname] or {}) do
                local other_chunk, other_macro_statement_number, other_statement_number
                  = other_definition.chunk, other_definition.macro_statement_number, other_definition.statement_number
                local other_statement = get_statement(states, other_chunk, other_macro_statement_number, other_statement_number)
                assert(is_well_behaved(other_statement))
                assert(other_definition.csname == base_csname)
                -- Weaken the base function/variant definition confidence.
                local combined_definition
                if definition.confidence < other_definition.confidence then
                  combined_definition = make_shallow_copy(other_definition)
                  combined_definition.confidence = definition.confidence
                else
                  combined_definition = other_definition
                end
                table.insert(intermediate_reaching_definition_list, combined_definition)
              end
            end
          else
            error('Unexpected statement type and "' .. statement.type .. '" and subtype "' .. statement.subtype .. '"')
          end
          ::next_reaching_statement::
          reaching_definition_number = reaching_definition_number + 1
        end

        -- Draw the function call and variable use edges.
        for _, csname_definition in ipairs(reaching_definition_list) do
          local csname_definition_statement = get_statement(
            states,
            csname_definition.chunk,
            csname_definition.macro_statement_number,
            csname_definition.statement_number
          )
          assert(is_well_behaved(csname_definition_statement))

          -- Index the definitions used in the function calls / variable uses.
          states.results.csname_definition_in_edge_index[csname_definition_statement] = true

          -- Determine the segment of the function/varuable definition replacement/definition text.
          local results = states[csname_definition.chunk.segment.location.file_number].results
          local to_segment_number
          if csname_definition_statement.type == FUNCTION_DEFINITION then
            assert(csname_definition_statement.subtype == FUNCTION_DEFINITION_DIRECT)
            to_segment_number = csname_definition_statement.replacement_text_argument.segment_number
          elseif csname_definition_statement.type == VARIABLE_DEFINITION then
            assert(csname_definition_statement.subtype == VARIABLE_DEFINITION_DIRECT)
            to_segment_number = csname_definition_statement.definition_text_argument.segment_number
          else
            error(
              string.format(
                'Unexpected statement type "%s" and subtype "%s"',
                csname_definition_statement.type,
                csname_definition_statement.subtype
              )
            )
          end
          if to_segment_number == nil then
            states.results.elided_csname_use_out_edge_index[csname_use_statement] = true
            goto next_csname_definition
          end
          local to_segment = results.segments[to_segment_number]

          -- Elide calls to function/variable definitions with empty replacement/definition texts.
          if to_segment.chunks == nil or #to_segment.chunks == 0 then
            states.results.elided_csname_use_out_edge_index[csname_use_statement] = true
            goto next_csname_definition
          end

          -- Determine the edge confidence.
          local edge_confidence
          if #reaching_definition_list > 1 then
            -- If there are multiple definitions for this function call, then it's uncertain which one will be used.
            edge_confidence = MAYBE
          else
            -- Otherwise, use the minimum of the function/variable definition statement confidence and the edge confidences along
            -- the maximum-confidence path from the function/variable definition statement to the function call / variable use
            -- statement.
            edge_confidence = csname_definition.confidence
          end
          assert(edge_confidence >= MAYBE)

          -- Draw the edges.
          local use_edge_to_chunk = to_segment.chunks[1]
          local use_edge_to_statement_number = use_edge_to_chunk.statement_range:start()
          local use_edge = {
            type = outgoing_edge_type,
            from = {
              chunk = csname_use_chunk,
              statement_number = csname_use_statement_number,
            },
            to = {
              chunk = use_edge_to_chunk,
              statement_number = use_edge_to_statement_number,
            },
            confidence = edge_confidence,
          }
          local return_edge_from_chunk = to_segment.chunks[#to_segment.chunks]
          local return_edge_from_statement_number = return_edge_from_chunk.statement_range:stop() + 1
          local return_edge = {
            type = incoming_edge_type,
            from = {
              chunk = return_edge_from_chunk,
              statement_number = return_edge_from_statement_number,
            },
            to = {
              chunk = csname_use_chunk,
              statement_number = csname_use_statement_number + 1,
            },
            confidence = edge_confidence,
          }
          -- The following attributes are specific to the edge types.
          table.insert(current_edges, use_edge)
          table.insert(current_edges, return_edge)
          ::next_csname_definition::
        end
        ::next_csname_use::
      end
    end

    num_outer_loops = num_outer_loops + 1
  until not (
    any_edges_changed(previous_function_call_edges, current_function_call_edges)
    or any_edges_changed(previous_variable_use_edges, current_variable_use_edges)
  )

  -- Record edges.
  local edge_indexes = states.results.edge_indexes[REACHING_DEFINITIONS]
  for _, current_edges_and_edge_index_name in ipairs({
    {current_function_call_edges, "function_call_out"},
    {current_variable_use_edges, "variable_use_out"},
  }) do
    local current_edges, edge_index_name = table.unpack(current_edges_and_edge_index_name)
    assert(type(current_edges) == "table")
    edge_indexes[edge_index_name] = {}
    for _, edge in ipairs(current_edges) do
      local results = states[edge.from.chunk.segment.location.file_number].results
      assert(results.edges ~= nil)
      if results.edges[DYNAMIC] == nil then
        results.edges[DYNAMIC] = {}
      end
      table.insert(results.edges[DYNAMIC], edge)
      _index_edge(REACHING_DEFINITIONS, edge_index_name, 'from', edge)
    end
  end
end

-- For each segment, determine the minimum reaching nesting depth from other segments.
local function determine_min_reaching_nesting_depth(states, _, _)
  -- Determine the minimum reaching nesting depth once for all files in the file group, not just individual files.
  if states.results.determined_min_reaching_nesting_depth ~= nil then
    return
  end
  states.results.determined_min_reaching_nesting_depth = true

  local changed_segment_list, changed_segment_index = {}, {}

  -- Add a changed segment on the top of the stack.
  local function add_changed_segment(segment)
    if changed_segment_index[segment] == nil then
      table.insert(changed_segment_list, segment)
      changed_segment_index[segment] = true
    end
  end

  -- Pop a changed segment off the top of stack.
  local function pop_changed_segment()
    local segment = table.remove(changed_segment_list)
    changed_segment_index[segment] = nil
    return segment
  end

  -- Collect all segments with incoming or outgoing edges and index all these edges.
  local incoming_edge_index, outgoing_edge_index = {}, {}
  for _, state in ipairs(states) do
    -- Skip statements from files in the current file group that haven't reached the flow analysis.
    if state.results.stopped_early then
      goto next_file
    end
    local edge_category_list = {}
    for edge_category, _ in pairs(state.results.edges or {}) do
      table.insert(edge_category_list, edge_category)
    end
    table.sort(edge_category_list)
    for _, edge_category in ipairs(edge_category_list) do
      local edges = state.results.edges[edge_category]
      for _, edge in ipairs(edges) do
        -- Collect the segments with incoming or outgoing edges.
        for _, segment in ipairs({edge.from.chunk.segment, edge.to.chunk.segment}) do
          add_changed_segment(segment)
        end
        -- Index the edges.
        for _, segments_and_edge_index in ipairs({
              {edge.to.chunk.segment, edge.from.chunk.segment, incoming_edge_index},
              {edge.from.chunk.segment, edge.to.chunk.segment, outgoing_edge_index},
            }) do
          local from_segment, to_segment, edge_index = table.unpack(segments_and_edge_index)
          if edge_index[from_segment] == nil then
            edge_index[from_segment] = {}
          end
          if edge_index[from_segment][to_segment] == nil then
            table.insert(edge_index[from_segment], to_segment)
            edge_index[from_segment][to_segment] = true
          end
        end
      end
    end
    ::next_file::
  end

  -- Iterate over the changed statements until convergence.
  while #changed_segment_list > 0 do
    -- Pick a sedgment from the stack of changed segments.
    local segment = pop_changed_segment()

    -- Determine the incoming minimum reaching nesting depth.
    local min_reaching_nesting_depth = segment.min_reaching_nesting_depth
    for _, incoming_segment in ipairs(incoming_edge_index[segment] or {}) do
      min_reaching_nesting_depth = math.min(min_reaching_nesting_depth, incoming_segment.min_reaching_nesting_depth)
    end

    -- Update the current minimum reaching nesting depth.
    if min_reaching_nesting_depth < segment.min_reaching_nesting_depth then
      segment.min_reaching_nesting_depth = min_reaching_nesting_depth
      -- If there was an update, mark all outgoing segments as changed.
      for _, outgoing_segment in ipairs(outgoing_edge_index[segment] or {}) do
        add_changed_segment(outgoing_segment)
      end
    end
  end
end

-- Report any issues.
local function report_issues(states, main_file_number, options)
  local state = states[main_file_number]

  local issues = state.issues

  local expl3_well_known_csname = parsers.expl3_well_known_csname(options, state.pathname)

  for _, segment in ipairs(state.results.segments or {}) do
    local part_number = segment.location.part_number
    local tokens = state.results.tokens[part_number]
    local token_range_to_byte_range = get_token_range_to_byte_range(tokens, #state.content)
    for _, chunk in ipairs(segment.chunks or {}) do
      local call_range_to_token_range = get_call_range_to_token_range(chunk.segment.calls, #tokens)
      for macro_statement_number, macro_statement in chunk.statement_range:enumerate(segment.macro_statements) do
        -- Skip uninteresting macro statements that would have been skipped during the analysis.
        if not _is_interesting(REACHING_DECLARATIONS, states, chunk, macro_statement_number)
            and not _is_interesting(REACHING_DEFINITIONS, states, chunk, macro_statement_number) then
          goto next_macro_statement
        end
        -- Report issues with function (variant) (un)definitions.
        if macro_statement.type == FUNCTION_AND_VARIABLE_DEFINITIONS then
          for statement_number, statement in ipairs(macro_statement.statements or {macro_statement}) do
            assert(not is_macro_statement(statement))
            if statement.confidence ~= DEFINITELY then
              goto next_statement
            end

            -- Get the byte range of the current statement.
            local function get_byte_range()
              local token_range = call_range_to_token_range(statement.call_range)
              local byte_range = token_range_to_byte_range(token_range)

              return byte_range
            end

            -- Get definitions for a given control sequence name that reach the current statement.
            local function get_reaching(reaching_definition_type, csname)
              local incoming_definition_list, incoming_definition_index
                = get_incoming_reaching_definitions(reaching_definition_type, states, chunk, macro_statement_number)
              local current_definition_list, current_definition_index, invalidated_statement_index = get_current_reaching(
                reaching_definition_type,
                states,
                chunk,
                macro_statement_number,
                incoming_definition_list,
                incoming_definition_index,
                statement_number - 1
              )

              local definition_lists = {incoming_definition_list, current_definition_list}
              local definition_indexes = {incoming_definition_index[csname] or {}, current_definition_index[csname] or {}}
              local current_definition_list_number, current_definition_number = 1, 1

              return function()
                while true do
                  if current_definition_list_number > #definition_lists then
                    return nil
                  end
                  local definition_list = definition_lists[current_definition_list_number]
                  local definition_index = definition_indexes[current_definition_list_number]
                  if current_definition_number > #definition_index then
                    current_definition_list_number = current_definition_list_number + 1
                    current_definition_number = 1
                    goto continue
                  end
                  local definition_number = definition_index[current_definition_number]
                  current_definition_number = current_definition_number + 1
                  local definition = definition_list[definition_number]
                  local other_statement
                    = get_statement(states, definition.chunk, definition.macro_statement_number, definition.statement_number)
                  if not invalidated_statement_index[other_statement] then
                    return definition
                  end
                  ::continue::
                end
              end
            end

            -- Determine whether there are any definite definitions for a given control sequence name that reach the current statement.
            local function any_reaching(reaching_definition_type, csname, check_definition)
              for definition in get_reaching(reaching_definition_type, csname) do
                assert(definition.csname == csname)
                if check_definition ~= nil then
                  local other_statement = get_statement(
                    states,
                    definition.chunk,
                    definition.macro_statement_number,
                    definition.statement_number
                  )
                  if check_definition(definition, other_statement) then
                    return true
                  else
                    goto next_definition
                  end
                else
                  return true
                end
                ::next_definition::
              end
            end

            if (
                  statement.type == FUNCTION_DEFINITION and not statement.maybe_redefinition or
                  statement.type == FUNCTION_VARIANT_DEFINITION
                ) and statement.defined_csname.type == TEXT then
              local defined_csname = statement.defined_csname.payload
              if any_reaching(
                    REACHING_DEFINITIONS,
                    defined_csname,
                    function(definition, other_statement)
                      return definition.confidence == DEFINITELY and
                        statement ~= other_statement and  -- a definition is reached by itself, not a redefinition
                        (
                          other_statement.type == FUNCTION_DEFINITION and not other_statement.maybe_redefinition or
                          other_statement.type == FUNCTION_VARIANT_DEFINITION
                        )
                    end
                  ) then
                local formatted_csname = format_csname(defined_csname)
                local byte_range = get_byte_range()

                -- Report a multiply defined function.
                if statement.type == FUNCTION_DEFINITION then
                  issues:add("e500", "multiply defined function", byte_range, formatted_csname)
                -- Report a multiply defined function variant.
                elseif statement.type == FUNCTION_VARIANT_DEFINITION then
                  issues:add("w501", "multiply defined function variant", byte_range, formatted_csname)
                else
                  error('Unexpected statement type "' .. statement.type .. '"')
                end
              end
            end

            -- For the following issues, only consider statements reachable from top-level code.
            -- Otherwise, the statements are part of either dead code or library functions and we can't accurately
            -- determine their reaching definitions.
            if segment.min_reaching_nesting_depth > 1 then
              goto next_macro_statement
            end

            if (
                  statement.type == FUNCTION_VARIANT_DEFINITION or
                  statement.type == FUNCTION_DEFINITION and statement.subtype == FUNCTION_DEFINITION_INDIRECT
                ) and statement.base_csname.type == TEXT then
              local base_csname = statement.base_csname.payload
              if lpeg.match(expl3_well_known_csname, base_csname) == nil and
                  not any_reaching(REACHING_DEFINITIONS, base_csname) then
                local formatted_csname = format_csname(base_csname)
                local byte_range = get_byte_range()

                -- Report function variants for an undefined function.
                if statement.type == FUNCTION_VARIANT_DEFINITION then
                  issues:add("e504", "function variant for an undefined function", byte_range, formatted_csname)
                -- Report indirect function definitions from an undefined function.
                elseif statement.type == FUNCTION_DEFINITION then
                  assert(statement.subtype == FUNCTION_DEFINITION_INDIRECT)
                  issues:add("e506", "indirect function definition from an undefined function", byte_range, formatted_csname)
                else
                  error('Unexpected statement type "' .. statement.type .. '" and subtype "' .. statement.subtype .. '"')
                end
              end
            end

            -- Report setting a function before definition.
            if statement.type == FUNCTION_DEFINITION and statement.maybe_redefinition and statement.defined_csname.type == TEXT then
              local defined_csname = statement.defined_csname.payload
              if lpeg.match(expl3_well_known_csname, defined_csname) == nil and
                  not any_reaching(REACHING_DEFINITIONS, defined_csname) then
                local formatted_csname = format_csname(defined_csname)
                local byte_range = get_byte_range()
                issues:add("w507", "setting a function before definition", byte_range, formatted_csname)
              end
            end

            if (
                  (
                    (statement.type == FUNCTION_DEFINITION or statement.type == FUNCTION_VARIANT_DEFINITION)
                      and statement.is_private and statement.call_segments ~= nil or
                    statement.type == VARIABLE_DECLARATION and statement.use_segments ~= nil
                  ) and
                  states.results.csname_definition_in_edge_index[statement] == nil
                ) then
              local call_or_use_segments, defined_or_declared_csname
              if statement.type == FUNCTION_DEFINITION or statement.type == FUNCTION_VARIANT_DEFINITION then
                call_or_use_segments = statement.call_segments
                defined_or_declared_csname = statement.defined_csname
              else
                assert(statement.type == VARIABLE_DECLARATION)
                call_or_use_segments = statement.use_segments
                defined_or_declared_csname = statement.declared_csname
              end
              assert(#call_or_use_segments > 0)
              assert(defined_or_declared_csname.type == TEXT)
              local all_calls_or_use_reached_flow_analysis_and_are_top_level_reachable = true
              for _, call_or_use_segment in ipairs(call_or_use_segments) do
                if (
                      -- Only consider function (variant) definitions / variable declarations with calls/uses reachable from
                      -- top-level code. Otherwise, the calls/uses are part of either dead code or library functions and we can't
                      -- accurately determine their reaching definitions.
                      call_or_use_segment.min_reaching_nesting_depth > 1 or
                      -- Do not consider function (variant) definitions / variable declarations calls/uses in files that did not
                      -- reach the flow analysis.
                      states[call_or_use_segment.location.file_number].results.stopped_early
                    ) then
                  all_calls_or_use_reached_flow_analysis_and_are_top_level_reachable = false
                  break
                end
              end
              if all_calls_or_use_reached_flow_analysis_and_are_top_level_reachable then
                local formatted_csname = format_csname(defined_or_declared_csname.payload)
                local byte_range = get_byte_range()

                -- Report unused private function definitions.
                if statement.type == FUNCTION_DEFINITION then
                  issues:add("w502", "unused private function", byte_range, formatted_csname)
                -- Report unused private function variant definitions.
                elseif statement.type == FUNCTION_VARIANT_DEFINITION then
                  issues:add("w503", "unused private function variant", byte_range, formatted_csname)
                -- Report unused variable or constant declarations.
                elseif statement.type == VARIABLE_DECLARATION then
                  issues:add("w517", "unused variable or constant", byte_range, formatted_csname)
                else
                  error('Unexpected statement type "' .. statement.type .. '"')
                end
              end
            end

            ::next_statement::
          end
        -- Report calling an undefined function.
        elseif macro_statement.type == FUNCTION_CALL then
          local statement_number, statement = macro_statement_number, macro_statement
          assert(not is_macro_statement(statement))

          -- Only consider function calls reachable from top-level code. Otherwise, the calls are part of either dead code
          -- or library functions and we can't accurately determine their reaching definitions.
          if segment.min_reaching_nesting_depth > 1 then
            goto next_macro_statement
          end
          if statement.confidence ~= DEFINITELY then
            goto next_macro_statement
          end
          if not is_well_behaved(statement) then
            goto next_macro_statement
          end
          assert(statement.used_csname.type == TEXT)

          -- Get the byte range of the current statement.
          local function get_byte_range()
            local token_range = call_range_to_token_range(statement.call_range)
            local byte_range = token_range_to_byte_range(token_range)

            return byte_range
          end

          assert(statement.definition_file_numbers ~= nil)
          assert(#statement.definition_file_numbers > 0)
          local all_definitions_reached_flow_analysis = true
          for _, file_number in ipairs(statement.definition_file_numbers) do
            -- Do not check statements with definitions in files that did not reach the flow analysis.
            if states[file_number].results.stopped_early then
              all_definitions_reached_flow_analysis = false
              break
            end
          end
          if all_definitions_reached_flow_analysis then
            local edge_indexes = states.results.edge_indexes[REACHING_DEFINITIONS]
            if edge_indexes.function_call_out[chunk] == nil or edge_indexes.function_call_out[chunk][statement_number] == nil then
              if states.results.elided_csname_use_out_edge_index[statement] == nil then
                local formatted_csname = format_csname(statement.used_csname.payload)
                local byte_range = get_byte_range()
                issues:add("e505", "calling an undefined function", byte_range, formatted_csname)
              end
            else
              assert(#edge_indexes.function_call_out[chunk][statement_number] > 0)
            end
          end
        end
        ::next_macro_statement::
      end
    end
  end
end

-- Remove auxiliary intermediate results to free up memory.
local function cleanup(states, _, _)
  -- Remove group-wide intermediate results.
  states.results.determined_min_reaching_nesting_depth = nil
  states.results.drew_dynamic_edges = nil
  states.results.drew_static_edges = nil
  states.results.edge_indexes = nil
  states.results.csname_definition_in_edge_index = nil
  states.results.elided_csname_use_out_edge_index = nil
  states.results.reaching_definitions = nil
end

local substeps = {
  merge_statements,
  collect_chunks,
  draw_file_local_static_edges,
  draw_group_wide_static_edges,
  draw_group_wide_dynamic_edges,
  determine_min_reaching_nesting_depth,
  report_issues,
  cleanup,
}

return {
  edge_types = edge_types,
  is_confused = is_confused,
  name = "flow analysis",
  substeps = substeps,
}
