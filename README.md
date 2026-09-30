# SilkOS System Tools

**Weave** and **Loom** are the declarative package resolution/build system and system-state manager for SilkOS — a non-systemd, Nix-inspired Linux distribution configured entirely in Lua. Together they play the role `nix`/Nix Flakes and `nixos-rebuild` play in NixOS: Weave resolves and builds packages from `fabric.lua` (SilkOS's system manifest, akin to `configuration.nix`); Loom takes Weave's output and turns it into a real, atomic, rollback-capable system generation.

**They are independently usable.** Weave has no dependency on Loom in either direction — it can be used entirely on its own as a standalone package resolver/builder, with no generations, no OSTree, no immutable-root model at all. Loom, by contrast, is intentionally fused to that generation/rollback model, the same way `nixos-rebuild` is fused to Nix — see "Using Loom" below before assuming it's meant to be generic.

**Status:** Weave's core pipeline (parser → schema → resolver → sources → executor) is implemented and proven working end-to-end. Loom's full design — all six verbs, generation tracking, OSTree staging, the reboot-required checklist — is fully written but not yet tested against a real system. Expect breaking changes.

## Repository Layout

```
silkos-system/
├── weave/           -- package resolution & build system (standalone-capable)
│   ├── parser.lua
│   ├── resolver.lua
│   ├── schema.lua
│   ├── executor.lua
│   ├── sources/
│   │   ├── native.lua
│   │   ├── aur.lua
│   │   └── nix.lua
│   ├── util/
│   │   ├── shell.lua
│   │   └── version.lua
│   └── recipes/
│       ├── recipe.lua
│       └── lua.lua
└── loom/            -- system-state manager, built on top of Weave
    ├── init.lua
    ├── manifest.lua
    ├── verbs/
    │   ├── bind.lua
    │   ├── thread.lua
    │   ├── spin.lua
    │   ├── test.lua
    │   ├── unravel.lua
    │   └── set.lua
    ├── state/
    │   ├── generations.lua
    │   ├── staging.lua
    │   └── reboot_checklist.lua
    └── util/
        ├── json.lua
        └── hash.lua
```


`weave/` holds the package resolver and builder: `parser.lua`, `resolver.lua`, and `schema.lua` implement the core resolution pipeline; `executor.lua` runs a resolved recipe's build steps; `sources/` holds one module per package source kind; `util/` holds small shared helpers; `recipes/` holds native package recipes plus a generator script for scaffolding new ones.

`loom/` holds the system-state manager built on top of Weave: `verbs/` holds one file per command; `state/` holds the shared machinery those verbs use; `util/` holds small shared helpers; `init.lua` and `manifest.lua` are the entry point and system-manifest loader.

## Using Weave Standalone

Weave has no dependency on Loom, generations, `store/`, or OSTree — it can be used on its own as a plain package resolver/builder. This is the entire pattern:

```lua
package.path = "/path/to/weave/?.lua;/path/to/weave/?/init.lua;;" .. package.path

local resolver = require("weave.resolver")
local executor = require("weave.executor")

local package_strings = { "neovim", "some-tool.aur", "ripgrep-all.nix" }

local recipes, err = resolver.resolve_all(package_strings)
if not recipes then
    error("resolution failed: " .. tostring(err))
end

for _, recipe in ipairs(recipes) do
    local ctx = executor.run(recipe, { yes = true })
    print(recipe.name, "built into", ctx.destdir)
end
```

`resolver.resolve_all()` turns a list of package strings into validated `Recipe`s, `executor.run()` builds each one and returns the `ctx` table it used, including `ctx.destdir` — the directory the finished package output was written to. Nothing else happens automatically; where that output goes next is entirely up to whatever's calling Weave.

### What you'll need to adapt

- **`LUA_PATH`** — Weave's modules are referenced as `weave.<name>`, so `weave/`'s *parent* directory needs to be on `package.path`, as shown above.
- **Native recipes** (`weave/recipes/*.lua`) — write your own, or adapt SilkOS's as a starting point.
- **`weave/util/shell.lua`** and anywhere else a shell command assumes a particular filesystem layout.
- **The `loom-build` unprivileged user** (used by `sources/aur.lua`, since `makepkg` refuses to run as root) — needs to exist on whatever system you're running Weave on, with the same no-login/no-password/scoped-access properties described under AUR recipes below.

## Writing a Recipe

Every package, regardless of source, resolves into the same `Recipe` shape — defined canonically in `weave/schema.lua`:

```lua
{
    name = "...",
    version = nil,             -- filled in once the source is queried
    source = { kind = "...", ... },   -- source-specific fields, see below
    depends = {},
    acquire = nil,               -- how to build/obtain it, see below
}
```

`weave/schema.lua` is the single source of truth for this shape — it's also where the recipe-authoring template comes from, so scaffolding a new recipe can never drift out of sync with the real schema:

```bash
lua recipes/recipe.lua > weave/recipes/<name>.lua
```

### Source kinds

A package's source kind is determined by its name in `fabric.lua`: a bare name (`"neovim"`) is `native`; a suffixed name (`"neovim.aur"`, `"neovim.nix"`) is foreign. Suffixes are a closed list — `aur` and `nix` are the only two recognized; anything else with a dot is treated as a literal part of the package name.

| Kind | Where it lives | How it resolves |
|---|---|---|
| `native` | `weave/recipes/<name>.lua` | You write the recipe yourself — fetch, verify, build, install into `ctx.destdir` |
| `aur` | Nothing to write | Weave clones the AUR package's git repo directly and parses the `PKGBUILD` for version + dependencies |
| `nix` | Nothing to write | Weave runs `nix eval` against nixpkgs and copies the resolved closure into `ctx.destdir` |

Only `native` recipes are hand-written — `aur` and `nix` resolve automatically from their respective upstreams. A `depends` entry can reference any kind, e.g. `depends = { "some-package.aur" }`.

### Writing a native recipe

```lua
return {
    name = "lua",
    version = "5.4.7",
    source = {
        kind = "native",
        url = "https://www.lua.org/ftp/lua-5.4.7.tar.gz",
        checksum = "...",
    },
    depends = {
        -- "some-package",                                  -- no version constraint
        -- { name = "some-package", constraint = ">=1.2" },  -- with a constraint
    },
    acquire = {
        steps = {
            { cmd = "curl -LO ${url}" },
            { cmd = "tar xzf lua-${version}.tar.gz" },
            { cmd = "cd lua-${version} && make linux" },
            { cmd = "cd lua-${version} && make install INSTALL_TOP=${destdir}/usr", confirm = "About to install Lua system-wide into destdir. Continue?" },
            { fn = function(ctx) ctx.log("build complete") end },
        },
    },
}
```

A few things worth knowing about `acquire.steps`:

- Each step is either a shell command (`cmd`) or a Lua function (`fn`) — they run in order, and every step gets a fresh shell, so a `cd` inside one step doesn't carry into the next. Chain related commands with `&&` inside one step if they need to share a working directory.
- Any step can carry a `confirm` string — a prompt shown before that step runs, requiring acknowledgment to continue. Skippable in non-interactive contexts by passing `{ yes = true }` to `executor.run()`.
- Every recipe writes its output to `ctx.destdir` and nothing else — a recipe never writes directly to the live system, and never needs to know or care what happens to `ctx.destdir` afterward.
- `${field}` inside a `cmd` string is substituted from `ctx` at execution time — `${destdir}`, `${srcdir}`, `${version}`, etc.

### Flavor-specific steps (optional)

```lua
acquire = {
    steps = { ... },        -- used for any flavor without a specific override
    steps_musl = { ... },   -- used only when ctx.flavor == "musl"
}
```

## Using Loom

Loom is the layer that turns Weave's output into a real, declarative system: it tracks numbered **generations**, stages built packages into an OSTree-committed tree plus a content-addressed `store/`, and lets you build, activate, preview, and roll back system states atomically.

**This is not a generic tool the way Weave is.** Loom is intentionally fused to this specific generation/rollback model — in the same way `nixos-rebuild` is fused to Nix's store and profile system. If you just want package resolution and building without any of this, see "Using Weave Standalone" above.

### The verbs

| Verb | Live? | Persists past reboot? | What it does |
|---|---|---|---|
| `loom test` | No | No | Build + validate only. No generation created, nothing touched. |
| `loom spin` | Yes | No | Live, temporary preview — reverts automatically on reboot. |
| `loom thread` | No | Yes | Full build + creates a generation, applies on next boot. |
| `loom bind` | Yes\* | Yes | Full build + creates a generation + swaps live now. |
| `loom unravel [gen]` | No | Yes | Revert to a previous generation (defaults to the one before current). |
| `loom set <n>` / `loom set list` | — | — | Set how many generations are retained (default 5) / list current generations. |

\* `loom bind`'s live swap only happens when the generation is eligible — see below.

### Why a live swap isn't always possible

Some changes can't safely apply without a reboot — a kernel change, an init system swap, a package that self-declares `requires_reboot = true` in its recipe, or any generation containing an AUR-sourced package (which, unlike native/nix packages, aren't symlink-swappable into a running system). `loom bind` checks for these automatically: if none apply, it does a live symlink-repoint of the running system; if one does, it creates the generation anyway (so it's ready on next boot) but explains why it can't apply it live right now.

### What a generation actually is

Each generation is an entry in `generations.json`, backed by:
- an OSTree commit (the whole filesystem tree for that generation), and
- `store/` — a content-addressed, deduplicated area holding native and nix-sourced package output, referenced from the OSTree tree via per-file symlinks rather than being copied in directly.

Generations sharing most of their files (the common case) don't duplicate that shared content on disk, the same way Nix profiles don't.

### Setup

- A system manifest at `/etc/silk/fabric.lua`, in the same shape shown under "Writing a Recipe" — `{ system = {hostname, libc, init}, packages = {...} }`.
- `/silk/store/`, `/silk/ostree/`, and `/silk/boot/loom/` to exist and be writable by Loom.
- The `/usr/bin/loom` launcher on `PATH`, pointing `LUA_PATH` at wherever `loom/` and `weave/` live.

## Adopting This Into Your Own Distro

There are two real levels of adoption here, and they're genuinely different amounts of work.

### Just Weave (small lift)

See "Using Weave Standalone" above. You'll need to:
- Write your own native recipes (or adapt the included ones)
- Point `weave/util/shell.lua` and anything else with a hardcoded path at your own layout
- Provide the unprivileged `loom-build` user if you want AUR support

Nothing else needs to change. Weave doesn't know or care what calls it.

### Weave + Loom together (bigger lift)

This is closer to "run your distro the way SilkOS does" than "add a feature." Concretely:

- **Update every hardcoded path** across `loom/manifest.lua`, `loom/state/*.lua`: `/etc/silk/fabric.lua`, `/silk/store`, `/silk/ostree/*`, `/silk/boot/loom/*`.
- **Have a working OSTree setup** on the target system — Loom shells out to the real `ostree` CLI, it doesn't reimplement any of it.
- **Provide your own installer step** that creates generation 0 by calling `generations.add()` — Loom has no bootstrapping logic of its own.
- **Decide on your own init system(s)** — Loom's manifest validation deliberately doesn't hardcode a list of "valid" init systems, but your own installer/bootloader integration will need to actually support whatever you declare.
- **Write your own bootloader integration** — Loom only ever writes `generations.json` and re-points the `current` deployment symlink; something on your system needs to actually read `generations.json` at boot time and select the right OSTree deployment. This piece doesn't exist in this repo.

If in doubt which level you're signing up for: `loom test` never touches generations or OSTree at all, and is a reasonable way to confirm Weave itself is working on your system before deciding whether to go further.

## License

GPLv3