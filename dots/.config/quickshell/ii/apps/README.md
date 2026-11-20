# apps/ — standalone shell apps

Apps that look exactly like the shell (Material 3 Expressive, same widgets, same
live palette) but run in **their own process**. Closing one returns every byte to
the system, and the shell itself never grows.

```bash
qs -p ~/.config/quickshell/ii/apps/files.qml                                # start
qs -p ~/.config/quickshell/ii/apps/files.qml ipc call files open ~/Pictures # reuse the running one
qs -p ~/.config/quickshell/ii/apps/files.qml ipc call files quit            # exit the process
```

## Why a separate process

QML singletons can't be destroyed and neither the JS heap nor the allocator give
memory back. A panel opened inside the shell keeps a share of its memory after it
closes (measured: Settings +57 MB, Notes +57 MB, VideoEditor +36 MB), and that
adds up over a session. A separate `qs -p` process has no such leftovers: when it
exits, the kernel reclaims all of it.

There's a catch: the shell's `modules/common` is not meant to be imported on its
own. Pulling in the real `Appearance`/`Config` boots half the shell:

| Same window (sidebar + toolbar + folder grid) | PSS | Child processes |
|---|---|---|
| Plain Quickshell + QtQuick.Controls, no shell imports | ~79 MB | 0 |
| Shell's real `Appearance` + `Config` + `MaterialThemeLoader` | ~165 MB | ~24 at boot |
| Real singletons minus `Config` (slim `Appearance`) | ~150 MB | 1-3 |
| **This runtime** (`files.qml`) | **93 MB** | **0** |

With the real singletons the window also registered a notification server, started
IiLink, ran a vdirsyncer calendar sync and left an orphaned `avahi-browse` behind
when it was killed. Every one of those comes in through a singleton, not the window.

## How imports resolve

Quickshell treats the folder of the entry file as the `qs` root. For
`qs -p apps/files.qml` that is `apps/`, so:

```
import qs                        → apps/                (GlobalStates.qml)
import qs.modules.common         → apps/modules/common/ (slim singletons below)
import qs.modules.common.widgets → apps/modules/common/widgets → symlink to the shell's widgets
import qs.services               → apps/services/       (Translation.qml only)
```

The shell's widgets never notice the change. They still say
`import qs.modules.common` and `Appearance.colors.colLayer1`, but in an app process
those names resolve to the stand-ins.

The running shell never sees this folder. Quickshell's scanner
(`src/core/scan.cpp`) starts at `shell.qml` and follows import lines only, and
nothing in the shell imports `qs.apps`. So `apps/` is never scanned or watched,
and editing it never hot-reloads the shell.

## The stand-ins

| File | Replaces | What it keeps / drops |
|---|---|---|
| `modules/common/Appearance.qml` | `Appearance` | **Generated.** Keeps the token blocks (`m3colors`, `colors`, `rounding`, `font`, `animationCurves`, `animation`, `sizes`, `windowRounding`, `animMultiplier`, `reducedMotion`) word for word, plus a `colors.json` watcher. Drops the `hyprctl` pushes (rules, gaps, borders, blur), the wallpaper quantizer and `qs.services`. |
| `modules/common/Config.qml` | `Config` | Read-only snapshot of the shell's `config.json`, re-read when it changes. Keeps only the dotted paths in `sections`. Never writes. |
| `modules/common/Directories.qml` | `Directories` | Same paths and names. Drops the startup `mkdir`s and the `rm -rf` the real one runs on shell caches (cover art, cliphist, previews). Adds `appsState`. |
| `modules/common/PanelFamily.qml` | `PanelFamily` | `isTablet`/`touchFirst` pinned to `false`: apps are desktop windows. |
| `GlobalStates.qml` | `GlobalStates` | Every member the shared widgets read, inert. The real one binds to Notifications and HyprlandData, and `StyledToolTip` (inside every `RippleButton`) reads it, so without this any button boots KdeConnect, IiLink and the notification server. |
| `services/Translation.qml` | `Translation` | Same `tr()` over the same `translations/*.json`, minus the language scanner processes. `en_US` reads nothing. It is the only service apps get. |

