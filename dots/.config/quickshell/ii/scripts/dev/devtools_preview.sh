#!/usr/bin/env bash
# Render Dev tools previews off-screen: a private headless kwin + a sandboxed qs
# running scripts/dev/devtools_preview.qml from THIS checkout. The QML is copied
# to the checkout root for the run (qs resolves `qs.*` imports from there) and
# removed after, so run it from a worktree, not the checkout the live shell
# watches: a new root file would hot-reload the live shell.
#
#   scripts/dev/devtools_preview.sh OUT_DIR TOOL_ID[,TOOL_ID...] [INPUTS_JSON] [OPTIONS_JSON]
#
#   INPUTS_JSON   {"tool_id": "input text"}       (optional; default = sample input)
#   OPTIONS_JSON  {"tool_id": {"option": value}}  (optional)
#
# Writes OUT_DIR/<tool>-page.png (cheatsheet page, 1546x900) and
# OUT_DIR/<tool>-search.png (Search Tools panel, 760x640), plus OUT_DIR/qs.log.
# Lines starting with "DTPREVIEW" in the log show each tool's error/output.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
TOOLS="$2"
INPUTS="${3:-{\}}"
OPTIONS="${4:-{\}}"
ID="dtprev-$$-$RANDOM"
RUN="$(mktemp -d "${TMPDIR:-/tmp}/$ID.XXXX")"
SOCKET="$ID"

# Sandbox XDG dirs: the live config and colours, copied, so nothing is written back.
mkdir -p "$RUN/config/illogical-impulse" "$RUN/state/quickshell/user" "$RUN/cache"
cp "$HOME/.config/illogical-impulse/config.json" "$RUN/config/illogical-impulse/" 2>/dev/null
cp -r "$HOME/.local/state/quickshell/user/generated" "$RUN/state/quickshell/user/" 2>/dev/null

cleanup() {
    [ -n "${QS_PID:-}" ] && kill "$QS_PID" 2>/dev/null
    [ -n "${KWIN_PID:-}" ] && kill "$KWIN_PID" 2>/dev/null
    rm -rf "$RUN"
    rm -f "$PREVIEW_QML"
}
trap cleanup EXIT
PREVIEW_QML="$ROOT/.devtools_preview.qml"
cp "$ROOT/scripts/dev/devtools_preview.qml" "$PREVIEW_QML"

(unset WAYLAND_DISPLAY DISPLAY; exec kwin_wayland --virtual --width 1920 --height 1080 --socket "$SOCKET" --no-lockscreen --no-global-shortcuts) > "$OUT/kwin.log" 2>&1 &
KWIN_PID=$!
for _ in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && break; sleep 0.1; done
if [ ! -S "$XDG_RUNTIME_DIR/$SOCKET" ]; then echo "kwin did not start (see $OUT/kwin.log)"; exit 1; fi

(
    export XDG_CONFIG_HOME="$RUN/config" XDG_STATE_HOME="$RUN/state" XDG_CACHE_HOME="$RUN/cache"
    export WAYLAND_DISPLAY="$SOCKET" DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent
    # Marks a throwaway shell: Modes and its tasks stay off (an empty state dir
    # would otherwise make every catch-up routine run the user's real commands).
    export II_SANDBOX=1
    export DT_TOOLS="$TOOLS" DT_OUT="$OUT" DT_INPUTS="$INPUTS" DT_OPTIONS="$OPTIONS"
    unset HYPRLAND_INSTANCE_SIGNATURE DISPLAY
    exec qs -p "$PREVIEW_QML"
) > "$OUT/qs.log" 2>&1 &
QS_PID=$!

# ~1 s per step: 2 per tool per view + loads, plus boot time.
COUNT=$(echo "$TOOLS" | tr ',' '\n' | grep -c .)
LIMIT=$((40 + COUNT * 5))
for _ in $(seq "$LIMIT"); do
    grep -q "DTPREVIEW done" "$OUT/qs.log" 2>/dev/null && break
    kill -0 "$QS_PID" 2>/dev/null || break
    sleep 1
done
sleep 1
grep -a "DTPREVIEW" "$OUT/qs.log" | sed 's/.*DTPREVIEW /  /'
grep -aE "WARN|ERROR" "$OUT/qs.log" | grep -aiE "devtools|cheatsheet|ToolsPanel|Registry|TypeError|ReferenceError|unavailable" | head -20
ls "$OUT"/*.png 2>/dev/null
