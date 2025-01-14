-- Common functions used by different modules of the static analyzer explcheck.

local config = require("explcheck-config")

-- Get the value of an option or the default value if unspecified.
local function get_option(options, key)
  if options == nil or options[key] == nil then
    return config[key]
  end
  return options[key]
end

return {
  get_option = get_option,
}
