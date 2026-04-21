#!/usr/bin/env texlua
-- Generates a file with up-to-date LPEG parsers and other information extracted from LaTeX3 data files.

local format = require("explcheck-format")
local get_basename = require("explcheck-utils").get_basename

local humanize = format.humanize
local pluralize = format.pluralize

local lfs = require("lfs")

local lpeg = require("lpeg")
local C, Cc, Ct, Cs, P, R, S = lpeg.C, lpeg.Cc, lpeg.Ct, lpeg.Cs, lpeg.P, lpeg.R, lpeg.S
local any, eof = P(1), P(-1)

local LATEX3_PATHNAME = "../../third-party/latex3"

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
  local latest_date, latest_raw_csname, csnames, dates = nil, nil, {}, {}
  local input_pathname = string.format("%s/l3kernel/doc/l3obsolete.txt", LATEX3_PATHNAME)
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
      local _, _, raw_csname = line:find([[\(%S*)]])
      if latest_date == nil or date > latest_date then
        latest_date = date
        latest_raw_csname = raw_csname
      end
      local extracted_csnames = {raw_csname}
      -- Try to determine the base form for conditional function names, so that occurences in calls like
      -- `\prg_generate_conditional_variant:Nnn` are also detected even without semantic analysis.
      local csname_stem, argument_specifiers = raw_csname:match("([^:]*):([^:]*)")
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
  assert(latest_raw_csname ~= nil)
  return csnames, dates, latest_date, latest_raw_csname
end

-- Generate LPEG parsers of obsolete control sequence names from file "l3obsolete.txt".
local function generate_l3obsolete_parsers(output_file, dates, csnames)
  -- First, generate some variable names that the parsers will use.
  output_file:write('M.obsolete = {}\n')
  output_file:write('do\n')
  output_file:write('  local any, eof = P(1), P(-1)\n')
  output_file:write('  ---@diagnostic disable-next-line:unused-local\n')
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
        output_file:write('  M.obsolete.' .. csname_type .. '_csname = (' .. subparsers[path] .. ') * eof\n')
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
  local latest_date, latest_prefix, prefixes, dates = nil, nil, {}, {}
  local input_pathname = string.format("%s/l3kernel/doc/l3prefixes.csv", LATEX3_PATHNAME)
  local input_file = assert(io.open(input_pathname, "r"), "Could not open " .. input_pathname .. " for reading")
  local csv_field = (
    '"' * Cs(((any - P('"')) + P('""') / '"')^0) * '"'  -- quoted field
    + C((any - S(',\n"'))^0)  -- unquoted field
  )
  local csv_fields = Ct(csv_field * (P(",") * csv_field)^0) * (lpeg.P("\n") + eof)
  local _ = input_file:read("*line")  -- skip the header on the first line
  for line in input_file:lines() do
    local values = lpeg.match(csv_fields, line)
    assert(#values == 9)
    local prefix, date = values[1], values[7]
    if date:find("(%d%d%d%d%-%d%d%-%d%d)$") == nil then
      print(string.format('Failed to parse date out of line "%s", skipping it in determining the latest registered prefix', line))
    elseif latest_date == nil or date > latest_date then
      latest_date, latest_prefix = date, prefix
    end
    table.insert(prefixes, prefix)
    if date ~= nil and (dates[prefix] == nil or dates[prefix] > date) then  -- only record earliest first registered prefix for duplicates
      dates[prefix] = date
    end
  end
  assert(latest_date ~= nil)
  assert(latest_prefix ~= nil)
  return prefixes, dates, latest_date, latest_prefix
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

  -- Then, generate a parser out of the tree.
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
      output_file:write('M.prefixes = (' .. subparsers[path] .. ')\n')
      produced_parsers = produced_parsers + 1
    end
  end)
  output_file:write('-- luacheck: pop\n')
  assert(produced_parsers == 1)
end

