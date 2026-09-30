-- weave/sources/deb.lua
-- Per design (tech reference 9b-1): explicit URL/path declared in a
-- recipe file (weave/recipes/<name>.lua, source.kind = "deb"), manual
-- ar/tar extraction. No dpkg dependency, no live index -- .deb has none
-- to query, unlike AUR/Nix, so the recipe file is where checksum,
-- depends, and any extra acquire.steps get declared by hand.

local function resolve(name)
  local ok, recipe = pcall(require, "weave.recipes." .. name)
  if not ok then
    error(string.format(
      "no deb recipe found for '%s' (expected weave/recipes/%s.lua with source.kind = \"deb\"): %s",
      name, name, recipe
    ))
  end

  if not recipe.source or not recipe.source.url then
    error(string.format("deb recipe '%s' must declare source.url", name))
  end

  local filename = recipe.source.url:match("([^/]+)$")

  -- Prepend the fetch+unpack steps ahead of whatever the recipe
  -- author already wrote in acquire.steps (if anything).
  local steps = {
    { cmd = "curl -LO " .. recipe.source.url },
    -- `ar x` pulls out control.tar.* and data.tar.* separately;
    -- we only need data.tar.* (the actual package contents).
    { cmd = "ar x " .. filename },
    -- data.tar.* may be .gz/.xz/.zst depending on the package --
    -- `tar -xf` auto-detects compression, so one command covers
    -- all three without branching on extension.
    { cmd = "tar -xf data.tar.*" },
  }
  if recipe.acquire and recipe.acquire.steps then
    for _, step in ipairs(recipe.acquire.steps) do
      table.insert(steps, step)
    end
  end

  recipe.acquire = recipe.acquire or {}
  recipe.acquire.steps = steps

  return recipe
end

local M = {}
M.resolve = resolve
return M
