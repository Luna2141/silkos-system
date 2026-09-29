-- loom/state/generations.lua
local json = require("loom.util.json")

local GENERATIONS_PATH = "/silk/boot/loom/generations.json"
local LOCK_PATH = "/silk/boot/loom/generations.json.lock"
local RETENTION_PATH = "/silk/boot/loom/retention.json"
local DEFAULT_RETENTION_LIMIT = 5

local M = {}

-- === reading ===

local function read_generations()
  local f = io.open(GENERATIONS_PATH, "r")
  if not f then
    return {}
  end

  local content = f:read("*a")
  f:close()

  if content == "" then
    return {}
  end

  local ok, data = pcall(json.decode, content)
  if not ok then
    error("generations.lua: corrupt generations.json: " .. tostring(data))
  end

  return data
end

-- === writing (atomic) ===

local function write_generations(data)
  local tmp_path = GENERATIONS_PATH .. ".tmp"

  os.execute("chmod u+w " .. GENERATIONS_PATH)

  local f = io.open(tmp_path, "w")
  if not f then
    error("generations.lua: failed to open temp file for writing")
  end

  f:write(json.encode(data))
  f:close()

  local ok, err = os.rename(tmp_path, GENERATIONS_PATH)
  if not ok then
    error("generations.lua: failed to atomically replace generations.json: " .. tostring(err))
  end

  os.execute("chmod u-w " .. GENERATIONS_PATH)
end

-- === locking ===

local function acquire_lock()
  local f = io.open(LOCK_PATH, "r")
  if f then
    f:close()
    error("generations.lua: another loom operation is in progress (lockfile exists at " .. LOCK_PATH .. ")")
  end

  local lock = io.open(LOCK_PATH, "w")
  lock:write(tostring(os.time()))
  lock:close()
end

local function release_lock()
  os.remove(LOCK_PATH)
end

local function with_lock(fn)
  acquire_lock()
  local ok, result = pcall(fn)
  release_lock()

  if not ok then
    error(result)
  end
  return result
end

-- === retention limit (separate small file, see design note) ===

local function read_retention_limit()
  local f = io.open(RETENTION_PATH, "r")
  if not f then
    return DEFAULT_RETENTION_LIMIT
  end

  local content = f:read("*a")
  f:close()

  if content == "" then
    return DEFAULT_RETENTION_LIMIT
  end

  local ok, data = pcall(json.decode, content)
  if not ok or type(data) ~= "table" or not data.limit then
    return DEFAULT_RETENTION_LIMIT
  end

  return data.limit
end

local function write_retention_limit(limit)
  local tmp_path = RETENTION_PATH .. ".tmp"
  local f = io.open(tmp_path, "w")
  f:write(json.encode_object({ limit = limit }))
  f:close()
  os.rename(tmp_path, RETENTION_PATH)
end

-- === public interface ===

function M.load()
  return read_generations()
end

function M.next_number()
  local existing = read_generations()
  local max_gen = -1
  for _, entry in ipairs(existing) do
    if entry.generation > max_gen then
      max_gen = entry.generation
    end
  end
  return max_gen + 1
end

function M.add(entry)
  with_lock(function()
    local data = read_generations()
    data[#data + 1] = entry
    write_generations(data)
  end)
end

function M.set_active(generation_number)
  with_lock(function()
    local data = read_generations()
    for _, entry in ipairs(data) do
      if entry.status == "active" then
        entry.status = "stale"
      end
      if entry.generation == generation_number then
        entry.status = "active"
      end
    end
    write_generations(data)
  end)
end

function M.get_active()
  local data = read_generations()
  for _, entry in ipairs(data) do
    if entry.status == "active" then
      return entry
    end
  end
  return nil
end

function M.prune(limit)
  return with_lock(function()
    local data = read_generations()
    table.sort(data, function(a, b) return a.generation < b.generation end)

    local removed = {}
    while #data > limit do
      removed[#removed + 1] = table.remove(data, 1)
    end

    write_generations(data)
    return removed
  end)
end

function M.get_retention_limit()
  return read_retention_limit()
end

function M.set_retention_limit(limit)
  write_retention_limit(limit)
  M.prune(limit)
end

return M
