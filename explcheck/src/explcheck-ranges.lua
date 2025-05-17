-- A class for working with index ranges in arrays.

local Range = {}

local range_flags = {
  EXCLUSIVE = 0,
  INCLUSIVE = 1,
  MAYBE_EMPTY = 2,
}

local EXCLUSIVE = range_flags.EXCLUSIVE
local INCLUSIVE = range_flags.INCLUSIVE
local MAYBE_EMPTY = range_flags.MAYBE_EMPTY

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
      mapped_range_end = map_back(range_end)
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
  if self:start() == 0 then
    assert(self:stop() == 0)
    return 0  -- empty range
  elseif self:stop() < self:start() then
    assert(self:stop() == self:start() - 1)
    return 0  -- empty range
  else
    return self:stop() - self:start() + 1  -- non-empty range
  end
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

return {
  new_range = function(...)
    return Range:new(...)
  end,
  range_flags = range_flags,
}
