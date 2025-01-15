-- The configuration for the static analyzer explcheck.

local toml = require("explcheck-toml")

-- The default options
local default_options = {
  expect_expl3_everywhere = false,
  max_line_length = 80,
  porcelain = false,
  warnings_are_errors = false,
  ignored_issues = {},
}

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

-- The user-defined configuration
local config_file = read_config_file(".explcheckrc")

-- The user-defined options, falling back on the default options
local options = {}
for _, template_options in ipairs({default_options, config_file.options or {}}) do
  for key, value in pairs(template_options) do
    options[key] = value
  end
end

return options
