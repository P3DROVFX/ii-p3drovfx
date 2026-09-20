# sni_watcher

Keeps system tray icons alive across a shell restart.

**Binary:** `~/.config/quickshell/ii/scripts/tray/sni_watcher`
**Source:** `~/.config/quickshell/ii/scripts/tray/sni_watcher_src/`

## Why a helper is needed

The tray is two halves. Apps export a *StatusNotifierItem* and announce it to a
*StatusNotifierWatcher*, which owns the bus name `org.kde.StatusNotifierWatcher`
and tells every *host* — the thing that draws icons — what exists. Quickshell
ships all three, so the watcher lives and dies with the shell.

Stopping the shell therefore drops the watcher's bus name, and the instance that
takes it back starts with an empty item list. The protocol has no way to tell a
client that its watcher changed, so what happens next is up to each app:

- **Chromium, so every Electron app** (Discord, Vesktop, Deezer) re-registers
  when the name gets a new owner — and if that call fails, `OnRegistered` calls
  `OnImplInitializationFailed`, which tears the icon down and falls back to a
  GTK status icon, i.e. nothing at all on Wayland. The D-Bus object is
  unexported at that point, so no amount of re-registering from outside can
  bring it back.
- **Steam, Go clients, older Electron** never watch the name and are simply
  gone from the tray.
- **Qt apps and libayatana-appindicator** re-register and come back fine.

That is why tray icons disappear after an update: the update restarts the shell.

## What it does

It is the watcher, in a process that does not restart. Quickshell claims
`org.kde.StatusNotifierWatcher` only when it is free and otherwise acts as a
plain host against whoever holds it, so nothing in the shell has to change —
it finds the helper's watcher and asks it for the items.

With the name never changing hands, no client ever learns that the shell went
away, and every icon is still registered when the new shell asks.

Two details make the handover itself safe:

- **The name is requested queued.** If a shell is already holding it, ownership
  passes to the helper the moment that shell exits, without the name ever being
  unowned. The helper never asks to replace a running shell, and never allows
  itself to be replaced.
- **Whenever it gains the name it sweeps the bus.** Items registered with the
  previous watcher are still alive but unknown to the new one, so every
  connection is probed for a StatusNotifierItem and the ones that answer are
  adopted. At login that sweep finds nothing — the helper runs before anything
  with a tray icon.

`IsStatusNotifierHostRegistered` always answers true, as Quickshell's own
watcher does: a client that asks while the shell is still starting would
otherwise conclude there is no tray and tear its own icon down.

## Running it

Started from `~/.config/hypr/hyprland/execs.lua` before the shell, so it is
already holding the name when Quickshell starts. If it is not running,
Quickshell registers its own watcher as before and only the restart protection
is lost.

## Building

```bash
~/.config/quickshell/ii/scripts/rust-helpers.sh build sni_watcher
```

Pure Rust (`zbus`), so there is nothing to install beyond a Rust toolchain.
Costs about 4 MB of RAM and no CPU at all while nothing changes.
