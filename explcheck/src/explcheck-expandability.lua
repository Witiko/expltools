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
  -- Fully expandable objects are also restricted-expandable.
  assert(not self.maybe_fully_expandable or self.maybe_restricted_expandable)
end

local expandability_types = {
  BASIC = "basic expandability within top-level material",
  BOOLEAN_EXPRESSION = "expandability within boolean expressions",
}

local BASIC = expandability_types.BASIC
local BOOLEAN_EXPRESSION = expandability_types.BOOLEAN_EXPRESSION

table.insert(expandability_types, BASIC)
table.insert(expandability_types, BOOLEAN_EXPRESSION)

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

-- Weaken every type's estimate when the reason applies to all expandability types.
function ExpandabilityEstimates:weaken_all(...)
  for _, expandability_type in ipairs(expandability_types) do
    self[expandability_type]:weaken(...)
  end
end

-- Weaken the estimates for every expandability type except the specified one.
function ExpandabilityEstimates:weaken_all_except(excluded_type, ...)
  assert(self[excluded_type] ~= nil)
  for _, expandability_type in ipairs(expandability_types) do
    if expandability_type ~= excluded_type then
      self[expandability_type]:weaken(...)
    end
  end
end

-- Get the expandability type with the most optimistic estimate.
function ExpandabilityEstimates:get_most_optimistic()
  local best_type, best_estimate
  for _, expandability_type in ipairs(expandability_types) do
    local estimate = self[expandability_type]
    if best_estimate == nil or
        (estimate.maybe_fully_expandable and not best_estimate.maybe_fully_expandable) or
        (estimate.maybe_restricted_expandable and not best_estimate.maybe_restricted_expandable)
    then
      best_type, best_estimate = expandability_type, estimate
    end
  end
  assert(best_estimate ~= nil)
  return best_type, best_estimate
end

return {
  expandability_types = expandability_types,
  new_expandability = function()
    return ExpandabilityEstimates:new()
  end,
}
