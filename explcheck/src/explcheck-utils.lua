-- Common functions used by different modules of the static analyzer explcheck.

local config = require("explcheck-config")

-- Convert a byte number in a file to a line and column number in a file.
local function convert_byte_to_line_and_column(line_starting_byte_numbers, byte_number)
  local line_number = 0
  for _, line_starting_byte_number in ipairs(line_starting_byte_numbers) do
    if line_starting_byte_number > byte_number then
      break
    end
    line_number = line_number + 1
  end
  assert(line_number > 0)
  local line_starting_byte_number = line_starting_byte_numbers[line_number]
  assert(line_starting_byte_number <= byte_number)
  local column_number = byte_number - line_starting_byte_number + 1
  return line_number, column_number
end

-- Get the value of an option or the default value if unspecified.
local function get_option(options, key)
  if options == nil or options[key] == nil then
    return config[key]
  end
  return options[key]
end

return {
  convert_byte_to_line_and_column = convert_byte_to_line_and_column,
  get_option = get_option,
}
