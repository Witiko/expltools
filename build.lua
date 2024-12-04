bundle = "expltools"
modules = {"explcheck"}

-- A custom main function
function main(target, names)
  local return_value
  if ({check=true, bundlecheck=true, doc=true})[target] ~= nil then
    return_value = call(modules, target)
  elseif ({ctan=true, bundlectan=true})[target] ~= nil then
    return_value = target_list[target].bundle_func(names)
  else
    help()
    return_value = 0
  end
  os.exit(return_value == 0 and 0 or 1)
end
