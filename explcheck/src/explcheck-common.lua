-- Transform a filename into a state object that can be passed to the processing steps.
local function initialize_state(filename)
  local file = assert(io.open(filename, "r"), "Could not open " .. filename .. " for reading")
  local content = assert(file:read("*a"))
  assert(file:close())
  local state = {
    filename = filename,
    content = content,
    warnings = {},
    errors = {},
  }
  return state
end

return {
  initialize_state = initialize_state
}
