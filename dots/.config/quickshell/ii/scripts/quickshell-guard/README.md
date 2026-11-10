# quickshell-guard

The shell is its own notification daemon, so when it cannot start nothing on screen
says why. The usual reason is a Qt update that Quickshell was not rebuilt for. These
scripts cover the three moments that matters, without needing the shell:

| When | What | Script |
|---|---|---|
| During the update | A pacman hook runs `quickshell --private-check-compat` after a Qt or Quickshell upgrade. On a mismatch it warns in pacman's output and on every running Hyprland session: rebuild before you log out or reboot. | `ii-quickshell-qt.hook`, `quickshell-qt-check.sh` |
| At login and on Ctrl+Super+R | Hyprland starts the shell through the guard. A shell that crashes twice in its first 30 s, or whose config never answers over IPC, has not started: the guard says so, and when Qt is the reason it opens a terminal on the rebuild script. A later crash restarts it, at most 3 times in 10 minutes. | `qs-guard.sh` |
| To fix it | Rebuilds the package after asking: `yay -S --rebuild` for an AUR build, a full update (then `quickshell-git`) for a repository package. Then starts the shell again. | `qs-rebuild.sh` |

Messages use `hyprctl notify`, which Hyprland draws itself.

## Settings

`health.guard.enable` and `health.guard.openTerminal` in `config.json`, edited from
System Health's Settings page (*When the shell cannot start*). The guard reads them at
start with `jq`; without `jq` both stay on.

## The pacman hook

```bash
sudo ~/.config/quickshell/ii/scripts/quickshell-guard/install-hook.sh install
sudo ~/.config/quickshell/ii/scripts/quickshell-guard/install-hook.sh remove
     ~/.config/quickshell/ii/scripts/quickshell-guard/install-hook.sh status
```

Setup offers it once; Settings installs or removes it through pkexec. The hook runs as
root, so its script is copied to `/usr/local/lib/ii/quickshell-qt-check`, owned by root;
pacman never runs anything from the home directory.

## Testing

`QS_GUARD_DRY=1 qs-guard.sh -c ii` prints the notifications and the terminal command
instead of showing them. A fake `qs` first on `PATH` can stand in for a mismatch
(`--private-check-compat` exiting 1) or a crash.