-- Extract variable and function names from "l3*.dtx" files.
local function parse_definitions()
  -- Define an LPEG parser for variable and function name definitions.
  local macro_definitions
  do
    local newline = (
      P("\n")
      + P("\r\n")
      + P("\r")
    )
    local linechar = any - newline
    local endline = (
      newline
      + eof
    )

    local space = P(" ")
    local tab = P("\t")

    local percent_sign = P("%")

    local optional_commented_whitespace = (
      space
      + tab
      + (newline * percent_sign)
    )^0

    local function comma_list(item_parser, ender)
      return Ct(
        optional_commented_whitespace
        * ender
        + item_parser
        * optional_commented_whitespace
        * (
          P(",")
          * optional_commented_whitespace
          * item_parser
          * optional_commented_whitespace
        )^0
        * P(",")^-1
        * optional_commented_whitespace
        * ender
      )
    end

    local csname = (
      P([[\]])
      * C(
        (
          R("AZ", "az")
          + P(":")
          + P("_")
        )^1
      )
    )

    local macro_definition = Ct(
      P([[\begin]])
      * optional_commented_whitespace
      * P("{")
      * optional_commented_whitespace
      * C(
        P("variable")
        + P("function")
        + P("macro")
      )
      * optional_commented_whitespace
      * P("}")
      * optional_commented_whitespace
      * (
        P("[")
        * optional_commented_whitespace
        * comma_list(
          (
            Ct(
              C(P("added"))
              * optional_commented_whitespace
              * P("=")
              * optional_commented_whitespace
              * C(
                (
                  any
                  - S(",]")
                )^0
              )
            )
            + C(
              P("EXP")
              + P("rEXP")
              + P("TF")
              + P("pTF")
              + P("noTF")
            )
            + (
              any
              - S(",]")
            )^0
          ),
          P("]")
        )
        + Cc({})
      )
      * optional_commented_whitespace
      * P("{")
      * optional_commented_whitespace
      * comma_list(csname, P("}"))
    )

    local commented_lines = (
      percent_sign
      * (
        macro_definition
        + linechar
      )^0
      * endline
    )
    local non_commented_line = (
      linechar^1
      * endline
      + linechar^0
      * newline
    )

    macro_definitions = Ct(
      (
        commented_lines
        + non_commented_line
      )^0
    )
  end

  -- Collect all .dtx files from LaTeX3.
  local function collect_dtx_files()
    local seen_directory_pathnames, future_directory_pathnames = {}, {LATEX3_PATHNAME}
    local input_file_pathnames = {}
    while #future_directory_pathnames > 0 do
      local current_directory_pathname = table.remove(future_directory_pathnames)
      if seen_directory_pathnames[current_directory_pathname] ~= nil then
        goto next_directory
      end
      seen_directory_pathnames[current_directory_pathname] = true
      for current_file_filename in lfs.dir(current_directory_pathname) do
        if current_file_filename == "." or current_file_filename == ".." then
          goto next_file
        end
        local current_file_pathname = string.format("%s/%s", current_directory_pathname, current_file_filename)
        if lfs.attributes(current_file_pathname, "mode") == "directory" then
          table.insert(future_directory_pathnames, current_file_pathname)
        elseif current_file_filename:sub(1, 2) == "l3" and current_file_pathname:sub(-4):lower() == ".dtx" then
          table.insert(input_file_pathnames, current_file_pathname)
        end
        ::next_file::
      end
      ::next_directory::
    end
    table.sort(input_file_pathnames)
    return input_file_pathnames
  end

  local parsed_dtx_files, definitions = {}, {}
  for _, input_pathname in ipairs(collect_dtx_files()) do
    local input_file = assert(io.open(input_pathname, "r"), "Could not open " .. input_pathname .. " for reading")
    local content = assert(input_file:read("*all"))
    assert(input_file:close())

    -- For each DTX file, parse the definitions.
    local raw_definitions = lpeg.match(macro_definitions, content)
    if #raw_definitions == 0 then
      goto next_file
    end

    -- Record the DTX file.
    table.insert(parsed_dtx_files, input_pathname)

    -- Then, interpret these definitions.
    for _, raw_definition in ipairs(raw_definitions) do
      local definition_type, options, raw_csnames = table.unpack(raw_definition)
      for _, option in ipairs(options) do
        if type(option) == "string" then
          options[option] = true
        elseif type(option) == "table" then
          local key, value = table.unpack(option)
          assert(type(key) == "string")
          assert(type(value) == "string")
          options[key] = value
        end
      end
      -- Determine when the definition was first added.
      local definition = {
        pathname = input_pathname,
        type = definition_type,
      }
      if options.added ~= nil then
        local _, _, added_date = options.added:find("(%d%d%d%d%-%d%d%-%d%d)")
        assert(added_date ~= nil, string.format('Failed to parse date out of value "%s"', options.added))
        definition.added = added_date
      end
      -- Determine expandability.
      if options.EXP or options.pTF then
        assert(options.rEXP == nil)
        definition.EXP = "full"
      end
      if options.rEXP then
        assert(options.EXP == nil)
        assert(options.pTF == nil)
        definition.EXP = "restricted"
      end
      -- Determine the actual defined control sequence names.
      local csnames = {}
      for _, raw_csname in ipairs(raw_csnames) do
        if not (options.TF or options.pTF) or options.noTF then
          table.insert(csnames, raw_csname)
        end
        if options.TF or options.pTF or options.noTF then
          table.insert(csnames, string.format("%sTF", raw_csname))
          table.insert(csnames, string.format("%sT", raw_csname))
          table.insert(csnames, string.format("%sF", raw_csname))
        end
        if options.pTF then
          local raw_csname_stem, argument_specifiers = raw_csname:match("([^:]*):([^:]*)")
          assert(raw_csname_stem ~= nil)
          assert(argument_specifiers ~= nil)
          table.insert(csnames, string.format("%s_p:%s", raw_csname_stem, argument_specifiers))
        end
      end
      -- Record the control sequence names and their definitions.
      for _, csname in ipairs(csnames) do
        if definitions[csname] ~= nil then
          for _, key in ipairs({"added", "EXP"}) do
            -- When a definition is repeated and the recorded values are incompatible, either log a warning or report an error,
            -- based on whether one of the definitions originates from `\begin{macro}`, which makes the values less reliable.
            if definitions[csname][key] ~= nil and definition[key] ~= nil and definitions[csname][key] ~= definition[key] then
              local message =  string.format(
                'Conflicting value of "%s" for `\\%s`: "%s" in "%s" (`\\begin{%s}`) versus "%s" in "%s" (`\\begin{%s}`)',
                key,
                csname,
                definitions[csname][key],
                get_basename(definitions[csname].pathname),
                definitions[csname].type,
                definition[key],
                get_basename(definition.pathname),
                definition.type
              )
              if definitions[csname].type == "macro" or definition.type == "macro" then
                io.write(string.format("Warning: %s", message))
                local template = '; preferring "%s" over "%s"'
                if definitions[csname].type == "macro" and definition.type ~= "macro" then
                  print(string.format(template, definition[key], definitions[csname][key]))
                  definitions[csname][key] = definition[key]
                else
                  print(string.format(template, definitions[csname][key], definition[key]))
                end
              else
                error(message)
              end
            elseif definitions[csname][key] == nil and definition[key] ~= nil then
              -- When a definition is repeated and the next definition specifies some new values, record them.
              definitions[csname][key] = definition[key]
            end
          end
        else
          definitions[csname] = definition
          table.insert(definitions, csname)
        end
      end
    end
    ::next_file::
  end
  return parsed_dtx_files, definitions
