-- loom/state/staging.lua
local shell = require("weave.util.shell")
local hash = require("loom.util.hash")

local M = {}

local STORE_PATH = "/silk/store"
local AUR_DEB_CACHE_PATH = "/silk/weave/cache/aur-deb"
local MERGE_PATH = "/silk/ostree/staged"
local OSTREE_REPO = "/silk/ostree/repo"
local OSTREE_BRANCH = "silk"

local function compute_input_hash(recipe)
  local parts = {
    recipe.name,
    recipe.version,
    recipe.source.kind,
    recipe.source.checksum or "",
    table.concat(recipe.depends or {}, ","),
    recipe.flavor or "",
  }
  for _, step in ipairs(recipe.acquire.steps or {}) do
    parts[#parts + 1] = step.cmd or "fn-step"
  end
  return hash.sha256(table.concat(parts, "|"))
end

local function compute_output_hash(destdir)
  local cmd = "tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -cf - -C "
      .. hash.shell_quote(destdir) .. " . | sha256sum"
  local handle = io.popen(cmd)
  local output = handle:read("*a")
  handle:close()
  return output:match("^(%x+)")
end

local function cache_dir_for(recipe)
  if recipe.source.kind == "native" or recipe.source.kind == "nix" then
    return STORE_PATH
  else
    return AUR_DEB_CACHE_PATH
  end
end

local function path_exists(path)
  return os.execute("test -e " .. hash.shell_quote(path)) == true
end

function M.check_cache(recipe)
  local input_hash = compute_input_hash(recipe)
  local entry_dir = cache_dir_for(recipe) .. "/" .. input_hash .. "-" .. recipe.name .. "-" .. recipe.version

  if path_exists(entry_dir) then
    return input_hash, entry_dir
  end
  return input_hash, nil
end

local function place_in_cache(entry)
  if entry.cached then
    return
  end

  local target_dir = cache_dir_for(entry.recipe) ..
  "/" .. entry.input_hash .. "-" .. entry.recipe.name .. "-" .. entry.recipe.version

  shell.run("mkdir -p " .. hash.shell_quote(target_dir))
  shell.run("cp -a " .. hash.shell_quote(entry.destdir) .. "/. " .. hash.shell_quote(target_dir) .. "/")

  local output_hash = compute_output_hash(target_dir)
  local meta_file = io.open(target_dir .. "/.loom-output-hash", "w")
  meta_file:write(output_hash)
  meta_file:close()

  entry.stored_path = target_dir
end

local function list_files(dir)
  local handle = io.popen("cd " .. hash.shell_quote(dir) .. " && find . -type f -o -type l | sed 's|^\\./||'")
  local files = {}
  for line in handle:lines() do
    files[#files + 1] = line
  end
  handle:close()
  return files
end

local function place_entry(entry, merge_dir, claimed_by)
  local is_symlink_kind = (entry.recipe.source.kind == "native" or entry.recipe.source.kind == "nix")
  local source_dir = entry.stored_path or entry.destdir
  local files = list_files(source_dir)

  for _, rel_path in ipairs(files) do
    if claimed_by[rel_path] then
      error(("staging: path collision at '%s' between packages '%s' and '%s'")
        :format(rel_path, claimed_by[rel_path], entry.recipe.name))
    end
    claimed_by[rel_path] = entry.recipe.name

    local target_path = merge_dir .. "/" .. rel_path
    shell.run("mkdir -p " .. hash.shell_quote(target_path:match("^(.*)/[^/]+$")))

    if is_symlink_kind then
      shell.run("ln -s " .. hash.shell_quote(source_dir .. "/" .. rel_path) .. " " .. hash.shell_quote(target_path))
    else
      shell.run("cp -a " .. hash.shell_quote(source_dir .. "/" .. rel_path) .. " " .. hash.shell_quote(target_path))
    end
  end
end

local function fresh_merge_tree()
  shell.run("rm -rf " .. hash.shell_quote(MERGE_PATH))
  shell.run("mkdir -p " .. hash.shell_quote(MERGE_PATH))
  return MERGE_PATH
end

function M.validate_symlinks(tree_dir)
  local handle = io.popen("find " .. hash.shell_quote(tree_dir) .. " -type l 2>/dev/null")
  local broken = {}

  for link_path in handle:lines() do
    if os.execute("test -e " .. hash.shell_quote(link_path)) ~= true then
      broken[#broken + 1] = link_path
    end
  end
  handle:close()

  if #broken > 0 then
    error("staging: broken symlink(s) detected before swap:\n  " .. table.concat(broken, "\n  "))
  end
end

function M.stage(entries)
  for _, entry in ipairs(entries) do
    place_in_cache(entry)
  end

  local merge_dir = fresh_merge_tree()
  local claimed_by = {}

  for _, entry in ipairs(entries) do
    place_entry(entry, merge_dir, claimed_by)
  end

  M.validate_symlinks(merge_dir)

  local commit_cmd = ("ostree --repo=%s commit -b %s --tree=dir=%s")
      :format(hash.shell_quote(OSTREE_REPO), OSTREE_BRANCH, hash.shell_quote(merge_dir))
  local handle = io.popen(commit_cmd)
  local output = handle:read("*a")
  handle:close()

  local commit_hash = output:match("%x+")
  if not commit_hash then
    error("staging: ostree commit failed or produced no commit hash: " .. output)
  end

  return { ostree_commit = commit_hash }
end

return M
