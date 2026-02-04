-- Classes for working with index ranges in arrays.

local Range = {}

local range_flags = {
  EXCLUSIVE = 0,  -- the end index is one higher than the actual last item
  INCLUSIVE = 1,  -- the end index is corresponds to the last item
  MAYBE_EMPTY = 2,  -- the range may be empty
  FIRST_MAP_THEN_SUBTRACT = 4,  -- for EXCLUSIVE, first map back to the original array and _then_ subtract one, not vise versa
}

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY
local FIRST_MAP_THEN_SUBTRACT = range_flags.FIRST_MAP_THEN_SUBTRACT

-- Create a new range based on the start/end indices, the type of the end index
-- (INCLUSIVE/EXCLUSIVE, MAYBE_EMPTY), the size of the array that contains the
-- range, and an optional nondecreasing map-back function from indices in the
-- array to indices in an original array and the size of the original array.
--
-- Since empty ranges are usually a mistake, they are not allowed unless MAYBE_EMPTY
-- is specified. For example, `Range:new(index, index, EXCLUSIVE, #array)` is not
-- allowed but `Range:new(index, index, EXCLUSIVE + MAYBE_EMPTY, #array)` is.
-- The exception to this rule are empty arrays, which always produce an empty range.
function Range.new(cls, range_start, range_end, end_type, transformed_array_size, map_back, original_array_size)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Check pre-conditions.
  if transformed_array_size == 0 then
    -- If the transformed array is empty, produce an empty range, encoded as [0; 0].
    range_start = 0
    range_end = 0
    end_type = INCLUSIVE + MAYBE_EMPTY
  else
    -- Otherwise, check that the range start is not out of bounds.
    assert(range_start >= 1)
    assert(range_start <= transformed_array_size)
  end
  local exclusive_end = end_type % 2 == EXCLUSIVE
  local maybe_empty = end_type - (end_type % 2) == MAYBE_EMPTY
  local first_map_then_subtract = end_type - (end_type % 4) == FIRST_MAP_THEN_SUBTRACT
  if first_map_then_subtract then
    assert(map_back ~= nil)
  end
  if exclusive_end then
    -- Convert exclusive range end to inclusive.
    range_end = range_end - 1
  end
  if transformed_array_size == 0 then
    -- If the transformed array is empty, only allow empty ranges, encoded as [0; 0].
    assert(range_start == 0)
    assert(range_end == 0)
  else
    -- Otherwise:
    if maybe_empty then
      -- If MAYBE_EMPTY is specified, allow empty ranges [x, x).
      assert(range_end >= range_start - 1)
    else
      -- Otherwise, only allow non-empty ranges [x, y].
      assert(range_end >= range_start)
    end
    -- Check that the range end is not out of bounds.
    assert(range_end <= transformed_array_size)
  end
  -- Apply the map-back function.
  local mapped_range_start, mapped_range_end
  if map_back ~= nil then
    -- Apply the map-back function to the range start.
    assert(original_array_size ~= nil)
    mapped_range_start = map_back(range_start)
    if original_array_size == 0 then
      -- If the original array is empty, check that the range start has stayed at 0.
      assert(mapped_range_start == 0)
    else
      -- Otherwise, check that the range start is not out of bounds.
      assert(mapped_range_start >= 1)
      assert(mapped_range_start <= original_array_size)
    end
    if range_end < range_start then
      -- If the range is supposed to be empty, set the range end to the range start - 1.
      assert(maybe_empty)
      mapped_range_end = mapped_range_start - 1
    else
      -- Otherwise, apply the map-back function to the range end as well.
      if exclusive_end and first_map_then_subtract then
        -- If EXCLUSIVE + FIRST_MAP_THEN_SUBTRACT is specified, use the exclusive index in the mapping and
        -- only subtract the index after the mapping.
        mapped_range_end = map_back(range_end + 1) - 1
      else
        mapped_range_end = map_back(range_end)
      end
    end
    if original_array_size == 0 then
      -- If the original array is empty, check that the range end has also stayed at 0.
      assert(mapped_range_end == 0)
    else
      -- Otherwise:
      if maybe_empty then
        -- If MAYBE_EMPTY is specified, allow empty ranges [x, x).
        assert(mapped_range_end >= mapped_range_start - 1)
      else
        -- Otherwise, only allow non-empty ranges [x, y].
        assert(mapped_range_end >= mapped_range_start)
      end
      -- Check that the range end is not out of bounds.
      assert(mapped_range_end <= original_array_size)
    end
  else
    mapped_range_start = range_start
    mapped_range_end = range_end
  end
  -- Initialize the class.
  self.range_start = mapped_range_start
  self.range_end = mapped_range_end
  return self
end

-- Get the inclusive start of the range, optionally mapped back to the original array.
function Range:start()
  return self.range_start
end

