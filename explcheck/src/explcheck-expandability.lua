-- Classes for tracking expandability estimates for expl3 objects.

local make_shallow_copy = require("explcheck-utils").make_shallow_copy

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

-- Weaken an expandability estimate by another expandability estimate.
function ExpandabilityEstimate:weaken_by(other, ...)
  self:weaken(other.maybe_fully_expandable, other.maybe_restricted_expandable, ...)
end

local ExpandabilityEstimates = {}

-- Create a new maximally-optimistic expandability estimate for the basic top-level expansion context, with the option to register
-- additional estimates for different expansion context types.
function ExpandabilityEstimates.new(cls)
  -- Instantiate the class.
  local self = {}
  setmetatable(self, cls)
  cls.__index = cls
  -- Initialize the class.
  self.basic_estimate = ExpandabilityEstimate:new()
  self.other_estimates = {}
  return self
end

-- Create an expandability estimate for a new expansion context type.
function ExpandabilityEstimates:_add_other_expansion_context_type(other_estimate_type)
  assert(self.other_estimates[other_estimate_type] == nil)
  self.other_estimates[other_estimate_type] = make_shallow_copy(self.basic_estimate)
  table.insert(self.other_estimates, other_estimate_type)
end

-- Weaken all expandability estimates when the reason applies to all expansion context types.
function ExpandabilityEstimates:weaken_all(...)
  self.basic_estimate:weaken(...)
  for _, other_estimate_type in ipairs(self.other_estimates) do
    local other_estimate = self.other_estimates[other_estimate_type]
    other_estimate:weaken(...)
  end
end

-- Weaken the expandability estimates for every expansion context type except the specified one.
function ExpandabilityEstimates:weaken_all_except(excluded_estimate_type, ...)
  if self.other_estimates[excluded_estimate_type] == nil then
    -- If it doesn't exist, create a new expandability estimate for the excluded expansion context type based on the estimate
    -- for the basic top-level expansion.
    self:_add_other_expansion_context_type(excluded_estimate_type)
  end
  assert(self.other_estimates[excluded_estimate_type] ~= nil)

  self.basic_estimate:weaken(...)
  for _, other_estimate_type in ipairs(self.other_estimates) do
    if other_estimate_type ~= excluded_estimate_type then
      local other_estimate = self.other_estimates[other_estimate_type]
      other_estimate:weaken(...)
    end
  end
end

-- Weaken all expandability estimates by another set of expandability estimates.
function ExpandabilityEstimates:weaken_by(other, ...)
  for _, other_estimate_type in ipairs(self.other_estimates) do
    -- For expansion context types that already exist here, just weaken the expandability estimate.
    local other_estimate = self.other_estimates[other_estimate_type]
    other_estimate:weaken_by(other:get_estimate(other_estimate_type), ...)
  end
  for _, other_estimate_type in ipairs(other.other_estimates) do
    if self.other_estimates[other_estimate_type] == nil then
      -- For expansion context types that only exist in the other set, create a new expandability estimate and then weaken it.
      self:_add_other_expansion_context_type(other_estimate_type)
      local other_estimate = self.other_estimates[other_estimate_type]
      other_estimate:weaken_by(other.other_estimates[other_estimate_type], ...)
    end
  end
  -- Weaken the estimate for the basic top-level expansion last, so that the previous new expandability estimates are still based
  -- on the more optimistic basic estimate.
  self.basic_estimate:weaken_by(other.basic_estimate, ...)
end

-- Get the expandability estimate for the specified expansion context type.
function ExpandabilityEstimates:get_estimate(estimate_type)
  if estimate_type == nil then
    -- When no expansion context type was specified, return the estimate for the basic top-level expansion.
    return self.basic_estimate
  end
  if self.other_estimates[estimate_type] == nil then
    -- If an estimate for the specified expansion context type doesn't exist, create a new expandability estimate for it based on
    -- the estimate for the basic top-level expansion.
    self:_add_other_expansion_context_type(estimate_type)
  end
  assert(self.other_estimates[estimate_type] ~= nil)
  return self.other_estimates[estimate_type]
end

-- Get the expansion context type with the most optimistic expandability estimate.
function ExpandabilityEstimates:get_most_optimistic_estimate()
  local best_estimate_type, best_estimate

  -- Update the most optimistic expandability estimate.
  local function update_best_estimate(other_estimate_type, other_estimate)
    if best_estimate == nil or
        (other_estimate.maybe_fully_expandable and not best_estimate.maybe_fully_expandable) or
        (other_estimate.maybe_restricted_expandable and not best_estimate.maybe_restricted_expandable)
    then
      best_estimate_type, best_estimate = other_estimate_type, other_estimate
    end
  end

  -- If the basic top-level expansion context is the most optimistic, return `nil` as the expansion context type.
  update_best_estimate(nil, self.basic_estimate)
  for _, other_estimate_type in ipairs(self.other_estimates) do
    local other_estimate = self.other_estimates[other_estimate_type]
    update_best_estimate(other_estimate_type, other_estimate)
  end
  assert(best_estimate ~= nil)
  return best_estimate_type, best_estimate
end

return {
  new_expandability = function()
    return ExpandabilityEstimates:new()
  end,
}
