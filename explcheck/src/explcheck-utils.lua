-- Common functions used by different modules of the static analyzer explcheck.

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

-- Convert a pathname of a file to the suffix of the file.
local function get_suffix(pathname)
  return pathname:gsub(".*%.", "."):lower()
end

-- Convert a pathname of a file to the base name of the file.
local function get_basename(pathname)
  return pathname:gsub(".*[\\/]", "")
end

-- Convert a pathname of a file to the stem of the file.
local function get_stem(pathname)
  return get_basename(pathname):gsub("%..*", "")
end

-- Convert a pathname of a file to the pathname of its parent directory.
local function get_parent(pathname)
  if pathname:find("[\\/]") then
    return pathname:gsub("(.*)[\\/].*", "%1")
  else
    return "."
  end
end

-- Return all parameters unchanged, mostly used for no-op map-back and map-forward functions.
local function identity(...)
  return ...
end

-- Run all processing steps.
local function process_with_all_steps(pathname, content, issues, analysis_results, options)
  local get_option = require("explcheck-config").get_option
  local fail_fast = get_option('fail_fast', options, pathname)
  local stop_after = get_option('stop_after', options, pathname)
  local stop_early_when_confused = get_option('stop_early_when_confused', options, pathname)
  local step_filenames = {'preprocessing', 'lexical-analysis', 'syntactic-analysis', 'semantic-analysis'}
  for step_number, step_filename in ipairs(step_filenames) do
    local step = require(string.format('explcheck-%s', step_filename))
    -- If a processing step is confused, skip it and all following steps.
    if stop_early_when_confused then
      local is_confused, reason = step.is_confused(pathname, analysis_results, options)
      if is_confused then
        assert(reason ~= nil)
        analysis_results.stopped_early = {
          when = string.format("before %s", step.name),
          reason = reason,
        }
        break
      end
    end
    step.process(pathname, content, issues, analysis_results, options)
    -- If a processing step ended with error, skip all following steps.
    if fail_fast and #issues.errors > 0 then
      analysis_results.stopped_early = {
        when = string.format("after %s", step.name),
        reason = "it ended with errors and the option `fail_fast` was enabled",
      }
      break
    end
    -- If a processing step is supposed to be the last step, skip all following steps.
    if step_number < #step_filenames and (stop_after == step_filename or stop_after == step.name) then
      analysis_results.stopped_early = {
        when = string.format("after %s", step.name),
        reason = "it was the last step to run according to the option `stop_after`",
      }
      break
    end
  end
end

return {
  convert_byte_to_line_and_column = convert_byte_to_line_and_column,
  get_basename = get_basename,
  get_parent = get_parent,
  get_stem = get_stem,
  get_suffix = get_suffix,
  identity = identity,
  process_with_all_steps = process_with_all_steps,
}
