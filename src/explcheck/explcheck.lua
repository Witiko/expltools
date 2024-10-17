local preprocessing = require("explcheck-preprocessing")
-- local lexical_analysis = require("explcheck-lexical-analysis")
-- local syntactic_analysis = require("explcheck-syntactic-analysis")
-- local semantic_analysis = require("explcheck-semantic-analysis")
-- local pseudo_flow_analysis = require("explcheck-pseudo-flow-analysis")

-- Count the number of items in a table.
local function count_items(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

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

-- Print warnings and errors after analyzing a file.
local function print_warnings_and_errors(state)
  -- Display an overview.
  local issues = {}
  if(#state.errors > 0) then
    io.write("\t\t" .. colorize(tostring(#state.errors) .. " " .. pluralize("error", #state.errors), 1, 31))
    table.insert(issues, state.errors)
    if(#state.warnings > 0) then
      print(", " .. colorize(tostring(#state.warnings) .. " " .. pluralize("warning", #state.warnings), 1, 33))
      table.insert(issues, state.warnings)
    end
  elseif(#state.warnings > 0) then
    print("\t\t" .. colorize(tostring(#state.warnings) .. " " .. pluralize("warning", #state.warnings), 1, 33))
    table.insert(issues, state.warnings)
  else
    print("\t\t" .. colorize("OK", 1, 32))
  end
  
  -- Display the errors, followed by warnings.
  if #issues > 0 then
    print()
    for _, warnings_or_errors in ipairs(issues) do
      for _, issue in ipairs(warnings_or_errors) do
        local code = issue[1]
        local message = issue[2]
        local range = issue[3]
        io.write("\t" .. state.filename)
        if range ~= nil then
          io.write(":" .. tostring(range[1]))  -- TODO: Convert starting byte number to line and character number.
        end
        print(":\t" .. code .. " " .. message)
      end
      print()
    end
  end
end

-- Process all input files.
local function main(filenames)
  local num_warnings = 0
  local num_errors = 0

  print("Checking " .. #filenames .. " files\n")

  for _, filename in ipairs(filenames) do

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
    io.write("Checking " .. filename)
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
    print_warnings_and_errors(state)
  end

  -- Print a summary.
  io.write("\nTotal: ")

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

main(arg)