#!/usr/bin/env texlua
-- Generates a file with up-to-date LPEG parsers and other information extracted from LaTeX3 data files.

local kpse = require("kpse")
kpse.set_program_name("texlua", "generate-explcheck-latex3")

local lpeg = require("lpeg")
local C, Ct, Cs, P, R, S = lpeg.C, lpeg.Ct, lpeg.Cs, lpeg.P, lpeg.R, lpeg.S
local any, eof = P(1), P(-1)

-- Perform a depth-first-search algorithm on a tree.
local function depth_first_search(node, path, visit, leave)
  visit(node, path)
  for label, child in pairs(node) do  -- intermediate node
    if type(child) == "table" then
      depth_first_search(child, path .. label, visit, leave)
    end
  end
  for _, child in pairs(node) do  -- leaf node
    if type(child) ~= "table" then
      visit(child, path)
    end
  end
  leave(node, path)
end

-- Extract obsolete control sequence names from file "l3obsolete.txt".
local function parse_l3obsolete()
  local latest_date, csnames, dates = nil, {}, {}
  local input_filename = "l3obsolete.txt"
  local input_pathname = assert(kpse.find_file(input_filename, "TeX system documentation") or input_filename)
  local input_file = assert(io.open(input_pathname, "r"), "Could not open " .. input_pathname .. " for reading")
  local line, input_state, seen_csnames = input_file:read("*line"), "preamble", {}
  while line ~= nil do
    if input_state == "preamble" and line == "Deprecated functions and variables" then
      input_state = "deprecated"
    elseif input_state == "deprecated" and line == "Removed functions and variables" then
      input_state = "removed"
    elseif input_state == "deprecated" and line:sub(1, 1) == [[\]] then
      local _, _, date = line:find("(%d%d%d%d%-%d%d%-%d%d)%s*$")
      assert(date ~= nil, string.format('Failed to parse date out of line "%s"', line))
      if latest_date == nil or date > latest_date then
        latest_date = date
      end
      local _, _, raw_csname = line:find([[\(%S*)]])
      local extracted_csnames = {raw_csname}
      -- Try to determine the base form for conditional function names, so that occurences in calls like
      -- `\prg_generate_conditional_variant:Nnn` are also detected even without semantic analysis.
      local _, _, csname_stem, argument_specifiers = raw_csname:find("([^:]*):([^:]*)")
      if csname_stem ~= nil then
        if argument_specifiers:sub(-2) == "TF" then
          table.insert(extracted_csnames, string.format("%s:%s", csname_stem, argument_specifiers:sub(1, -3)))
        elseif argument_specifiers:sub(-1) == "T" or raw_csname:sub(-1) == "F" then
          table.insert(extracted_csnames, string.format("%s:%s", csname_stem, argument_specifiers:sub(1, -2)))
        elseif csname_stem:sub(-2) == "_p" then
          table.insert(extracted_csnames, string.format("%s:%s", csname_stem:sub(1, -3), argument_specifiers))
        end
      end
      if csnames[input_state] == nil then
        csnames[input_state] = {}
        dates[input_state] = {}
        seen_csnames[input_state] = {}
      end
      for _, csname in ipairs(extracted_csnames) do
        if seen_csnames[input_state][csname] == nil then
          table.insert(csnames[input_state], csname)
          dates[input_state][csname] = date
          seen_csnames[input_state][csname] = true
        end
      end
    end
    line = input_file:read("*line")
  end
  assert(input_file:close())
  assert(latest_date ~= nil)
  return csnames, dates, latest_date
end

