-- Classes for tracking expandability estimates for expl3 objects.

local ExpandabilityEstimate = {}

-- Create a new maximally-optimistic expandability estimate.
function ExpandabilityEstimate.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.maybe_fully_expandable = true
  self.not_fully_expandable_reason = nil
  self.maybe_restricted_expandable = true
  self.not_restricted_expandable_reason = nil
  return self
end

-- Weaken an expandability estimate and remember what caused each lost property.
function ExpandabilityEstimate:weaken(maybe_fully_expandable, maybe_restricted_expandable, expandability_reason)
  assert(expandability_reason ~= nil)
  if self.maybe_fully_expandable and not maybe_fully_expandable then
    self.maybe_fully_expandable = false
    self.not_fully_expandable_reason = expandability_reason
  end
  if self.maybe_restricted_expandable and not maybe_restricted_expandable then
    self.maybe_restricted_expandable = false
    self.not_restricted_expandable_reason = expandability_reason
  end
end

local expandability_types = {
  BASIC = "basic expandability within top-level material",
}

local BASIC = expandability_types.BASIC

table.insert(expandability_types, BASIC)

local ExpandabilityEstimates = {}

-- Create new maximally-optimistic expandability estimates for all different expandability types.
function ExpandabilityEstimates.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  for _, expandability_type in ipairs(expandability_types) do
    self[expandability_type] = ExpandabilityEstimate:new()
  end
  return self
end

return {
  expandability_types = expandability_types,
  new_expandability = function()
    return ExpandabilityEstimates:new()
  end,
}
