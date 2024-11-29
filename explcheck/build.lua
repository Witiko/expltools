bundle = "expltools"
module = "explcheck"
maindir = ".."

supportdir = "support"
docfiledir = "doc"
typesetfiles = {
  "*.bib",
  "*.md",
  "*.tex",
}
typesetsuppfiles = {
  "*.cls",
  "*.ist",
  "latexmkrc",
  "*.pdf",
  "*.sty",
}

-- Convert a pathname of a file to the base name of a file.
local function get_suffix(filename)
  return filename:gsub(".+%.", "."):lower()
end

-- Determine whether a filename refers to an existing file.
local function file_exists(filename)
  return lfs.attributes(filename, "mode") == "file"
end

-- A custom main function
function main(target, names)
  if target == "check" or target == "doc" then
    local return_value = target_list[target].func(names)
    if target == "doc" then
      local lfs = require("lfs")
      -- After typesetting the documentation, remove .pdf files from supportdir, so that they are excluded from artefacts.
      for filename in lfs.dir(supportdir) do
        if get_suffix(filename) == ".pdf" then
          rm(typesetdir, filename)
        end
      end
    end
    os.exit(return_value)
  else
    help()
  end
end

function docinit_hook()
  local lfs = require("lfs")
  -- Before typesetting the documentation, add .tex files from testfiledir, so that they can be used in code listings.
  for filename in lfs.dir(testfiledir) do
    if get_suffix(filename) == ".tex" then
      cp(filename, testfiledir, typesetdir)
    end
  end
  return 0
end

function typeset(filename, dir)
  local lfs = require("lfs")
  -- The caller will only call us once for every basename. Therefore, even if filename is e.g. "document.bib",
  -- we must check whether "document.tex" exists, because we won't be called again for "document.tex".
  if (get_suffix(filename) == ".tex" or file_exists(dir .. "/" .. jobname(filename) .. ".tex"))
      and not file_exists(testfiledir .. "/" .. jobname(filename) .. ".tex") then
    -- Use Latexmk to typeset the documentation.
    return run(dir, "latexmk " .. jobname(filename))
  else
    print("Skipping " .. jobname(filename))
    return 0
  end
end

-- Translate the command "l3build check" to calling the function returned by the Lua module "test.py".
function checkinit_hook()
  local lfs = require("lfs")
  local support_files = {}
  for filename in lfs.dir("src") do
    if get_suffix(filename) == ".lua" then
      table.insert(support_files, "src/" .. filename)
    end
  end
  local testfiles = {}
  for filename in lfs.dir(testfiledir) do
    local suffix = get_suffix(filename)
    if suffix == ".lua" or suffix == ".tex" then
      table.insert(testfiles, testfiledir .. "/" .. filename)
    end
  end
  local run_tests = require("test")
  local test_result = run_tests("test", support_files, testfiles)
  os.exit(test_result and 0 or 1)
end
