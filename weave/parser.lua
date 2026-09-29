-- weave/parser.lua
-- defines source package suffixes

local SOURCE_SUFFIXES = {
  aur = "aur",
  nix = "nix",
}

-- Splits "package_name.aur" -> name="package_name", kind="aur"
-- Splits "neovim" -> name="neovim", kind="native"
local function parse_package_string(str)
  local name, suffix = str:match("^(.+)%.([%w]+)$")

  if suffix and SOURCE_SUFFIXES[suffix] then
    return { name = name, kind = SOURCE_SUFFIXES[suffix] }
  end

  -- No recognized suffix (or no dot at all) -> treat whole string as the name, source is native
  return { name = str, kind = "native" }
end

local M = {}
M.parse_package_string = parse_package_string
return M