end

-- Generate an LPEG parser of variable and function names defined in "l3*.dtx" files.
local function generate_definitions_parser(output_file, definitions)
  -- In order to minimize the size and speed of the parser, first construct a prefix tree of the definitions.
  local prefix_tree = {}
  for _, csname in ipairs(definitions) do
    local node = prefix_tree
    for character_index = 1, #csname do
      local character = csname:sub(character_index, character_index)
      assert(#character == 1)
      if character_index < #csname then  -- an intermediate node
        if node[character] == nil then
          node[character] = {}
        end
        node = node[character]
      else  -- a leaf node
        table.insert(node, character)
      end
    end
  end

  -- Then, generate a parser out of the tree.
  local output_regular_character = any - P('"')
  local output_capture = P(" * Cc({") * (any - P("}"))^0 * P("})")
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
      output_capture
      + simplified_output_regular_characters
    )^0
    * eof
  )

  output_file:write('-- luacheck: push no max line length\n')
  local subparsers = {}
  local produced_parsers = 0
  depth_first_search(prefix_tree, "", function(node, path)  -- visit
    if type(node) == "string" then  -- leaf node
      assert(node ~= '"')
      local suffix_buffer = {'P("' .. node .. '")'}
      local definition = definitions[path .. node]
      assert(definition ~= nil)
      local options_buffer = {}
      for _, key in ipairs({"added", "EXP"}) do
        local value = definition[key]
        if value ~= nil then
          table.insert(options_buffer, string.format('%s="%s"', key, value))
        end
      end
      if #options_buffer > 0 then
        table.insert(suffix_buffer, " * Cc({")
        table.insert(suffix_buffer, table.concat(options_buffer, ", "))
        table.insert(suffix_buffer, "})")
      end
      local suffix = table.concat(suffix_buffer)
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
      output_file:write('M.definitions = (' .. subparsers[path] .. ')\n')
      produced_parsers = produced_parsers + 1
    end
  end)
  output_file:write('-- luacheck: pop\n')
  assert(produced_parsers == 1)
