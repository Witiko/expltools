-- Transform a filename into a state object that can be passed to the processing steps.
local function initialize_state()
  local state = {
    warnings = {},
    errors = {},
  }
  return state
end

return {
  initialize_state = initialize_state
}
