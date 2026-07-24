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
