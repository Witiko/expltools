-- The configuration for the static analyzer explcheck.

local toml = require("explcheck-toml")
local utils = require("explcheck-utils")

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

-- Load the default configuration from the pre-installed config file `explcheck-config.toml`.
local default_config_pathname = string.sub(debug.getinfo(1).source, 2, (#".lua" + 1) * -1) .. ".toml"
local default_config = read_config_file(default_config_pathname)

-- Load the user-defined configuration from the config file .explcheckrc (if it exists).
local user_config = read_config_file(".explcheckrc")

-- Get the value of an option.
local function get_option(key, options, pathname)
  -- If a table of options is provided and the option is specified there, use it.
  if options ~= nil and options[key] ~= nil then
    return options[key]
  end
  -- Otherwise, try the user-defined configuration first, if it exists, and then the default configuration.
  for _, config in ipairs({user_config, default_config}) do
    if pathname ~= nil then
      -- If a a pathname is provided and the current configuration specifies the option for the provided filename, use it.
      local filename = utils.get_basename(pathname)
      if config["filename"] and config["filename"][filename] ~= nil and config["filename"][filename][key] ~= nil then
        return config["filename"][filename][key]
      end
    end
    -- If the current configuration specifies the option in the defaults, use it.
    if config["defaults"] ~= nil and config["defaults"][key] ~= nil then
      return config["defaults"][key]
    end
  end
  error('Failed to get a value for option "' .. key .. '"')
end

return get_option
