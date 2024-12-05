bundle = "expltools"
modules = {"explcheck"}

local function dirzip(dir, zipname)
  local newzip = require"l3build-zip"
  local lfs = require("lfs")
  local attributes = lfs.attributes

  zipname = zipname .. ".zip"
  local zip = assert(newzip(dir .. '/' .. zipname))
  local function tab_to_check(table)
    local patterns = {}
    for n,i in ipairs(table) do
      patterns[n] = glob_to_pattern(i)
    end
    return function(name)
      for n, patt in ipairs(patterns) do
        if name:match"([^/]*)$":match(patt) then return true end
      end
      return false
    end
  end
  -- Convert the tables of files to quoted strings
  local binfile = tab_to_check(binaryfiles)
  local exclude = tab_to_check(excludefiles)
  local exefile = tab_to_check(exefiles)
  -- First, zip up all of the text files
  for _, p in ipairs(tree(dir, "**")) do
    local src = p.src:sub(3) -- Strip ./
    if not (attributes(p.cwd, "mode") == "directory" or exclude(src) or src == zipname) then
      zip:add(p.cwd, src, binfile(src), exefile(src))
    end
  end
  return zip:close()
end

-- A custom main function
function main(target, names)
  local return_value
  if ({check=true, bundlecheck=true, doc=true})[target] ~= nil then
    return_value = call(modules, target)
  elseif ({ctan=true, bundlectan=true})[target] ~= nil then
    return_value = target_list[target].bundle_func(names)
    -- After installing CTAN files, add one extra level of directories.
    local pkgdir = ctandir .. "/" .. ctanpkg
    cp("CHANGES.md", pkgdir, pkgdir .. "/doc")
    rm(pkgdir, "CHANGES.md")
    dirzip(ctandir, ctanzip)
    cp(ctanzip .. ".zip", ctandir, currentdir)
  else
    help()
    return_value = 0
  end
  os.exit(return_value == 0 and 0 or 1)
end
