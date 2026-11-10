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
`r` rule, `b` bind, `u` unbind, `g` global, `c` curve, `a` animation), so reading the block back is a line-shaped parse rather than Lua
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

Settings → Windows uses the same writer through `HyprlandGui.saveWindowsSettings()`.
Its FAB explicitly saves the current window animations, gaps, border and blur settings;
it also saves any changes already staged on the Hyprland page. The FAB compares against
the stored entries, not against the last click, so failed writes and edits during a write
remain pending. Animation curves precede the animation leaves that reference them.
Shell-only transparency preferences remain in Config; they are not compositor settings.

## Workspace Profile Manager

A high-performance Rust backend that captures live Hyprland clients via `hyprctl`, saves them as JSON profiles, and restores layouts on demand. Used by the Cheatsheet.

**Binary:** `~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager`
**Source:** `~/.config/quickshell/ii/scripts/hyprland/workspace_profile_manager_src/`

**Data:** Profiles are saved as JSON to `~/.config/illogical-impulse/workspace_profiles/` — safe to back up or sync across machines, and will survive dots updates.

### Rebuilding from Source

Only needed if you've modified the Rust source. Requires Rust/`cargo` ([install via rustup](https://rustup.rs)).

```bash
~/.config/quickshell/ii/scripts/rust-helpers.sh build workspace_profile_manager
```

## Workspace Arranger

Arranges the focused monitor's workspace numbering, in both directions: it closes gaps and opens
new workspaces in between. Nothing is moved between workspaces — the workspaces themselves are
renumbered, so every window keeps its exact place (split tree and ratios, floating geometry,
fullscreen state, groups). Special and named workspaces are left untouched. It was called the
Workspace Compactor before it could insert; config written by older versions is migrated on load
(config v30), but a custom keybind calling `workspace_compactor` must be renamed.

**Closing gaps** (no arguments) renumbers the occupied workspaces to 1..N — with apps on 2, 4
and 5, they become 1, 2 and 3. Bound to `CTRL + SUPER + C`; Settings → Workspaces → Workspace
Arranger can also do it automatically whenever a gap appears.

The active workspace follows its own contents to their new number. If it was left empty, focus
falls back to the nearest occupied workspace below it.

**Scope:** only the block of workspaces you are currently in takes part — the page the bar is
showing. With the default block size of 10, standing on workspace 12 arranges 11–20 as 11..N and
leaves 1–10 exactly where they are; windows never migrate between pages.

**Multi-monitor:** only the focused monitor's workspaces are touched, and the "1..N" range is
relative to that monitor, not global — arranging monitor 2 lands its windows in its own range
instead of monitor 1's. It works out the range the same way the bar does: if
`bar.workspaces.useWorkspaceMap` is enabled (Settings → Bar → Workspaces → Display Options), it
reads `workspaceMap`/`shown` from `~/.config/illogical-impulse/config.json` directly, so it always
agrees with what the bar shows. Otherwise it falls back to the `workspace_in_group()` block
convention from `~/.config/hypr/hyprland/lib/init.lua` (fixed-size blocks of `workspaceGroupSize`
per monitor, 10 by default), reading `workspaceGroupSize` out of
`~/.config/hypr/custom/variables.lua` (or the shipped `hyprland/variables.lua`) so a changed block
size is picked up on its own. Passing a block size as the first argument to the binary still
overrides it (see keybind below).

**Inserting a workspace:** `--insert=before|after|first` does the reverse. It opens an empty
workspace before or after the active one, or at the start of the block, by shifting the occupied
workspaces in the way up by one, and takes you there. `--take` brings the focused window with it.
The shift stops at the first free id, so later gaps are kept. When the block has no free id left,
the binary refuses and sends a notification. Bound to `CTRL + SUPER + I` (after),
`CTRL + SUPER + SHIFT + I` (before) and `CTRL + SUPER + Home` (first); `SUPER + ALT` instead of
`CTRL + SUPER` takes the window along. With automatic gap closing on, an inserted workspace you
leave empty is closed again as usual.

**Source:** `~/.config/quickshell/ii/scripts/hyprland/workspace_arranger_src/`

### Building from Source

Requires Rust/`cargo` ([install via rustup](https://rustup.rs)). The binary is not shipped — build
it once and the keybind picks it up.

```bash
~/.config/quickshell/ii/scripts/rust-helpers.sh build workspace_arranger
```

`rust-helpers.sh` installs through a rename and stamps the binary with a hash of the
sources it came from, so `rust-helpers.sh status` can say afterwards whether an update
has left it behind.

### Keybind

In `~/.config/hypr/hyprland/keybinds.lua`:

```lua
local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"

--#/# bind = CTRL+SUPER, C,, -- Close workspace gaps (renumber into 1..N)
hl.bind("CTRL + SUPER + C", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger"),
    { description = "Workspaces: Close gaps (renumber into 1..N)" })
hl.bind("CTRL + SUPER + I", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=after"),
    { description = "Workspaces: Insert empty workspace after current" })
```

The shipped file binds all six insert variants (see "Inserting a workspace" above).

`qsScripts` is already declared at the top of that file — you only need that line if you put the
bind somewhere else, like `~/.config/hypr/custom/keybinds.lua`.

`workspaceGroupSize` is read from your Hyprland config automatically, so a changed block size
needs no keybind edit. Pass it as an argument only to override that (and only when
`useWorkspaceMap` is off — see above):

```lua
hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger 10")
```
