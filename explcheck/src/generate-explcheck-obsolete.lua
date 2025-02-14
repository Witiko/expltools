#!/usr/bin/env texlua
-- Generates a file with up-to-date LPEG parsers for checking whether the name
-- of a standard expl3 function/variable is obsolete.

local kpse = require("kpse")
kpse.set_program_name("texlua", "generate-explcheck-obsolete")

local lpeg = require("lpeg")
local C, Ct, Cs, P = lpeg.C, lpeg.Ct, lpeg.Cs, lpeg.P

-- Extract the obsolete functions/variables from file "explcheck-obsolete.lua".
local input_filename = assert(kpse.find_file("l3obsolete.txt", "TeX system documentation"))
local input_file = assert(io.open(input_filename, "r"), "Could not open " .. input_filename .. " for writing")
local line, input_state, csnames = input_file:read("*line"), "preamble", {}
while line ~= nil do
  if input_state == "preamble" and line == "Deprecated functions and variables" then
    input_state = "deprecated"
  elseif input_state == "deprecated" and line == "Removed functions and variables" then
    input_state = "removed"
  elseif input_state == "deprecated" and line:sub(1, 1) == [[\]] then
    local _, _, csname = line:find([[\(%S*)]])
    if csnames[input_state] == nil then
      csnames[input_state] = {}
    end
    table.insert(csnames[input_state], csname)
  end
  line = input_file:read("*line")
end
assert(input_file:close())

-- Generate the file "explcheck-obsolete.lua".
local output_filename = "explcheck-obsolete.lua"
local output_file = assert(io.open(output_filename, "w"), "Could not open " .. output_filename .. " for writing")

---- Generate the preamble.
output_file:write(
  "-- LPEG parsers for checking whether the name of a standard expl3 function/variable is obsolete.\n\n"
)

---- Generate the LPEG parsers.
output_file:write('local lpeg = require("lpeg")\n')
output_file:write('local P = lpeg.P\n\n')
output_file:write('local eof = P(-1)\n')
output_file:write('local regular_character = P(1)\n')
output_file:write('local wildcard = regular_character^0\n\n')

------ In order to minimize the size and speed of the parsers, we will first
------ construct prefix trees of the obsolete functions/variables.
local input_wildcard = P("...")
local input_regular_character = P(1)
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
local prefix_trees = {}
for csname_type, csname_list in pairs(csnames) do
  prefix_trees[csname_type] = {}
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

------ Finally, we will generate LPEG parsers out of the prefix trees.
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

local output_wildcard = P("wildcard")
local output_regular_character = P(1) - P('"')
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
  simplified_output_regular_characters
  * (
    output_wildcard^1
    * simplified_output_regular_characters
  )^0
  *P(-1)
)

output_file:write('-- luacheck: push no max line length\n')
output_file:write('local obsolete = {}\n')
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
      output_file:write('obsolete.' .. csname_type .. '_csname = (' .. subparsers[path] .. ') * eof\n')
    end
  end)
end
output_file:write('-- luacheck: pop\n\n')
output_file:write('return obsolete\n')

assert(output_file:close())
