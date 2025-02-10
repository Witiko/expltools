-- A class for working with index ranges in arrays.

local Range = {}

-- Create a new range based on the start/end indices, the type of the end index
-- (inclusive/exclusive), the size of the array that contains the range, and an
-- optional nondecreasing map-back function from indices in the array to
-- indices in an original array and the size of the original array.
function Range.new(cls, range_start, range_end, end_type, transformed_array_size, map_back, original_array_size)
  -- Instantiate the class.
  local new_object = {}
  setmetatable(new_object, cls)
  cls.__index = cls
  -- Check pre-conditions.
  if transformed_array_size == 0 then
    assert(range_start == 0)
  else
    assert(range_start >= 1)
    assert(range_start <= transformed_array_size)
  end
  assert(end_type == "inclusive" or end_type == "exclusive")
  if end_type == "exclusive" then
    -- Convert exclusive range end to inclusive.
    range_end = range_end - 1
  end
  if transformed_array_size == 0 then
    assert(range_end == 0)
  else
    assert(range_end >= range_start)
    assert(range_end <= transformed_array_size)
  end
  local mapped_range_start, mapped_range_end
  if map_back ~= nil then
    -- Apply the map-back function to the endpoints of the range.
    assert(original_array_size ~= nil)
    mapped_range_start = map_back(range_start)
    if original_array_size == 0 then
      assert(mapped_range_start == 0)
    else
      assert(mapped_range_start >= 1)
      assert(mapped_range_start <= original_array_size)
    end
    mapped_range_end = map_back(range_end)
    if original_array_size == 0 then
      assert(mapped_range_end == 0)
    else
      assert(mapped_range_end >= mapped_range_start)
      assert(mapped_range_end <= original_array_size)
    end
  else
    mapped_range_start = range_start
    mapped_range_end = range_end
  end
  -- Initialize the class.
  new_object.range_start = mapped_range_start
  new_object.range_end = mapped_range_end
  return new_object
end

-- Get the inclusive start of the range, optionally mapped back to the original array.
function Range:start()
  return self.range_start
end

-- Get the inclusive end of the range, optionally mapped back to the original array.
function Range:end_inclusive()
  return self.range_end
end

-- Get the exclusive end of the range, optionally mapped back to the original array.
function Range:end_exclusive()
  return self.range_end + 1
end

return function(...)
  return Range:new(...)
end
