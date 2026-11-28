#!/usr/bin/env bash
# Open a local image/video in the standalone ii Gallery app.
# Used by ~/.local/share/applications/ii-gallery.desktop when Gallery is set as
# the default photo viewer (or invoked via "Open with..." in any file manager).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_QML="$(realpath "$SCRIPT_DIR/../../apps/gallery.qml")"

RAW_TARGET="${1:-}"
if [ -z "$RAW_TARGET" ]; then
    exec qs -p "$APP_QML"
fi

# Strip file:// URI prefix and decode percent-encoding if passed by a file manager
TARGET="$(python3 -c '
import sys, urllib.parse, os
u = sys.argv[1]
if u.startswith("file://"):
    u = urllib.parse.unquote(urllib.parse.urlparse(u).path)
print(os.path.abspath(os.path.expanduser(u)))
' "$RAW_TARGET")"

# If a Gallery instance is already running, hand the path over via IPC
if qs -p "$APP_QML" ipc call gallery openPath "$TARGET" >/dev/null 2>&1; then
    exit 0
fi

# Otherwise launch a fresh Gallery window directly on the target image
exec env II_GALLERY_INITIAL_PATH="$TARGET" qs -p "$APP_QML"
