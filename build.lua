bundle = "expltools"
modules = {"explcheck"}

-- A custom main function
function main(target)
  local errorlevel
  if target == "check" then
    errorlevel = call(modules, "check")
  else
    help()
  end
  if errorlevel ~=0 then
    os.exit(1)
  end
end