end

-- Generate the file "explcheck-latex3.lua".
local output_filename = "explcheck-latex3.lua"
local output_file = assert(io.open(output_filename, "w"), "Could not open " .. output_filename .. " for writing")

-- Add a comment, both to an output file and to the standard output.
local function add_comment(text)
  print(text)
  output_file:write(string.format("-- %s\n", text))
end

---- Generate the preamble.
add_comment("LPEG parsers and other information extracted from LaTeX3 data files.")
add_comment(string.format("Generated on %s from the following files:", os.date("%Y-%m-%d")))
local csnames, l3obsolete_dates, l3obsolete_latest_date, l3obsolete_latest_raw_csname = parse_l3obsolete()
add_comment(
  string.format('- "l3obsolete.txt" with the latest obsolete entry from %s: `\\%s`', l3obsolete_latest_date, l3obsolete_latest_raw_csname)
)
local prefixes, l3prefixes_dates, l3prefixes_latest_date, l3prefixes_latest_prefix = parse_l3prefixes()
add_comment(
  string.format('- "l3prefixes.csv" with the latest registered prefix from %s: "%s"', l3prefixes_latest_date, l3prefixes_latest_prefix)
)
local parsed_dtx_files, definitions = parse_definitions()
add_comment(
  string.format(
    '- %s "l3*.dtx" files with %s public function and variable %s',
    humanize(#parsed_dtx_files),
    humanize(#definitions),
    pluralize("definition", #definitions)
  )
)
output_file:write("\n")

---- Generate the LPEG parsers.
output_file:write('local lpeg = require("lpeg")\n')
output_file:write('local Cc, P = lpeg.Cc, lpeg.P\n\n')
output_file:write('local M = {}\n\n')
generate_l3obsolete_parsers(output_file, l3obsolete_dates, csnames)
output_file:write("\n")
generate_l3prefixes_parser(output_file, l3prefixes_dates, prefixes)
output_file:write("\n")
generate_definitions_parser(output_file, definitions)
output_file:write("\nreturn M")
assert(output_file:close())
