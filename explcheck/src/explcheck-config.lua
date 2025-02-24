-- The configuration for the static analyzer explcheck.

local toml = require("explcheck-toml")

-- Read a TOML file with a user-defined configuration.
local function read_config_file(pathname)
  local file = io.open(pathname, "r")
  if file == nil then
    return {}
  end
  local content = assert(file:read("*a"))
  assert(file:close())
  return toml.parse(content)
end

-- The default configuration from file explcheck-config.toml
local default_config_pathname = string.sub(debug.getinfo(1).source, 2, (#".lua" + 1) * -1) .. ".toml"
local default_config = read_config_file(default_config_pathname)

-- The user-defined configuration from file ./.explcheckrc
local user_config = read_config_file(".explcheckrc")

-- The user-defined options, falling back on the default options
local options = {}
for _, defaults in ipairs({default_config.defaults, user_config.defaults}) do
  for key, value in pairs(defaults) do
    options[key] = value
  end
end

return options
