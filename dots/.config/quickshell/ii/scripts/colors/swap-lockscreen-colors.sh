#!/usr/bin/env bash
# swap-lockscreen-colors.sh
# Atomically swaps colors.json between lockscreen and desktop palettes.
# Uses a write-in-place strategy (not rename/mv) so FileView watchChanges triggers.
# Usage:
#   swap-lockscreen-colors.sh lock    → copies lockscreen_colors.json → colors.json
#   swap-lockscreen-colors.sh unlock  → copies desktop_colors.json   → colors.json

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"

CURRENT_COLORS="$STATE_DIR/user/generated/colors.json"
LOCKSCREEN_COLORS="$STATE_DIR/user/generated/lockscreen_colors.json"
DESKTOP_COLORS="$STATE_DIR/user/generated/desktop_colors.json"

# Write content into the watched file in-place so inotify fires on the same inode
write_in_place() {
    local src="$1"
    local dst="$2"
    # cat > dst rewrites content of existing file → same inode → inotify IN_MODIFY fires
    cat "$src" > "$dst"
}

action="${1:-lock}"

case "$action" in
    lock)
        if [[ ! -f "$LOCKSCREEN_COLORS" ]]; then
            echo "[swap-lockscreen-colors] lockscreen_colors.json not found, skipping" >&2
            exit 0
        fi
        # Backup current desktop colors if not already backed up
        if [[ -f "$CURRENT_COLORS" && ! -f "$DESKTOP_COLORS" ]]; then
            cp "$CURRENT_COLORS" "$DESKTOP_COLORS"
        fi
        write_in_place "$LOCKSCREEN_COLORS" "$CURRENT_COLORS"
        echo "[swap-lockscreen-colors] Switched to lockscreen colors"
        ;;
    unlock)
        if [[ ! -f "$DESKTOP_COLORS" ]]; then
            echo "[swap-lockscreen-colors] desktop_colors.json not found, skipping" >&2
            exit 0
        fi
        write_in_place "$DESKTOP_COLORS" "$CURRENT_COLORS"
        echo "[swap-lockscreen-colors] Restored desktop colors"
        ;;
    *)
        echo "Usage: $0 lock|unlock" >&2
        exit 1
        ;;
esac
