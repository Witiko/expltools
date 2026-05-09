-- The configuration for the static analyzer explcheck.

local toml = require("explcheck-toml")
local utils = require("explcheck-utils")

-- Parse TOML content with a user-defined configuration.
local function parse_config(content, pathname)
  local data, err = toml.parse(content)
  if err ~= nil then
    error(string.format('Parse error in "%s": %s', pathname or content, err))
  end
  return data
end

-- Read a TOML file with a user-defined configuration.
local function read_config_file(pathname)
  local file = io.open(pathname, "r")
  if file == nil then
    return nil
  end
  local content = assert(file:read("*a"))
  assert(file:close())
  return parse_config(content, pathname)
end

-- Load the default configuration from the pre-installed config file `explcheck-config.toml`.
local default_config_pathname = string.sub(debug.getinfo(1).source, 2, (#".lua" + 1) * -1) .. ".toml"
local default_config = assert(read_config_file(default_config_pathname))

local user_config_files, user_inline_configs = {}, {}

-- Try to load user-defined configuration files.
local function get_user_configs(options)
  -- Read the configuration.
  local default_pathnames, options_pathnames
  default_pathnames = default_config.defaults.config_files
  assert(default_pathnames ~= nil)
  -- TODO: Remove support for `config_file` in v1.0.0.
  if options ~= nil and (options.config_file ~= nil or options.config_files ~= nil) then
    if options.config_file ~= nil and options.config_files ~= nil then
      error('Conflicting options "config_file" (deprecated) and "config_files" were both specified')
    elseif options.config_file ~= nil then
      options_pathnames = options.config_file
    else
      assert(options.config_files ~= nil)
      options_pathnames = options.config_files
    end
  end
  -- Determine the pathnames of the user-defined config files.
  local pathnames, must_exist
  if options_pathnames ~= nil then
    pathnames = options_pathnames
    -- TODO: Remove support for `type(options_pathnames) == "string"` in v1.0.0.
    if type(options_pathnames) == "string" then
      local options_pathname = options_pathnames
      if options_pathname == "" then
        options_pathnames = {}
      else
        options_pathnames = {options_pathname}
      end
    end
    assert(type(options_pathnames) == "table")
    must_exist = true
  else
    pathnames = default_pathnames
    must_exist = false
  end
  assert(pathnames ~= nil)
  local effective_user_configs = {}
  local effective_config_pathnames_or_inline_contents = {}
  -- Try to read inline configurations.
  local inline_configs = options ~= nil and options.inline_configs ~= nil and options.inline_configs or {}
  for config_number = #inline_configs, 1, -1 do  -- read last-specified configurations first
    local content = options.inline_configs[config_number]
    if user_inline_configs[content] == nil then
      user_inline_configs[content] = parse_config(content)
    end
    table.insert(effective_user_configs, user_inline_configs[content])
    table.insert(effective_config_pathnames_or_inline_contents, content)
  end
  -- Try to read the configuration files.
  for pathname_number = #pathnames, 1, -1 do  -- read last-specified files first
    local pathname = pathnames[pathname_number]
    if user_config_files[pathname] == nil then
      user_config_files[pathname] = read_config_file(pathname)  -- only read the file from the disk once
    end
    if user_config_files[pathname] == nil or user_config_files[pathname] == false then
      if must_exist then
        error(string.format('Config file "%s" does not exist', pathname))
      end
      user_config_files[pathname] = false  -- mark the file as read, so that we don't read it again
    else
      table.insert(effective_user_configs, user_config_files[pathname])
      table.insert(effective_config_pathnames_or_inline_contents, pathname)
    end
  end
  assert(#effective_user_configs == #effective_config_pathnames_or_inline_contents)
  return effective_user_configs, effective_config_pathnames_or_inline_contents
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
  local configs, config_pathnames_or_inline_contents = get_user_configs(options)
  table.insert(configs, default_config)
  table.insert(config_pathnames_or_inline_contents, default_config_pathname)
  -- Then, try the user-defined configuration first, if it exists, and then the default configuration.
  for config_number, config in ipairs(configs) do
    local config_pathname_or_inline_content = config_pathnames_or_inline_contents[config_number]
    assert(config_pathname_or_inline_content ~= nil)
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
    local formatted_default_config_section_names_with_key, default_config_value = {}, nil
    for _, section_name in ipairs({"", "defaults", "options"}) do  -- TODO: Remove `[options]` in v1.0.0.
      local section = section_name == "" and config or config[section_name]
      if section ~= nil and section[key] ~= nil then
        local formatted_section_name = section_name == "" and "top level" or string.format('[%s]', section_name)
        table.insert(formatted_default_config_section_names_with_key, formatted_section_name)
        default_config_value = section[key]
      end
    end
    if #formatted_default_config_section_names_with_key > 0 then
      if #formatted_default_config_section_names_with_key > 1 then
        error(
          string.format(
            'Option "%s" was specified in several conflicting sections of "%s": %s',
            key,
            config_pathname_or_inline_content,
            table.concat(formatted_default_config_section_names_with_key, ", ")
          )
        )
      end
      assert(default_config_value ~= nil)
      return default_config_value
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
  get_user_configs = get_user_configs,
}
