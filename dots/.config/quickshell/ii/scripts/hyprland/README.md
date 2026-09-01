# Hyprland Scripts

## Hyprland GUI writer (`hyprgui.py`)

Backs Settings -> Hyprland. It owns a fenced block at the **end** of each `~/.config/hypr/custom/*.lua`
file and leaves everything outside that fence byte for byte alone:

```lua
-- >>> quickshell:managed:begin v1 - written by Settings -> Hyprland. Edits here are overwritten; put your own Lua above.
hl.config({ input = { kb_layout = "fr" } })                     --@k input:kb_layout
hl.device({ name = "znt0001:00-14e5:e760-mouse", sensitivity = -0.2 })  --@d mouse-1
-- <<< quickshell:managed:end
```

The block sits last so its statements run after the hand-written ones in the same file and therefore
win. `hyprland.lua` loads `custom/env.lua` first, then `general`, `rules` and `keybinds`, and
`hyprland/shellOverrides/main.lua` after all of them — so Modes, Game Mode and the screen shader still
outrank anything written here.

Each generated line carries a `--@` tag naming what produced it (`k` config key, `d` device, `e` env,
`r` rule, `b` bind, `u` unbind), so reading the block back is a line-shaped parse rather than Lua
evaluation. A line whose tag this version does not recognise is kept verbatim and reported as
unrecognised, so a newer shell's output is never silently dropped by an older one.

`read` also reports `regionText` — the block exactly as it sits on disk, which is what the page's
Review dialog shows — and `backup`, the newest saved copy of that file with its mtime, so the page can
say how old the safety net is without a second process.

Every hand-written key found outside the fence carries its own `line` and a `span` — the exact byte
range of the assignment that sets it, not of the `hl.config` call it lives in. One call setting thirty
keys therefore reports thirty different lines, which is what lets the page say *"also set by hand at
general.lua:59"* and offer to remove that one line.

```bash
hyprgui.py read  --file ~/.config/hypr/custom/general.lua      # managed entries + what they override
hyprgui.py write --file ~/.config/hypr/custom/general.lua --json -   # desired state on stdin
hyprgui.py write --file ... --json - --dry-run                 # unified diff instead of a write
hyprgui.py strip --file ~/.config/hypr/custom/general.lua      # remove the block, keep the rest
hyprgui.py drop-key --file ... --key input:kb_layout           # delete one hand-written line
```

`drop-key` is the only command that touches Lua outside the fence, so it is deliberately timid. It
removes the *last* hand-written assignment of that key — the one Lua actually applies — then re-scans
the result and refuses to write unless every other setting in the file comes back identical, the
managed block is byte for byte where it was, and `luac -p` (when installed) still accepts the file.
`--dry-run` returns the same diff without writing, which is what the confirmation dialog shows.

`hyprgui_test.py` next to it exercises the round trip end to end — hand-written Lua preservation,
patterns containing `" \\ $ |`, unknown-tag forward compatibility, the no-op write, the path guard, and
write-then-strip returning each file byte for byte. Run it directly after touching the writer.

State arrives on **stdin, never argv**: window-rule patterns contain `$`, `|`, `\` and quotes, and none
of it should ever reach a shell.

Writes refuse any path outside `~/.config/hypr/custom/` (override with `--custom-dir` for tests), back
the file up to `$XDG_STATE_HOME/quickshell/hyprland-backups/` keeping the last 20 per file, and replace
it atomically. A write that would change nothing is skipped entirely — rewriting the file costs a
Hyprland reload, which drops every runtime-only option (border size and colour, gaps, rounding, blur)
back to whatever the Lua config says.

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

**Scope:** only the block of workspaces you are currently in takes part — the page the bar is
showing. With the default block size of 10, standing on workspace 12 compacts 11–20 into 11..N and
leaves 1–10 exactly where they are; windows never migrate between pages.

**Multi-monitor:** only the focused monitor's workspaces are touched, and the "1..N" range is
relative to that monitor, not global — compacting monitor 2 lands its windows in its own range
instead of monitor 1's. It works out the range the same way the bar does: if
`bar.workspaces.useWorkspaceMap` is enabled (Settings → Bar → Workspaces → Display Options), it
reads `workspaceMap`/`shown` from `~/.config/illogical-impulse/config.json` directly, so it always
agrees with what the bar shows. Otherwise it falls back to the `workspace_in_group()` block
convention from `~/.config/hypr/hyprland/lib/init.lua` (fixed-size blocks of `workspaceGroupSize`
per monitor, 10 by default), reading `workspaceGroupSize` out of
`~/.config/hypr/custom/variables.lua` (or the shipped `hyprland/variables.lua`) so a changed block
size is picked up on its own. Passing a block size as the first argument to the binary still
overrides it (see keybind below).

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

`workspaceGroupSize` is read from your Hyprland config automatically, so a changed block size
needs no keybind edit. Pass it as an argument only to override that (and only when
`useWorkspaceMap` is off — see above):

```lua
hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_compactor 10")
```
