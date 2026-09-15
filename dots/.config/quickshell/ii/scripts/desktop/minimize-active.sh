#!/usr/bin/env bash
# minimize the active window to its OWN special workspace (special:desktop-min-<addr>) so
# restoring one app never drags the others out. mirrors AkebonoStash.minimize() in qml.

set -uo pipefail

addr="$(hyprctl activewindow -j | jq -r '.address // empty')"
[ -n "$addr" ] && hyprctl dispatch "hl.dsp.window.move({ workspace = \"special:desktop-min-$addr\", follow = false, window = \"address:$addr\" })"