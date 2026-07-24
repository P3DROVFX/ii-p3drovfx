# Hyprland Scripts

## Workspace Profile Manager

A high-performance Rust backend that captures live Hyprland clients via `hyprctl`, saves them as JSON profiles, and restores layouts on demand. Used by the Cheatsheet.

**Binary:** `~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager`
**Source:** `~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager_src/`

**Data:** Profiles are saved as JSON to `~/.config/illogical-impulse/workspace_profiles/` — safe to back up or sync across machines, and will survive dots updates.

### Rebuilding from Source

Only needed if you've modified the Rust source. Requires Rust/`cargo` ([install via rustup](https://rustup.rs)).

```bash
cd ~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager_src
cargo build --release
cp target/release/workspace_profile_manager ../
```

## Workspace Compactor

Renumbers the focused monitor's workspaces so the occupied ones run 1..N with no gaps — with
apps on 2, 4 and 5, it pulls them down to 1, 2 and 3. Windows sharing a workspace stay together
and keep their order, floating geometry is restored exactly, and tiled geometry is replayed
best-effort so dwindle's split ratios land close to where they were. Special and named
workspaces are left untouched. Bound to `CTRL + SUPER + C`.

The active workspace follows its own contents to their new number. If it was left empty, focus
falls back to the nearest occupied workspace below it.

**Multi-monitor:** only the focused monitor's workspaces are touched, and the "1..N" range is
relative to that monitor, not global — compacting monitor 2 lands its windows in its own range
instead of monitor 1's. It works out the monitor's range the same way the bar does: if
`bar.workspaces.useWorkspaceMap` is enabled (Settings → Bar → Workspaces → Display Options), it
reads `workspaceMap`/`shown` from `~/.config/illogical-impulse/config.json` directly, so it always
agrees with what the bar shows. Otherwise it falls back to the `workspace_in_group()` block
convention from `~/.config/hypr/hyprland/lib/init.lua` (fixed-size blocks of `workspaceGroupSize`
per monitor, 10 by default) — pass a different block size as the first argument to the binary if
you've changed `workspaceGroupSize` away from 10 (see keybind below).

**Source:** `~/.config/quickshell/ii/scripts/hyprland/workspace_compactor_src/`

### Building from Source

Requires Rust/`cargo` ([install via rustup](https://rustup.rs)). The binary is not shipped — build
it once and the keybind picks it up.

```bash
cd ~/.config/quickshell/ii/scripts/hyprland/workspace_compactor_src
cargo build --release
cp target/release/workspace_compactor ../
```

### Keybind

In `~/.config/hypr/hyprland/keybinds.lua`:

```lua
local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"

--#/# bind = CTRL+SUPER, C,, -- Compact workspaces into 1..N (remove empty gaps)
hl.bind("CTRL + SUPER + C", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_compactor"),
    { description = "Workspaces: Compact into 1..N (remove empty gaps)" })
```

`qsScripts` is already declared at the top of that file — you only need that line if you put the
bind somewhere else, like `~/.config/hypr/custom/keybinds.lua`.

If you've changed `workspaceGroupSize` in `~/.config/hypr/custom/variables.lua` away from its
default of 10, pass the same number as an argument (only used as a fallback when
`useWorkspaceMap` is off — see above):

```lua
hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_compactor 10")
```
