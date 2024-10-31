local preprocessing = require("explcheck-preprocessing")
-- local lexical_analysis = require("explcheck-lexical-analysis")
-- local syntactic_analysis = require("explcheck-syntactic-analysis")
-- local semantic_analysis = require("explcheck-semantic-analysis")
-- local pseudo_flow_analysis = require("explcheck-pseudo-flow-analysis")

-- Transform a singular into plural if the count is zero or greater than two.
local function pluralize(singular, count)
  if count == 1 then
    return singular
  else
    return singular .. "s"
  end
end

-- Colorize a string using ASCII color codes.
local function colorize(text, ...)
  local buffer = {}
  for _, color_code in ipairs({...}) do
    table.insert(buffer, "\27[")
    table.insert(buffer, tostring(color_code))
    table.insert(buffer, "m")
  end
  table.insert(buffer, text)
  table.insert(buffer, "\27[0m")
  return table.concat(buffer, "")
end

-- Convert a byte number in a file to a line and column number in a file.
local function convert_byte_to_line_and_column(state, byte_number)
  local line_number = 0
  for _, line_starting_byte_number in ipairs(state.line_starting_byte_numbers) do
    if line_starting_byte_number > byte_number then
      break
    end
    line_number = line_number + 1
  end
  assert(line_number > 0)
  local line_starting_byte_number = state.line_starting_byte_numbers[line_number]
  assert(line_starting_byte_number <= byte_number)
  local column_number = byte_number - line_starting_byte_number + 1
  return line_number, column_number
end

-- Print warnings and errors after analyzing a file.
local function print_warnings_and_errors(state, is_last_file)
  -- Display an overview.
  local issues = {}
  if(#state.errors > 0) then
    io.write("\t\t" .. colorize(tostring(#state.errors) .. " " .. pluralize("error", #state.errors), 1, 31))
    table.insert(issues, state.errors)
    if(#state.warnings > 0) then
      io.write(", " .. colorize(tostring(#state.warnings) .. " " .. pluralize("warning", #state.warnings), 1, 33))
      table.insert(issues, state.warnings)
    end
  elseif(#state.warnings > 0) then
    io.write("\t\t" .. colorize(tostring(#state.warnings) .. " " .. pluralize("warning", #state.warnings), 1, 33))
    table.insert(issues, state.warnings)
  else
    io.write("\t\t" .. colorize("OK", 1, 32))
  end

  -- Display the errors, followed by warnings.
  if #issues > 0 then
    for _, warnings_or_errors in ipairs(issues) do
      print()
      -- Before display, copy and sort the warnings/errors using location as the primary key.
      local sorted_warnings_or_errors = {}
      for _, issue in ipairs(warnings_or_errors) do
        local code = issue[1]
        local message = issue[2]
        local range = issue[3]
        table.insert(sorted_warnings_or_errors, {code, message, range})
      end
      table.sort(sorted_warnings_or_errors, function(a, b)
        local a_code, b_code = a[1], b[1]
        local a_range, b_range = (a[3] and a[3][1]) or 0, (b[3] and b[3][1]) or 0
        return a_range < b_range or (a_range == b_range and a_code < b_code)
      end)
      -- Display the warnings/errors.
      for _, issue in ipairs(sorted_warnings_or_errors) do
        local code = issue[1]
        local message = issue[2]
        local range = issue[3]
        io.write("\n\t" .. state.filename)
        if range ~= nil then
          local line_number, column_number = convert_byte_to_line_and_column(state, range[1])
          io.write(":" .. tostring(line_number) .. ":" .. tostring(column_number))
        end
        io.write(":\t" .. code .. " " .. message)
      end
    end
    if(not is_last_file) then
      print()
    end
  end
end

-- Deduplicate filenames.
local function deduplicate_filenames(filenames)
  local deduplicated_filenames = {}
  local seen_filenames = {}
  for _, filename in ipairs(filenames) do
    if seen_filenames[filename] ~= nil then
      goto continue
    end
    seen_filenames[filename] = true
    table.insert(deduplicated_filenames, filename)
    ::continue::
  end
  return deduplicated_filenames
end

-- Process all input files.
local function main(filenames)
  local num_warnings = 0
  local num_errors = 0

  print("Checking " .. #filenames .. " files")

  for filename_number, filename in ipairs(filenames) do

    -- Load an input file.
    local file = assert(io.open(filename, "r"), "Could not open " .. filename .. " for reading")
    local content = assert(file:read("*a"))
    assert(file:close())
    local state = {
      filename = filename,
      content = content,
      warnings = {},
      errors = {},
    }

    -- Run all processing steps.
    io.write("\nChecking " .. filename)
    preprocessing(state)
    if #state.errors > 0 then
      goto continue
    end
    -- lexical_analysis(state)
    -- syntactic_analysis(state)
    -- semantic_analysis(state)
    -- pseudo_flow_analysis(state)

    -- Print warnings and errors.
    ::continue::
    num_warnings = num_warnings + #state.warnings
    num_errors = num_errors + #state.errors
    print_warnings_and_errors(state, filename_number == #filenames)
  end

  -- Print a summary.
  io.write("\n\nTotal: ")

  local errors_message = tostring(num_errors) .. " " .. pluralize("error", num_errors)
  errors_message = colorize(errors_message, 1, (num_errors > 0 and 31) or 32)
  io.write(errors_message .. ", ")

  local warnings_message = tostring(num_warnings) .. " " .. pluralize("warning", num_warnings)
  warnings_message = colorize(warnings_message, 1, (num_warnings > 0 and 33) or 32)
  io.write(warnings_message .. " in ")

  print(tostring(#filenames) .. " " .. pluralize("file", #filenames))

  if(num_errors > 0) then
    os.exit(1)
  end
end

if #arg == 0 then
  print("Usage: " .. arg[0] .. " FILENAMES")
else
  local filenames = deduplicate_filenames(arg)
  main(filenames)
end
