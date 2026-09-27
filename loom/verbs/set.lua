-- loom/verbs/set.lua
local generations = require("loom.state.generations")

local M = {}

function M.run(args)
  if args[1] == "list" then
    local all = generations.load()
    local limit = generations.get_retention_limit()
    print(("loom set: retention limit = %d"):format(limit))
    for _, entry in ipairs(all) do
      print(("  generation %d — %s — created %s"):format(
        entry.generation, entry.status, os.date("%Y-%m-%d %H:%M", entry.created)))
    end
    return
  end

  local limit = tonumber(args[1])
  if not limit then
    print("loom set: usage: loom set <n> | loom set list")
    os.exit(1)
  end

  generations.set_retention_limit(limit)
  print(("loom set: retention limit set to %d"):format(limit))
end

return M
