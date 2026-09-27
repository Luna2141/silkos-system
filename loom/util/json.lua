-- loom/util/json.lua
local M = {}

-- forward declarations, needed because these functions call each other
local parse_value, parse_object, parse_array

local function skip_whitespace(s, pos)
  local _, new_pos = s:find("^%s*", pos)
  return new_pos + 1
end

local function parse_string(s, pos)
  pos = pos + 1
  local start = pos
  while s:sub(pos, pos) ~= '"' do
    pos = pos + 1
  end
  local str = s:sub(start, pos - 1):gsub('\\"', '"')
  return str, pos + 1
end

local function parse_number(s, pos)
  local match, new_pos = s:match("^(%-?%d+%.?%d*)()", pos)
  return tonumber(match), new_pos
end

local function parse_boolean(s, pos)
  if s:sub(pos, pos + 3) == "true" then
    return true, pos + 4
  else
    return false, pos + 5
  end
end

parse_object = function(s, pos)
  pos = pos + 1
  local obj = {}

  pos = skip_whitespace(s, pos)
  if s:sub(pos, pos) == "}" then
    return obj, pos + 1
  end

  while true do
    pos = skip_whitespace(s, pos)
    local key
    key, pos = parse_string(s, pos)

    pos = skip_whitespace(s, pos)
    pos = pos + 1 -- skip ':'

    pos = skip_whitespace(s, pos)
    local value
    value, pos = parse_value(s, pos)

    obj[key] = value

    pos = skip_whitespace(s, pos)
    local c = s:sub(pos, pos)
    if c == "," then
      pos = pos + 1
    elseif c == "}" then
      return obj, pos + 1
    else
      error("json.decode: expected ',' or '}' at position " .. pos)
    end
  end
end

parse_array = function(s, pos)
  pos = pos + 1
  local arr = {}

  pos = skip_whitespace(s, pos)
  if s:sub(pos, pos) == "]" then
    return arr, pos + 1
  end

  while true do
    pos = skip_whitespace(s, pos)
    local value
    value, pos = parse_value(s, pos)
    arr[#arr + 1] = value

    pos = skip_whitespace(s, pos)
    local c = s:sub(pos, pos)
    if c == "," then
      pos = pos + 1
    elseif c == "]" then
      return arr, pos + 1
    else
      error("json.decode: expected ',' or ']' at position " .. pos)
    end
  end
end

parse_value = function(s, pos)
  pos = skip_whitespace(s, pos)
  local c = s:sub(pos, pos)

  if c == '"' then
    return parse_string(s, pos)
  elseif c == "{" then
    return parse_object(s, pos)
  elseif c == "[" then
    return parse_array(s, pos)
  elseif c == "t" or c == "f" then
    return parse_boolean(s, pos)
  elseif c:match("[%-%d]") then
    return parse_number(s, pos)
  else
    error("json.decode: unexpected character '" .. c .. "' at position " .. pos)
  end
end

function M.decode(str)
  local value, _ = parse_value(str, 1)
  return value
end

-- encoding (from earlier)

local function encode_value(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub('"', '\\"') .. '"'
  elseif t == "number" then
    return tostring(v)
  elseif t == "boolean" then
    return tostring(v)
  else
    error("json.encode: unsupported type: " .. t)
  end
end

local function encode_entry(entry)
  local parts = {}
  for key, value in pairs(entry) do
    parts[#parts + 1] = '"' .. key .. '":' .. encode_value(value)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.encode(generations_list)
  local parts = {}
  for _, entry in ipairs(generations_list) do
    parts[#parts + 1] = encode_entry(entry)
  end
  return "[" .. table.concat(parts, ",") .. "]"
end

return M
