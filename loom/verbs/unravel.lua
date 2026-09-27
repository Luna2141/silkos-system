-- loom/verbs/unravel.lua
local generations = require("loom.state.generations")

local M = {}

function M.run(args)
  local target_gen

  if args[1] then
    target_gen = tonumber(args[1])
    if not target_gen then
      print("loom unravel: invalid generation number: " .. tostring(args[1]))
      os.exit(1)
    end
  else
    local active = generations.get_active()
    if not active then
      print("loom unravel: no active generation to revert from")
      os.exit(1)
    end
    target_gen = active.generation - 1
  end

  local all = generations.load()
  local found = nil
  for _, entry in ipairs(all) do
    if entry.generation == target_gen then
      found = entry
      break
    end
  end

  if not found then
    print("loom unravel: generation " .. target_gen .. " does not exist")
    os.exit(1)
  end

  generations.set_active(target_gen)
  print(("loom unravel: generation %d marked active. Reboot to apply."):format(target_gen))
end

return M
