# Weave

Weave is the declarative package resolution and build system for SilkOS — a non-systemd, Nix-Like Linux distribution configured entirely in Lua. Weave is what `fabric.lua` (SilkOS's system manifest, akin to `configuration.nix`) actually calls into to turn a list of declared packages into real, built software on disk.

> **Status: early, active development.** Weave is not yet functional end-to-end. Core resolution (`parser` → `schema` → `resolver` → `sources/*`) works for native packages; the execution engine (`executor.lua`) and storage staging (OSTree/`store/` commit) are still being built out. Expect breaking changes.

## What Weave does

A SilkOS system declares its packages like this, in `fabric.lua`:

```lua
local weave = require("silk.weave")

return {
    packages = {
        "neovim",                          -- native Silk recipe
        weave.aur("spotify-launcher"),     -- built from the AUR
        weave.nix("ripgrep-all"),          -- fetched from nixpkgs
        weave.deb("custom-tool_1.0.deb"),  -- unpacked from a .deb
    },
}
```

Weave takes that list and, for each entry:

1. **Parses** the package string to determine its source kind (bare name = native; `.aur`/`.nix`/`.deb` suffix = foreign)
2. **Resolves** it into a full `Recipe` — fetching metadata from the right place for its kind (a local recipe file, a cloned AUR repo, a live Nix evaluation, or a declared `.deb` URL)
3. **Validates** the resolved `Recipe` against a single canonical schema, regardless of where it came from
4. **Walks the dependency graph**, resolving and ordering every transitive dependency, with cycle detection and (for AUR) version-constraint checking
5. **Executes** each recipe's build/acquire steps, producing package output ready for SilkOS's storage layer

Every source kind normalizes to the same `Recipe` shape and converges on the same output contract — write to `ctx.destdir`, know nothing about how the result gets staged into the final system. This keeps four very differently-behaved package ecosystems (a Lua-native build, an AUR `makepkg` build, a Nix store fetch, and a raw `.deb` unpack) resolvable through one consistent pipeline.

## Package sources

| Kind | How it resolves | What it produces |
|---|---|---|
| **native** | `require()`s a recipe file from `weave/recipes/<name>.lua` | Built from source, per the recipe's own `acquire.steps` |
| **aur** | Git clones the AUR package repo directly, sources the `PKGBUILD` for version + dependencies | Built via `makepkg --nodeps`, run as an unprivileged `loom-build` user |
| **nix** | Live `nix eval` against nixpkgs (flakes) | Full dependency closure copied into SilkOS's own store, original Nix hash preserved |
| **deb** | A recipe file declaring an explicit URL | Unpacked manually via `ar`/`tar` — no `dpkg` dependency |

## Repository layout

```
weave/
├── parser.lua           -- package-string parsing ("neovim.aur" -> {name, kind})
├── resolver.lua          -- dependency graph walk, cycle detection, source dispatch
├── schema.lua             -- canonical Recipe shape, validation, recipe template
├── executor.lua            -- runs acquire.steps, builds ctx, handles confirm prompts
├── sources/
│   ├── native.lua
│   ├── aur.lua
│   ├── nix.lua
│   └── deb.lua
├── util/
│   ├── shell.lua           -- shared shell-command execution helper
│   └── version.lua          -- minimal version constraint comparison
└── recipes/
    ├── recipe.lua            -- generator script; scaffolds new native recipes
    └── lua.lua                 -- first real native recipe
```

## Writing a native recipe

Every recipe, regardless of source, follows the same shape (defined in `schema.lua`):

```lua
return {
    name = "...",
    version = "...",
    source = { kind = "native", url = "...", checksum = "..." },
    depends = {
        -- "some-package",                                   -- no version constraint
        -- { name = "some-package", constraint = ">=1.2" },  -- with a constraint
    },
    acquire = {
        steps = {
            { cmd = "..." },
            { cmd = "...", confirm = "About to do something risky. Continue?" },
            { fn = function(ctx) ... end },
        },
    },
}
```

Scaffold a new one rather than writing the shape by hand — this keeps every recipe in sync with the schema automatically:

```sh
lua recipes/recipe.lua > weave/recipes/<name>.lua
```

`acquire.steps` entries are either a shell command (`cmd`) or a Lua function (`fn`), run in order. Any step can carry a `confirm` string, which pauses for interactive acknowledgment before running (skippable with `loom switch --yes`).

## Design principles

- **One resolution path.** Every source kind normalizes to the same `Recipe` shape and is validated the same way, regardless of how differently each ecosystem actually works under the hood.
- **Recipes don't know about storage.** Every source writes to `ctx.destdir` and stops — deciding whether that output becomes part of SilkOS's content-addressed store or gets bundled into an OSTree commit is a separate, later concern recipes never have to think about.
- **Authoritative over cached.** Where a choice existed (AUR: RPC API vs. git clone; Nix: live eval vs. a pinned mapping), Weave favors fetching directly from the real source over a cached/indirect index.

## License

GPLv3
