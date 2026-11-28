#!/usr/bin/env bash
# One-click installer/uninstaller to set or remove ii Gallery as the default
# Linux photo viewer (XDG MIME + NoDisplay=true .desktop entry).
#
# Usage:
#   set_default_viewer.sh status
#   set_default_viewer.sh enable
#   set_default_viewer.sh disable
#   set_default_viewer.sh toggle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN_SCRIPT="$(realpath "$SCRIPT_DIR/open_in_gallery.sh")"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_ID="ii-gallery.desktop"
DESKTOP_FILE="$APPS_DIR/$DESKTOP_ID"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/apps"
BACKUP_FILE="$STATE_DIR/gallery-prev-mime.json"

IMAGE_MIMES=(
    "image/jpeg"
    "image/png"
    "image/webp"
    "image/gif"
    "image/bmp"
    "image/avif"
    "image/heic"
    "image/heif"
    "image/x-portable-pixmap"
)

is_default() {
    local png_def jpg_def
    png_def="$(xdg-mime query default image/png 2>/dev/null || true)"
    jpg_def="$(xdg-mime query default image/jpeg 2>/dev/null || true)"
    [ "$png_def" = "$DESKTOP_ID" ] && [ "$jpg_def" = "$DESKTOP_ID" ]
}

cmd_status() {
    local def="false"
    if is_default; then
        def="true"
    fi
    local png_def
    png_def="$(xdg-mime query default image/png 2>/dev/null || true)"
    printf '{"ok":true,"isDefault":%s,"current":"%s"}\n' "$def" "${png_def//\"/}"
}

cmd_enable() {
    mkdir -p "$APPS_DIR" "$STATE_DIR"

    # Save previous default handlers once (so 1-click remove restores them cleanly)
    if [ ! -f "$BACKUP_FILE" ]; then
        python3 - "$BACKUP_FILE" "$DESKTOP_ID" "${IMAGE_MIMES[@]}" <<'PY'
import json, subprocess, sys
out_file, self_id = sys.argv[1], sys.argv[2]
mimes = sys.argv[3:]
prev = {}
for m in mimes:
    try:
        r = subprocess.run(["xdg-mime", "query", "default", m], capture_output=True, text=True, timeout=3)
        val = r.stdout.strip()
        if val and val != self_id:
            prev[m] = val
    except Exception:
        pass
with open(out_file, "w", encoding="utf-8") as f:
    json.dump(prev, f, indent=2)
PY
    fi

    # Write NoDisplay=true .desktop so it never duplicates Gallery in app launchers,
    # while still working as default photo viewer and in file-manager "Open with..."
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Gallery
GenericName=Photo Viewer
Comment=View photos and videos in ii Gallery
Exec=$OPEN_SCRIPT %f
Icon=image-x-generic
Terminal=false
NoDisplay=true
StartupNotify=false
Categories=Graphics;Viewer;
MimeType=$(IFS=';'; echo "${IMAGE_MIMES[*]}");
EOF
    chmod 644 "$DESKTOP_FILE"

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi

    xdg-mime default "$DESKTOP_ID" "${IMAGE_MIMES[@]}"
    printf '{"ok":true,"isDefault":true}\n'
}

cmd_disable() {
    # Restore previous defaults if we saved them, and strip ii-gallery.desktop from mimeapps.list
    python3 - "$BACKUP_FILE" "$DESKTOP_ID" "${IMAGE_MIMES[@]}" <<'PY'
import json, os, subprocess, sys
backup_file, self_id = sys.argv[1], sys.argv[2]
mimes = sys.argv[3:]

prev = {}
if os.path.isfile(backup_file):
    try:
        with open(backup_file, "r", encoding="utf-8") as f:
            prev = json.load(f)
    except Exception:
        prev = {}

for m, handler in prev.items():
    if handler and handler != self_id:
        try:
            subprocess.run(["xdg-mime", "default", handler, m], capture_output=True, timeout=3)
        except Exception:
            pass

# Clean any leftover references to ii-gallery.desktop in ~/.config/mimeapps.list
mimeapps = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "mimeapps.list")
if os.path.isfile(mimeapps):
    try:
        lines = open(mimeapps, "r", encoding="utf-8", errors="ignore").splitlines()
        out = []
        for line in lines:
            if "=" in line and self_id in line:
                k, v = line.split("=", 1)
                parts = [p for p in v.split(";") if p and p != self_id]
                if parts:
                    out.append(f"{k}={';'.join(parts)};")
                # if empty, drop the line so system defaults apply
            else:
                out.append(line)
        with open(mimeapps, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    except Exception:
        pass
PY

    rm -f "$DESKTOP_FILE" "$BACKUP_FILE"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
    fi

    printf '{"ok":true,"isDefault":false}\n'
}

ACTION="${1:-status}"
case "$ACTION" in
    status)  cmd_status ;;
    enable)  cmd_enable ;;
    disable) cmd_disable ;;
    toggle)
        if is_default; then
            cmd_disable
        else
            cmd_enable
        fi
        ;;
    *)
        echo "Usage: $0 {status|enable|disable|toggle}" >&2
        exit 1
        ;;
esac
