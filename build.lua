bundle = "expltools"
modules = {"explcheck"}

-- A custom main function
function main(target)
  if target == "check" or target == "doc" then
    os.exit(call(modules, target))
  else
    help()
  end
end
