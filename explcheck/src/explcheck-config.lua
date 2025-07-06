-- The configuration for the static analyzer explcheck.

local toml = require("explcheck-toml")
local utils = require("explcheck-utils")

-- Read a TOML file with a user-defined configuration.
local function read_config_file(pathname)
  local file = io.open(pathname, "r")
  if file == nil then
    return nil
  end
  local content = assert(file:read("*a"))
  assert(file:close())
  return toml.parse(content)
end

-- Load the default configuration from the pre-installed config file `explcheck-config.toml`.
local default_config_pathname = string.sub(debug.getinfo(1).source, 2, (#".lua" + 1) * -1) .. ".toml"
local default_config = read_config_file(default_config_pathname)
assert(default_config ~= nil)

local user_configs = {}

-- Try to load user-defined configuration.
local function get_user_config(options)
  -- Read the configuration.
  local default_pathname, options_pathname
  default_pathname = default_config.defaults["config_file"]
  assert(default_pathname ~= nil)
  if options ~= nil and options["config_file"] ~= nil then
    options_pathname = options["config_file"]
  end
  -- Determine the pathname of the user-defined config file.
  local pathname, must_exist
  if options_pathname ~= nil then
    pathname = options_pathname
    if options_pathname ~= "" and options_pathname ~= default_pathname then
      must_exist = true  -- if the options specify a distinct pathname, it must exist
    end
  else
    pathname = default_pathname
    must_exist = false
  end
  assert(pathname ~= nil)
  -- Try to read the configuration.
  if user_configs[pathname] == nil then
    user_configs[pathname] = read_config_file(pathname)  -- only read the file from the disk once
  end
  if user_configs[pathname] == nil or user_configs[pathname] == false then
    if must_exist then
      error(string.format('Config file "%s" does not exist', pathname))
    end
    user_configs[pathname] = false  -- mark the file as read, so that we don't read it again
    return nil
  else
    return user_configs[pathname], pathname
  end
end

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
  -- Otherwise, try and load the user-defined configuration.
  local configs
  local user_config = get_user_config(options)
  if user_config ~= nil then
    configs = {user_config, default_config}
  else
    configs = {default_config}
  end
  -- Then, try the user-defined configuration first, if it exists, and then the default configuration.
  for _, config in ipairs(configs) do
    if pathname ~= nil then
      -- If a pathname is provided and the current configuration specifies the option for this filename, use it.
      local filename = get_filename(pathname)
      if config.filename ~= nil and config.filename[filename] ~= nil and config.filename[filename][key] ~= nil then
        return config.filename[filename][key]
      end
      -- If a pathname is provided and the current configuration specifies the option for this package, use it.
      local package = get_package(pathname)
      if config.package ~= nil and config.package[package] ~= nil and config.package[package][key] ~= nil then
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
  get_user_config = get_user_config,
}