-- Generate LPEG parsers of obsolete control sequence names from file "l3obsolete.txt".
local function generate_l3obsolete_parsers(output_file, dates, csnames)
  -- First, generate some variable names that the parsers will use.
  output_file:write('local obsolete = {}\n')
  output_file:write('do\n')
  output_file:write('  local any, eof = P(1), P(-1)\n')
  output_file:write('  local wildcard = any^0  -- luacheck: ignore wildcard\n\n')

  -- In order to minimize the size and speed of the parsers, first construct prefix trees of the obsolete names.
  local input_wildcard = P("...")
  local input_regular_character = any
  local csname_characters = Ct(
    (
      input_wildcard
      / function()  -- a wildcard
        return " "
      end
      + C(input_regular_character)
      / function(character)  -- a regular character
        return character
      end
    )^0
  )
  local prefix_trees, num_prefix_trees = {}, 0
  for csname_type, csname_list in pairs(csnames) do
    prefix_trees[csname_type] = {}
    num_prefix_trees = num_prefix_trees + 1
    for _, csname in ipairs(csname_list) do
      local node = prefix_trees[csname_type]
      local characters = lpeg.match(csname_characters, csname)
      for character_index, character in ipairs(characters) do
        if character_index < #characters then  -- an intermediate node
          if node[character] == nil then
            node[character] = {}
          end
          node = node[character]
        else  -- a leaf node
          table.insert(node, character)
        end
      end
    end
  end

  -- Finally, generate parsers out of the trees.
  local output_wildcard = P("wildcard")
  local output_regular_character = any - P('"')
  local output_date = P(' / "') * R("09") * R("09") * R("09") * R("09") * P("-") * R("09") * R("09") * P("-") * R("09") * R("09") * P('"')
  local output_regular_characters = (
    P('P("')
    * C(output_regular_character^1)
    * P('")')
  )
  local simplified_output_regular_characters = (
    Ct(
      output_regular_characters
      * (
        P(' * ')
        * output_regular_characters
      )^0
    )
    / function(accumulator)
      return 'P("' .. table.concat(accumulator, "") .. '")'
    end
  )
  local simplified_output_parsers = Cs(
    (
      output_wildcard
      + output_date
      + simplified_output_regular_characters
    )^0
    * eof
  )

  output_file:write('  -- luacheck: push no max line length\n')
  local produced_parsers = 0
  for csname_type, prefix_tree in pairs(prefix_trees) do
    local subparsers = {}
    depth_first_search(prefix_tree, "", function(node, path)  -- visit
      if type(node) == "string" then  -- leaf node
        local suffix
        if node == " " then  -- wildcard
          suffix = "wildcard"
        else
          assert(node ~= '"')
          suffix = 'P("' .. node .. '")'
        end
        local maybe_date = dates[csname_type][path .. node]
        if maybe_date ~= nil then
          suffix = suffix .. ' / "' .. maybe_date .. '"'
        end
        if subparsers[path] ~= nil then
          subparsers[path] = subparsers[path] .. " + " .. suffix
        else
          subparsers[path] = suffix
        end
      end
    end, function(_, path)  -- leave
      if #path > 0 then  -- non-root node
        local character = path:sub(#path, #path)
        local parent_path = path:sub(1, #path - 1)
        local prefix
        if character == " " then  -- wildcard
          prefix = "wildcard"
        else
          assert(character ~= '"')
          prefix = 'P("' .. character .. '")'
        end
        local simplified_pattern = lpeg.match(simplified_output_parsers, subparsers[path])
        local suffix
        if simplified_pattern ~= nil then  -- simple pattern
          suffix = prefix .. " * " .. simplified_pattern
          local simplified_suffix = lpeg.match(simplified_output_parsers, suffix)
          if simplified_suffix ~= nil then
            suffix = simplified_suffix
          end
        else  -- complex pattern
          suffix = prefix .. " * (" .. subparsers[path] .. ")"
        end
        if subparsers[parent_path] ~= nil then
          subparsers[parent_path] = subparsers[parent_path] .. " + " .. suffix
        else
          subparsers[parent_path] = suffix
        end
      else  -- root node
        output_file:write('  obsolete.' .. csname_type .. '_csname = (' .. subparsers[path] .. ') * eof\n')
        produced_parsers = produced_parsers + 1
      end
    end)
  end
  output_file:write('  -- luacheck: pop\n')
  output_file:write('end\n')
  assert(produced_parsers == num_prefix_trees)
end

-- Extract registered module names from file "l3prefixes.csv".
local function parse_l3prefixes()
  local latest_date, prefixes, dates = nil, {}, {}
  local input_filename = "l3prefixes.csv"
  local input_pathname = assert(kpse.find_file(input_filename, "TeX system documentation") or input_filename)
  local input_file = assert(io.open(input_pathname, "r"), "Could not open " .. input_pathname .. " for reading")
  local csv_field = (
    '"' * Cs(((any - P('"')) + P('""') / '"')^0) * '"'  -- quoted field
    + C((any - S(',\n"'))^0)  -- unquoted field
  )
  local csv_fields = Ct(csv_field * (P(",") * csv_field)^0) * (lpeg.P("\n") + eof)
  input_file:read("*line")  -- skip the header on the first line
  for line in input_file:lines() do
    local values = lpeg.match(csv_fields, line)
    assert(#values == 9)
    local prefix, date = values[1], values[7]
    if date:find("(%d%d%d%d%-%d%d%-%d%d)$") == nil then
      print(string.format('Failed to parse date out of line "%s", skipping it in determining the latest registered prefix', line))
    elseif latest_date == nil or date > latest_date then
      latest_date = date
    end
    table.insert(prefixes, prefix)
    if date ~= nil and (dates[prefix] == nil or dates[prefix] > date) then  -- only record earliest first registered prefix for duplicates
      dates[prefix] = date
    end
  end
  assert(latest_date ~= nil)
  return prefixes, dates, latest_date
end

-- Generate an LPEG parser of registered module names from file "l3prefixes.csv".
local function generate_l3prefixes_parser(output_file, dates, prefixes)
  -- In order to minimize the size and speed of the parser, first construct a prefix tree of the prefixes.
  local prefix_tree = {}
  for _, prefix in ipairs(prefixes) do
    local node = prefix_tree
    for character_index = 1, #prefix do
      local character = prefix:sub(character_index, character_index)
      assert(#character == 1)
      if character_index < #prefix then  -- an intermediate node
        if node[character] == nil then
          node[character] = {}
        end
        node = node[character]
      else  -- a leaf node
        table.insert(node, character)
      end
    end
  end

  -- Finally, generate a parser out of the tree.
  local output_regular_character = any - P('"')
  local output_date = P(' / "') * R("09") * R("09") * R("09") * R("09") * P("-") * R("09") * R("09") * P("-") * R("09") * R("09") * P('"')
  local output_regular_characters = (
    P('P("')
    * C(output_regular_character^1)
    * P('")')
  )
  local simplified_output_regular_characters = (
    Ct(
      output_regular_characters
      * (
        P(' * ')
        * output_regular_characters
      )^0
    )
    / function(accumulator)
      return 'P("' .. table.concat(accumulator, "") .. '")'
    end
  )
  local simplified_output_parsers = Cs(
    (
      output_date
      + simplified_output_regular_characters
    )^0
    * eof
  )

  output_file:write('-- luacheck: push no max line length\n')
  local subparsers = {}
  local produced_parsers = 0
  depth_first_search(prefix_tree, "", function(node, path)  -- visit
    if type(node) == "string" then  -- leaf node
      local suffix
      assert(node ~= '"')
      suffix = 'P("' .. node .. '")'
      local maybe_date = dates[path .. node]
      if maybe_date ~= nil then
        suffix = suffix .. ' / "' .. maybe_date .. '"'
      end
      if subparsers[path] ~= nil then
        subparsers[path] = subparsers[path] .. " + " .. suffix
      else
        subparsers[path] = suffix
      end
    end
  end, function(_, path)  -- leave
    if #path > 0 then  -- non-root node
      local character = path:sub(#path, #path)
      local parent_path = path:sub(1, #path - 1)
      local prefix
      assert(character ~= '"')
      prefix = 'P("' .. character .. '")'
      local simplified_pattern = lpeg.match(simplified_output_parsers, subparsers[path])
      local suffix
      if simplified_pattern ~= nil then  -- simple pattern
        suffix = prefix .. " * " .. simplified_pattern
        local simplified_suffix = lpeg.match(simplified_output_parsers, suffix)
        if simplified_suffix ~= nil then
          suffix = simplified_suffix
        end
      else  -- complex pattern
        suffix = prefix .. " * (" .. subparsers[path] .. ")"
      end
      if subparsers[parent_path] ~= nil then
        subparsers[parent_path] = subparsers[parent_path] .. " + " .. suffix
      else
        subparsers[parent_path] = suffix
      end
    else  -- root node
      output_file:write('local prefixes = (' .. subparsers[path] .. ')\n')
      produced_parsers = produced_parsers + 1
    end
  end)
  output_file:write('-- luacheck: pop\n')
  assert(produced_parsers == 1)
end

-- Add a comment, both to an output file and to the standard output.
local function add_comment(output_file, text)
  print(text)
  output_file:write(string.format("-- %s\n", text))
end

-- Generate the file "explcheck-latex3.lua".
local output_filename = "explcheck-latex3.lua"
local output_file = assert(io.open(output_filename, "w"), "Could not open " .. output_filename .. " for writing")

---- Generate the preamble.
add_comment(output_file, "LPEG parsers and other information extracted from LaTeX3 data files.")
add_comment(output_file, string.format("Generated on %s from the following files:", os.date("%Y-%m-%d")))
local csnames, l3obsolete_dates, l3obsolete_latest_date = parse_l3obsolete()
add_comment(output_file, string.format('- "l3obsolete.txt" with the latest obsolete entry from %s', l3obsolete_latest_date))
local prefixes, l3prefixes_dates, l3prefixes_latest_date = parse_l3prefixes()
add_comment(output_file, string.format('- "l3prefixes.csv" with the latest registered prefix from %s', l3prefixes_latest_date))
output_file:write("\n")

---- Generate the LPEG parsers.
output_file:write('local lpeg = require("lpeg")\n')
output_file:write('local P = lpeg.P\n\n')
generate_l3obsolete_parsers(output_file, l3obsolete_dates, csnames)
output_file:write("\n")
generate_l3prefixes_parser(output_file, l3prefixes_dates, prefixes)
output_file:write([[

return {
  obsolete = obsolete,
  prefixes = prefixes
}
]])
assert(output_file:close())