Everything else is a symlink back to the shell: `modules/common/{widgets,functions,animations,models}`,
`assets`, `translations` and `scripts` (the last three for `Quickshell.shellPath()`).

### Theme and config flow

```
matugen ─► ~/.local/state/quickshell/user/generated/colors.json ─► Appearance (FileView, watched)
Settings ─► ~/.config/illogical-impulse/config.json             ─► Config (FileView, watched, read-only)
```

A wallpaper or scheme change repaints an open app right away, just like the shell.
The shell writes `config.json` in several steps, so a half-written file can fail to
parse. Both readers then keep the previous value and wait for the next change event.

### Process lifecycle

- Each app is one process. Its entry declares an `IpcHandler` (`target: "files"`),
  so a launcher can reuse the running instance (`ipc call files open <dir>`)
  instead of starting a second one.
- Closing the window calls `Qt.quit()`, and so does `ipc call files quit`. Both end
  the `qs -p` process (verified).
- `qs -p` instances don't match `qs -c ii` for IPC: always address them by path
  (`qs -p <entry> ipc ...`).

## Adding an app

1. Create `apps/<name>.qml` (the entry) and, if it grows, `apps/<name>/` for its
   components (import it as `qs.<name>`).
2. Start from `files.qml`'s header: `UseQApplication`, `QS_NO_RELOAD_POPUP`, the
   Basic controls style, an `ApplicationWindow` with `onClosing: Qt.quit()` and an
   `IpcHandler`.
3. Keep app settings in `${Directories.appsState}/<name>.json`, never in the shell's
   `config.json`. The shell's JsonAdapter drops keys it doesn't know.

## Reusing a shell widget

- It reads a config path that isn't in `Config.sections` → add the path (a whole
  section like `"time"` or a single leaf like `"bar.sizes"`). Only listed paths are
  kept, so the app's heap stays small.
- It reads a service (77 of the 226 shared widgets import `qs.services`) → write a
  slim replacement in `apps/services/`. **Never link the shell's `services/`**: that
  is how half the shell comes back.
- It references a shell singleton that has no stand-in here (`Persistent`,
  `LocalPreferences`, the registries…) → you get a ReferenceError in the log. That's
  on purpose: an error is easy to see, while a silent copy of the shell's state
  would not be.

## Keeping Appearance in sync

`modules/common/Appearance.qml` is generated. Don't edit it. After changing tokens in
the shell's `modules/common/Appearance.qml`:

```bash
python3 scripts/apps/sync_app_appearance.py          # regenerate
python3 scripts/apps/sync_app_appearance.py --check  # exit 1 if stale
```

The generator finds blocks by name, so new tokens inside existing blocks come along
on their own. It fails when a block disappears or when a shell-only reference
(`hyprctl`, `HyprlandConfig`, `BarInteraction`…) leaks into the tokens. The bar
references the tokens do have are pinned to "no bar" values (see `SUBSTITUTIONS`).

## Measuring

Read `/proc/<pid>/smaps_rollup` (`Pss`, `Pss_Anon`) of the `qs -p` process and count
its children (`pgrep -P <pid>`). Numbers for `files.qml` (2026-11-20):

| State | PSS | Anon | Children |
|---|---|---|---|
| Idle in `~` | 93 MB | 56 MB | 0 |
| After opening `/usr/share` | 99 MB | 62 MB | 0 |
| After opening `/usr/bin` (thousands of entries) | 101 MB | 63 MB | 0 |
| After closing | 0 in the shell | | |

`GridView` only creates the visible delegates, so memory doesn't grow with the
number of files in a folder.

## Pitfalls

- QV4 rejects `??=` (and the rest of the logical-assignment family). Use an explicit `if`.
- A broken stand-in fails the whole app ("Type Appearance unavailable"): read the
  `qs -p` output, not the window.
- Don't run probes against the shell's real singletons and kill them: they leave an
  orphaned `avahi-browse` (the adb discovery helper) behind.
