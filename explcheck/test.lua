-- A testing framework for the static analyzer explcheck.

local lfs = require("lfs")

-- Convert a pathname of a file to the base name of the file.
local function get_basename(pathname)
  return pathname:gsub(".*[\\/]", "")
end

-- Convert a pathname of a file to the stem of the file.
local function get_stem(pathname)
  return get_basename(pathname):gsub("%..*", "")
end

-- Convert a pathname of a file to the suffix of the file.
local function get_suffix(pathname)
  return pathname:gsub(".*%.", "."):lower()
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
  local tex_test_files, lua_test_files = {}, {}
  local seen_lua_stems = {}
  for _, filename in ipairs(test_files) do
    if get_suffix(filename):lower() == ".lua" then
      lua_test_files[filename] = true
      seen_lua_stems[get_stem(filename)] = true
    elseif get_suffix(filename):lower() == ".tex" then
      tex_test_files[filename] = true
    end
    assert(lfs.link(filename, test_directory .. "/" .. get_basename(filename)))
  end
  local main_test_files = {}
  for _, filename in ipairs(test_files) do
    -- Determine the main test files: Either Lua files or TeX files with no associated Lua files.
    if lua_test_files[filename] or (tex_test_files[filename] and not seen_lua_stems[get_stem(filename)]) then
      table.insert(main_test_files, filename)
    end
  end
  table.sort(main_test_files, function(a, b)
    local a_number, b_number = tonumber(get_basename(a):sub(2, 4)), tonumber(get_basename(b):sub(2, 4))
    if a_number ~= nil and b_number ~= nil and a_number ~= b_number then
      return a_number < b_number
    elseif a_number == nil and b_number ~= nil then
      return false
    elseif a_number ~= nil and b_number == nil then
      return true
    else
      return get_stem(a) < get_stem(b)
    end
  end)

  -- Run the tests.
  local previous_directory = assert(lfs.currentdir())
  assert(lfs.chdir(test_directory))
  print("Running " .. #main_test_files .. " tests\n")
  local num_errors = 0
  for _, filename in ipairs(main_test_files) do
    local basename = get_basename(filename)
    io.write("Checking " .. basename)
    local check_function
    if tex_test_files[filename] then
      -- A TeX file with no associated Lua file. Check it and see if any issues were detected.
      assert(seen_lua_stems[get_stem(filename)] == nil)
      check_function = function()
        local options = {ignored_issues = {'w100'}}
        local issues = require("explcheck-issues")(filename, options)
        local file = assert(io.open(basename, "r"))
        local content = assert(file:read("*a"))
        assert(file:close())
        local analysis_results = {}
        require("explcheck-utils").process_with_all_steps(filename, content, issues, analysis_results, options)
        assert(#issues.warnings == 0)
        assert(#issues.errors == 0)
      end
    else
      -- A Lua file with a complex test, run it.
      assert(lua_test_files[filename])
      check_function = function()
        dofile(basename)
      end
    end
    local ran_ok, err = pcall(check_function)
    if ran_ok then
      print("\t" .. colorize("OK", 1, 32))
    else
      print("\t" .. colorize(err, 1, 31))
      num_errors = num_errors + 1
    end
  end
  assert(lfs.chdir(previous_directory))

  -- Print a summary.
  io.write("\nTotal: ")

  local errors_message = tostring(num_errors) .. " " .. pluralize("error", num_errors)
  errors_message = colorize(errors_message, 1, (num_errors > 0 and 31) or 32)
  io.write(errors_message .. " in ")

  print(tostring(#main_test_files) .. " " .. pluralize("file", #main_test_files))

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
