-- loom/manifest.lua
local FABRIC_PATH = "/etc/silk/fabric.lua"

local VALID_LIBC = { glibc = true, musl = true }

local function load_fabric()
  local chunk, err = loadfile(FABRIC_PATH)
  if not chunk then
    return nil, "failed to load " .. FABRIC_PATH .. ": " .. err
  end

  local ok, result = pcall(chunk)
  if not ok then
    return nil, "error running " .. FABRIC_PATH .. ": " .. result
  end

  return result
end

local function validate_system(system)
  if type(system) ~= "table" then
    return false, "fabric.lua: missing or invalid `system` block"
  end

  if type(system.hostname) ~= "string" or system.hostname == "" then
    return false, "fabric.lua: system.hostname must be a non-empty string"
  end

  if not VALID_LIBC[system.libc] then
    return false, "fabric.lua: system.libc must be 'glibc' or 'musl', got: " .. tostring(system.libc)
  end

  if type(system.init) ~= "string" or system.init == "" then
    return false, "fabric.lua: system.init must be a non-empty string"
  end

  return true
end

local M = {}

function M.load()
  local config, err = load_fabric()
  if not config then
    print("loom: " .. err)
    os.exit(1)
  end

  local ok, err2 = validate_system(config.system)
  if not ok then
    print("loom: " .. err2)
    os.exit(1)
  end

  return config
end

return M
