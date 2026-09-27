-- loom/state/reboot_checklist.lua
local generations = require("loom.state.generations")

local REBOOT_TRIGGER_PACKAGES = {
  linux = true,
  mesa = true,
  nvidia = true,
  -- DE/WM entries TBD, added as those recipes exist
}

local M = {}

local function hardcoded_match(recipes)
  for _, recipe in ipairs(recipes) do
    if REBOOT_TRIGGER_PACKAGES[recipe.name] then
      return true, ("package '%s' is a core-system component"):format(recipe.name)
    end
  end
  return false
end

local function self_declared_match(recipes)
  for _, recipe in ipairs(recipes) do
    if recipe.requires_reboot then
      return true, ("package '%s' declares requires_reboot"):format(recipe.name)
    end
  end
  return false
end

local function foreign_source_match(recipes)
  for _, recipe in ipairs(recipes) do
    if recipe.source.kind == "aur" or recipe.source.kind == "deb" then
      return true, ("package '%s' (%s) requires a reboot to apply"):format(recipe.name, recipe.source.kind)
    end
  end
  return false
end

local function init_change_match(new_init)
  local active = generations.get_active()
  if not active then
    return false
  end

  if active.init ~= new_init then
    return true, ("init system change detected: '%s' -> '%s'"):format(active.init, new_init)
  end
  return false
end

function M.check(recipes, new_init)
  local matched, reason = hardcoded_match(recipes)
  if matched then return true, reason end

  matched, reason = self_declared_match(recipes)
  if matched then return true, reason end

  matched, reason = foreign_source_match(recipes)
  if matched then return true, reason end

  matched, reason = init_change_match(new_init)
  if matched then return true, reason end

  return false
end

return M
