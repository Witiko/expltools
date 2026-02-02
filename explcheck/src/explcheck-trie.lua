-- Classes for working with prefix trees (tries).

local PrefixTree = {}

-- Create a new prefix tree.
--
-- This is an uncompressed prefix tree based on Lua tables. To keep the retrieval constant time and the heap fragmentation low, it
-- should only be used for the storage of short strings with few distinct prefixes, such as issue identifiers. Strings are stored
-- together with associated values, which must be unique.
function PrefixTree.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.tree_root = {}
end

-- Add a new string into the tree together with an associated value.
function PrefixTree:add(text, value)  -- luacheck: ignore self text value
  assert(#text > 0)
  -- Find the node corresponding to the text in the tree, creating it if it doesn't exist.
  local current_node = self.tree_root
  for character_number = 1, #text do
    local character = text:sub(character_number, character_number)
    if current_node[character] == nil then
      current_node[character] = {}
      if current_node._character_list == nil then
        current_node._character_list = {}
      end
      table.insert(current_node._character_list, character)
    end
    current_node = current_node[character]
  end
  assert(current_node ~= self.tree_root)
  -- Record the value.
  if current_node._value_list == nil then
    current_node._value_list = {}
  end
  table.insert(current_node._value_list, value)
end

-- Get all indexed strings that share a given prefix and their associated values.
function PrefixTree:get_prefixed_by(prefix)
  assert(#prefix > 0)
  -- Find the node corresponding to the prefix in the tree.
  local current_prefix_node = self.tree_root
  for character_number = 1, #prefix do
    local character = prefix:sub(character_number, character_number)
    if current_prefix_node[character] == nil then
      return function() return nil end
    end
    current_prefix_node = current_prefix_node[character]
  end
  assert(current_prefix_node ~= self.tree_root)
  -- Find all suffixes and return the full strings and their associated values.
  local current_suffix_node, current_value_index, current_child_index, current_text = current_prefix_node, 1, 1, nil
  local suffix_parent_nodes, suffix_text_buffer = {}, {}
  return function()
    while true do
      local finished_all_values = current_suffix_node._value_list == nil or current_value_index > #current_suffix_node._value_list
      local finished_all_children = current_suffix_node._character_list == nil or current_child_index > #current_suffix_node._character_list
      if not finished_all_values then
        -- If there are other values associated with the current node, return them.
        assert(#current_suffix_node._value_list ~= nil)
        if current_text == nil then
          current_text = prefix .. table.concat(suffix_text_buffer, "")
        end
        local value = current_suffix_node._value_list[current_value_index]
        current_value_index = current_value_index + 1
        return current_text, value
      elseif not finished_all_children then
        -- Otherwise, if there are other child nodes for longer suffixes, descend into them.
        assert(#current_suffix_node._character_list ~= nil)
        local character = current_suffix_node._character_list[current_child_index]
        table.insert(suffix_parent_nodes, {current_suffix_node, current_value_index, current_child_index + 1, current_text})
        table.insert(suffix_text_buffer, character)
        assert(#suffix_parent_nodes == #suffix_text_buffer)
        current_suffix_node, current_value_index, current_child_index, current_text = current_suffix_node[character], 1, 1, nil
        assert(current_suffix_node ~= nil)
      elseif current_suffix_node ~= current_prefix_node then
        -- Otherwise, if we have previously descended, ascend to the parent node.
        assert(#suffix_parent_nodes > 0)
        current_suffix_node, current_value_index, current_child_index, current_text
          = table.unpack(suffix_parent_nodes[#suffix_parent_nodes])
        table.remove(suffix_parent_nodes)
        table.remove(suffix_text_buffer)
        assert(#suffix_parent_nodes == #suffix_text_buffer)
      else
        -- Otherwise, we should be done.
        assert(#suffix_parent_nodes == 0)
        return nil
      end
    end
  end
end

-- Get all indexed prefixes for a given string and their associated values.
function PrefixTree:get_prefixes_of(text)
  -- Find the node corresponding to the text in the tree, collecting prefixes and their associated values along the way.
  local current_prefix_node, current_value_index, character_number, character, current_text = self.tree_root, 1, 1, nil, nil
  local prefix_text_buffer = {}
  return function()
    while true do
      local finished_all_values = current_prefix_node._value_list == nil or current_value_index > #current_prefix_node._value_list
      if not finished_all_values then
        -- If there are other values associated with the current node, return them.
        assert(#current_prefix_node._value_list ~= nil)
        if current_text == nil then
          current_text = table.concat(prefix_text_buffer, "")
        end
        local value = current_prefix_node._value_list[current_value_index]
        current_value_index = current_value_index + 1
        return current_text, value
      else
        -- Otherwise, if there is a child node for a longer prefix, descend into it.
        if character_number > #text then
          -- If we have reached the end of the string, then we should be done.
          return nil
        end
        character = text:sub(character_number, character_number)
        if current_prefix_node[character] ~= nil then
          current_prefix_node, current_value_index, character_number, character, current_text
            = current_prefix_node[character], 1, character_number + 1, nil, nil
        else
          -- If there is no longer prefix, then we should be done.
          return nil
        end
      end
    end
  end
end

-- Remove one or more values from the index.
function PrefixTree:remove(values)  -- luacheck: ignore self values
  -- TODO
end

return {
  new_prefix_tree = function()
    return PrefixTree:new()
  end,
}
