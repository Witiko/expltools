bundle = "expltools"
module = "explcheck"
maindir = ".."

supportdir = "support"
docfiledir = "doc"
sourcefiledir = "src"

typesetfiles = {
  "*.tex",
  "*.md",
}
sourcefiles = {
  "*.lua",
}
bibfiles = {
  "**/*.bib",
}
textfiles = {
  "**/*.cls",
  "**/*.ist",
  "**/latexmkrc",
  "**/*.sty",
}
typesetsuppfiles = {
  "*.cls",
  "*.ist",
  "latexmkrc",
  "*.pdf",
  "*.sty",
}
scriptfiles = {
  "explcheck.lua",
}
tagfiles = {
  "explcheck-cli.lua",
}

-- Convert a pathname of a file to the base name of a file.
local function get_suffix(filename)
  return filename:gsub(".+%.", "."):lower()
end

-- Determine whether a filename refers to an existing file.
local function file_exists(filename)
  return lfs.attributes(filename, "mode") == "file"
end

local function bundlectan()
  local errorlevel = install_files(tdsdir, true)
  if errorlevel ~= 0 then return errorlevel end
  copyctan()
  -- After installing CTAN files, add one extra level of directories.
  local pkgdir = ctandir .. "/" .. ctanpkg
  mkdir(pkgdir .. "/scripts")
  for _, scriptfile in ipairs(scriptfiles) do
    cp(scriptfile, pkgdir, pkgdir .. "/scripts")
    rm(pkgdir, scriptfile)
  end
  mkdir(pkgdir .. "/luatex")
  for _, sourcefile in ipairs(sourcefiles) do
    cp(sourcefile, pkgdir, pkgdir .. "/luatex")
    rm(pkgdir, sourcefile)
  end
  mkdir(pkgdir .. "/doc")
  for _, docfile in ipairs(filelist(pkgdir)) do
    if file_exists(pkgdir .. "/" .. docfile) then
      cp(docfile, pkgdir, pkgdir .. "/doc")
      rm(pkgdir, docfile)
    end
  end
  return 0
end

-- Determine the latest version of the tool from the file `CHANGES.md`.
local function get_latest_explcheck_version()
  local pattern = "^%s*#%s*#%s*#%s*explcheck%s*"
  for line in io.lines(maindir .. "/CHANGES.md") do
    if line:find(pattern) then
      return line:gsub(pattern, "")
    end
  end
  assert(false)
end

function update_tag(file, content, tagname, tagdate)
  tagname = tagname or get_latest_explcheck_version()
  return content:gsub("${VERSION}", tagname)
                :gsub("${DATE}", tagdate)
end

-- A custom main function
function main(target, names)
  local return_value
  if ({check=true, bundlecheck=true, ctan=true, bundlectan=true, doc=true, tag=true})[target] ~= nil then
    local func = target == "bundlectan" and bundlectan or target_list[target].func
    return_value = func(names)
    if ({ctan=true, bundlectan=true, doc=true})[target] ~= nil then
      local lfs = require("lfs")
      -- After typesetting the documentation, remove .pdf files from supportdir, so that they are excluded from artefacts.
      for filename in lfs.dir(supportdir) do
        if get_suffix(filename) == ".pdf" then
          rm(typesetdir, filename)
        end
      end
    end
  else
    help()
    return_value = 0
  end
  os.exit(return_value == 0 and 0 or 1)
end

function typeset(filename, dir)
  local lfs = require("lfs")
  if get_suffix(filename) == ".tex" and not file_exists(testfiledir .. "/" .. jobname(filename) .. ".tex") then
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
