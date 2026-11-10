#!/usr/bin/env bash
# Bridge between Settings -> Themed icons and the ii-icon-pack repository.
#
#   ii_icon_pack.sh <source-dir|""> <status|install|update|apply|shapes|preview> [iipack args...]
#
# Everything about the pack (shapes, rendering, updates) lives in the pack's own
# scripts/iipack.py, so the shell and the pack's install.sh run the same code. This script
# only makes sure a checkout exists - cloned on the first install - and forwards to it with
# --json: `@progress <0..1> <message>` lines while working, then one JSON object.
set -uo pipefail

REPO_URL="https://github.com/P3DROVFX/ii-icon-pack.git"
TARBALL="https://codeload.github.com/P3DROVFX/ii-icon-pack/tar.gz/refs/heads/main"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SRC="${1:-}"
[ -n "$SRC" ] || SRC="$DATA_HOME/ii-icon-pack"
SRC="${SRC/#\~/$HOME}"
shift || true
CMD="${1:-status}"
shift || true

json_error() {
    python3 -c 'import json,sys; print(json.dumps({"ok": False, "error": sys.argv[1]}))' "$1"
    exit 1
}

fetch_source() {
    echo "@progress 0.01 Downloading ii-icon-pack from GitHub"
    mkdir -p "$(dirname "$SRC")"
    if command -v git >/dev/null; then
        git clone --quiet --depth 1 --branch main "$REPO_URL" "$SRC" 2>/dev/null \
            || json_error "Could not download the pack from GitHub."
    else
        tmp="$(mktemp -d)"
        if ! curl -fsSL "$TARBALL" | tar -xz -C "$tmp"; then
            rm -rf "$tmp"
            json_error "Could not download the pack from GitHub."
        fi
        rm -rf "$SRC"
        mv "$tmp"/ii-icon-pack-* "$SRC"
        rm -rf "$tmp"
    fi
}

if [ ! -f "$SRC/scripts/iipack.py" ]; then
    case "$CMD" in
        install|update|apply)
            fetch_source
            CMD="install"
            ;;
        status)
            # No checkout yet: still say whether some ii-icon-pack theme is on disk.
            theme="$DATA_HOME/icons/ii-icon-pack"
            installed=false
            [ -f "$theme/index.theme" ] && installed=true
            printf '{"ok": true, "sourcePresent": false, "installed": %s, "managed": false, "source": "%s"}\n' "$installed" "$SRC"
            exit 0
            ;;
        *)
            json_error "The pack is not downloaded yet."
            ;;
    esac
fi

exec python3 "$SRC/scripts/iipack.py" "$CMD" --json "$@"