-- Get the inclusive end of the range, optionally mapped back to the original array.
function Range:stop()
  return self.range_end
end

-- Get the length of the range.
function Range:__len()
  if self.range_length == nil then
    if self:start() == 0 then
      assert(self:stop() == 0)
      self.range_length = 0  -- empty range
    elseif self:stop() < self:start() then
      assert(self:stop() == self:start() - 1)
      self.range_length = 0  -- empty range
    else
      self.range_length = self:stop() - self:start() + 1  -- non-empty range
    end
  end
  return self.range_length
end

-- Get an iterator over pairs of indices and items from the original array within the range.
function Range:enumerate(original_array, map_back)
  if #self == 0 then
    return function()  -- empty range
      return nil
    end
  else
    local start, stop = self:start(), self:stop()
    if map_back ~= nil then
      start = map_back(start)
      stop = map_back(stop)
    end
    assert(start >= 1)
    assert(start <= #original_array)
    assert(stop >= start)
    assert(stop <= #original_array)
    local i = start - 1
    return function()  -- non-empty range
      i = i + 1
      if i <= stop then
        return i, original_array[i]
      else
        return nil
      end
    end
  end
end

-- Split a range in half, producing two new subranges.
function Range:bisect()
  assert(#self > 1)
  local midpoint = self:start() + math.ceil((self:stop() - self:start()) / 2)
  local left_subrange_size, right_subrange_size = midpoint - self:start(), self:stop() - midpoint + 1
  local left_subrange = Range:new(self:start(), midpoint, EXCLUSIVE, self:stop())
  local right_subrange = Range:new(midpoint, self:stop(), INCLUSIVE, self:stop())
  assert(#left_subrange == left_subrange_size)
  assert(#right_subrange == right_subrange_size)
  return left_subrange, right_subrange
end

-- Given a range where each index maps into a list of non-decreasing sub-ranges, produce a new range that start with the start
-- of the first sub-range and ends with the end of the last sub-range.
function Range:new_range_from_subranges(get_subrange, subarray_size)
  if #self == 0 then
    return self  -- empty range
  else
    local first_subrange = get_subrange(self:start())
    local last_subrange = get_subrange(self:stop())
    return Range:new(  -- non-empty range
      first_subrange:start(),
      last_subrange:stop(),
      INCLUSIVE + MAYBE_EMPTY,
      subarray_size
    )
  end
end

-- Check whether two ranges overlap.
function Range:intersects(other_range)
  if #self == 0 or #other_range == 0 then
    return false
  end
  if self:start() > other_range:stop() then
    return false
  end
  if self:stop() < other_range:start() then
    return false
  end
  return true
end

-- Check whether one range fully contains another.
function Range:contains(other_range)
  if not self:intersects(other_range) then
    return false
  end
  if self:start() > other_range:start() then
    return false
  end
  if self:stop() < other_range:stop() then
    return false
  end
  return true
end

-- Get a string representation of the range.
function Range:__tostring()
  if #self == 0 then
    if self:start() == 0 then
      assert(self:stop() == 0)
      return "(0, 0)"  -- empty range in empty array
    else
      return string.format("[%d, %d)", self:start(), self:stop() + 1)  -- empty range in non-empty array
    end
  else
    return string.format("[%d, %d]", self:start(), self:stop())  -- non-empty range
  end
end

local RangeTree = {}

-- Create a new segment tree that stores ranges, where all the stored ranges fall within a bounding range. Ranges are stored
-- together with associated values.
function RangeTree.new(cls, min_range_start, max_range_end, max_tree_depth)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.root_bounding_range = Range:new(min_range_start, max_range_end, INCLUSIVE + MAYBE_EMPTY, max_range_end)
  self.max_tree_depth = max_tree_depth
  self:clear()
  return self
end

-- Clear all ranges and values from the index.
function RangeTree:clear()
  self.tree_root = nil
  self.range_list = {}
  self.value_list = {}
end

-- Get the number of ranges and values stored in the index.
function RangeTree:__len()
  return #self.range_list
end

local add_duration, add_loops, get_intersecting_ranges_duration = 0, 0, 0

-- Add a new range into the index together with an associated value.
function RangeTree:add(range, value)
  local start_time = os.clock()
  assert(self.root_bounding_range:contains(range))
  table.insert(self.range_list, range)
  table.insert(self.value_list, value)
  assert(#self.range_list == #self.value_list)
  local value_number = #self.value_list

  -- Add a new range into the segment tree with an associated value.
  ---@diagnostic disable-next-line:redefined-local
  local function add_to_tree(range, value_number)  -- luacheck: ignore range value_number
    add_loops = add_loops + 1
    assert(self.tree_root ~= nil)
    -- Include the range in all tree nodes whose corresponding ranges it contains, creating those nodes if they don't exist.
    local current_node_stack = {self.tree_root}
    while #current_node_stack > 0 do
      local current_node = table.remove(current_node_stack)
      -- If the added range contains the range that corresponds to the current node or if we are at maximum tree depth,
      -- record the range and the value.
      if current_node._depth >= self.max_tree_depth or range:contains(current_node._range) then
        if current_node._value_number_list == nil then
          current_node._value_number_list = {}
        end
        table.insert(current_node._value_number_list, value_number)
      else
        if current_node._left_subrange == nil then
          -- Otherwise, bisect the range of the current node into two subranges.
          assert(current_node._right_subrange == nil)
          assert(#current_node._range > 1)
          current_node._left_subrange, current_node._right_subrange = current_node._range:bisect()
          assert(#current_node._left_subrange > 0)
          assert(#current_node._right_subrange > 0)
        end
        -- Then, if the added range intersects with either subrange, descend into the corresponding subnodes, creating them if
        -- they don't exist, in later iterations.
        if range:intersects(current_node._left_subrange) then
          if current_node._left_subnode == nil then
            current_node._left_subnode = {
              _depth = current_node._depth + 1,
              _range = current_node._left_subrange,
            }
          end
          table.insert(current_node_stack, current_node._left_subnode)
        end
        if range:intersects(current_node._right_subrange) then
          if current_node._right_subnode == nil then
            current_node._right_subnode = {
              _depth = current_node._depth + 1,
              _range = current_node._right_subrange,
            }
          end
          table.insert(current_node_stack, current_node._right_subnode)
        end
      end
    end
  end

  -- Defer the creation of the tree at least until the asymptotic worst-case time complexities of a linear scan and a tree query
  -- become the same.
  if #self.range_list > self.max_tree_depth then
    if self.tree_root == nil then
      self.tree_root = {
        _depth = 1,
        _range = self.root_bounding_range,
      }
      for current_value_number, current_range in ipairs(self.range_list) do
        add_to_tree(current_range, current_value_number)
      end
    else
      add_to_tree(range, value_number)
    end
  end
  add_duration = add_duration + os.clock() - start_time
end

-- Get all indexed ranges that intersect a given range and their associated values.
function RangeTree:get_intersecting_ranges(range)
  local start_time = os.clock()
  assert(self.root_bounding_range:contains(range))
  if self.tree_root ~= nil then
    -- If we have already created the tree, find all intersecting ranges in it.
    local current_node, current_value_number, current_child_number = self.tree_root, 1, 1
    local parent_nodes = {}
    return function()
      while true do
        local finished_all_values = current_node._value_number_list == nil or current_value_number > #current_node._value_number_list
        local finished_all_children = current_child_number > 2
        if not finished_all_values then
          -- If there are other values associated with the current node, return them.
          assert(#current_node._value_number_list ~= nil)
          local value_number = current_node._value_number_list[current_value_number]
          local current_range, value = self.range_list[value_number], self.value_list[value_number]
          current_value_number = current_value_number + 1
          return current_range, value
        elseif not finished_all_children then
          -- Otherwise, if there are other child nodes whose corresponding ranges the query range intersects, descend into them.
          local next_node
          if current_child_number == 1 then
            next_node = current_node._left_subnode
          else
            assert(current_child_number == 2)
            next_node = current_node._right_subnode
          end
          if next_node ~= nil and range:intersects(next_node._range) then
            table.insert(parent_nodes, {current_node, current_value_number, current_child_number + 1})
            current_node, current_value_number, current_child_number = next_node, 1, 1
          else
            current_child_number = current_child_number + 1
          end
        elseif current_node ~= self.tree_root then
          -- Otherwise, if we have previously descended, ascend to the parent node.
          assert(#parent_nodes > 0)
          current_node, current_value_number, current_child_number = table.unpack(table.remove(parent_nodes))
        else
          -- Otherwise, we should be done.
          assert(current_node == self.tree_root)
          assert(#parent_nodes == 0)
          get_intersecting_ranges_duration = get_intersecting_ranges_duration + os.clock() - start_time
          return nil
        end
      end
    end
  else
    -- Otherwise, if we haven't created the tree yet, just do a linear scan of all stored ranges.
    local i = 0
    return function()
      i = i + 1
      if i <= #self.range_list then
        local other_range = self.range_list[i]
        if range:intersects(other_range) then
          local value = self.value_list[i]
          return other_range, value
        end
      else
        get_intersecting_ranges_duration = get_intersecting_ranges_duration + os.clock() - start_time
        return nil
      end
    end
  end
end

return {
  new_range = function(...)
    return Range:new(...)
  end,
  new_range_tree = function(...)
    return RangeTree:new(...)
  end,
  range_flags = range_flags,
  add_duration = function()
    return add_duration
  end,
  add_loops = function()
    return add_loops
  end,
  get_intersecting_ranges_duration = function()
    return get_intersecting_ranges_duration
  end,
}
