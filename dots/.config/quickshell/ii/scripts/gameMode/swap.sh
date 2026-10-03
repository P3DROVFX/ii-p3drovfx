#!/usr/bin/env bash
# Swaps the full shell for the game mode shell (gameMode.qml) and back.
#   swap.sh enter <restoreHyprland 0|1>
#   swap.sh exit
#   swap.sh recover   (run by the full shell when it boots after game mode)
# Started with `setsid -f` from the shell it is about to kill, so it survives `qs kill`.
# $state/active marks a game mode session; it holds whether Hyprland's game mode
# overrides were added by entering (1) and must be removed on the way back. The full
# shell reads it on boot, so leaving and a plain shell restart restore things the same way.
set -u

dir="$(cd "$(dirname "$0")/../.." && pwd)"
state="${XDG_RUNTIME_DIR:-/tmp}/ii-game-mode"
mkdir -p "$state"

# Wallpapers painted by other processes (mpvpaper ~0.5 GB, Wallpaper Engine) go down too.
# Their exact command lines are kept so leaving game mode starts them as they were.
wallpaper_pids() {
    pgrep -x mpvpaper
    pgrep -f '^(\S*/)?linux-wallpaperengine( |$)'
}

case "${1:-}" in
enter)
    restore="${2:-0}"
    rm -f "$state"/wallpaper.*
    echo "$restore" > "$state/active"
    i=0
    for pid in $(wallpaper_pids); do
        cp "/proc/$pid/cmdline" "$state/wallpaper.$i" 2>/dev/null && i=$((i + 1))
    done
    # `qs kill` returns once the instance is gone and takes its helper daemons with it.
    qs kill -c ii >/dev/null 2>&1 || killall qs quickshell 2>/dev/null
    for pid in $(wallpaper_pids); do kill "$pid" 2>/dev/null; done
    setsid -f qs -p "$dir/gameMode.qml" >/dev/null 2>&1 </dev/null
    ;;
exit)
    qs kill -p "$dir/gameMode.qml" >/dev/null 2>&1
    MALLOC_CONF=narenas:1 setsid -f qs -c ii >/dev/null 2>&1 </dev/null
    ;;
recover)
    if [ -z "$(wallpaper_pids)" ]; then
        for f in "$state"/wallpaper.*; do
            [ -s "$f" ] && xargs -0 -a "$f" setsid -f >/dev/null 2>&1 </dev/null
        done
    fi
    rm -f "$state"/wallpaper.* "$state/active"
    ;;
*)
    echo "usage: $0 enter <0|1> | exit | recover" >&2
    exit 2
    ;;
esac
