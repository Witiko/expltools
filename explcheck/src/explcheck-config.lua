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
local user_config_pathname = ".explcheckrc"
local user_config = read_config_file(user_config_pathname)

-- Get the filename of a file.
local function get_filename(pathname)
  return utils.get_basename(pathname)
end

-- Get the package name of a file.
local function get_package(pathname)
  return utils.get_basename(utils.get_parent(pathname))
end

-- Get the value of an option.
local function get_option(key, options, pathname)
  -- If a table of options is provided and the option is specified there, use it.
  if options ~= nil and options[key] ~= nil then
    return options[key]
  end
  -- Otherwise, try the user-defined configuration first, if it exists, and then the default configuration.
  for _, config in ipairs({user_config, default_config}) do
    if pathname ~= nil then
      -- If a pathname is provided and the current configuration specifies the option for this filename, use it.
      local filename = get_filename(pathname)
      if config.filename and config.filename[filename] ~= nil and config.filename[filename][key] ~= nil then
        return config.filename[filename][key]
      end
      -- If a pathname is provided and the current configuration specifies the option for this package, use it.
      local package = get_package(pathname)
      if config.package and config.package[package] ~= nil and config.package[package][key] ~= nil then
        return config.package[package][key]
      end
    end
    -- If the current configuration specifies the option in the defaults, use it.
    for _, section in ipairs({"defaults", "options"}) do  -- TODO: Remove `[options]` in v1.0.0.
      if config[section] ~= nil and config[section][key] ~= nil then
        return config[section][key]
      end
    end
  end
  error('Failed to get a value for option "' .. key .. '"')
end

return {
  default_config = default_config,
  default_config_pathname = default_config_pathname,
  get_filename = get_filename,
  get_option = get_option,
  get_package = get_package,
  user_config = user_config,
  user_config_pathname = user_config_pathname,
}
