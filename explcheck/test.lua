-- A testing framework for the static analyzer explcheck.

local lfs = require("lfs")

-- Convert a pathname of a file to the base name of a file.
local function get_basename(filename)
  return filename:gsub(".+/", "")
end

-- Convert a pathname of a file to the suffix of a file.
local function get_suffix(filename)
  return filename:gsub(".*%.", ".")
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

-- Run the tests.
local function run_tests(test_directory, support_files, test_files)
  -- Create the test directory and copy support files and testfiles to it.
  assert(lfs.mkdir(test_directory))
  for _, filename in ipairs(support_files) do
    assert(lfs.link(filename, test_directory .. "/" .. get_basename(filename)))
  end
  local lua_test_files = {}
  for _, filename in ipairs(test_files) do
    if get_suffix(filename):lower() == ".lua" then
      table.insert(lua_test_files, filename)
    end
    assert(lfs.link(filename, test_directory .. "/" .. get_basename(filename)))
  end

  -- Run the tests.
  local previous_directory = assert(lfs.currentdir())
  assert(lfs.chdir(test_directory))
  print("Running " .. #lua_test_files .. " tests\n")
  local num_errors = 0
  for _, filename in ipairs(lua_test_files) do
    local basename = get_basename(filename)
    io.write("Checking " .. test_directory .. "/" .. basename)
    local ran_ok, err = pcall(function()
      dofile(basename)
    end)
    if ran_ok then
      print("\t\t" .. colorize("OK", 1, 32))
    else
      print("\t\t" .. colorize(err, 1, 31))
      num_errors = num_errors + 1
    end
  end
  assert(lfs.chdir(previous_directory))

  -- Print a summary.
  io.write("\nTotal: ")

  local errors_message = tostring(num_errors) .. " " .. pluralize("error", num_errors)
  errors_message = colorize(errors_message, 1, (num_errors > 0 and 31) or 32)
  io.write(errors_message .. " in ")

  print(tostring(#lua_test_files) .. " " .. pluralize("file", #lua_test_files))

  -- Remove the test directory if none of the tests failed.
  if num_errors == 0 then
    for _, filename in ipairs(support_files) do
      assert(os.remove(test_directory .. "/" .. get_basename(filename)))
    end
    for _, filename in ipairs(test_files) do
      assert(os.remove(test_directory .. "/" .. get_basename(filename)))
    end
    assert(lfs.rmdir(test_directory))
  else
    return false
  end
  return true
end

return run_tests
