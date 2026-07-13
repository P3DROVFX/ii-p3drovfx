#!/usr/bin/env bash
# update-fork.sh — thin wrapper around setup-ii-vynx.sh --update.
#
# Kept for backwards compatibility. Use `vynx update` or
# `setup-ii-vynx.sh --update` directly for new code.
set -euo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

# Resolve the canonical script: prefer ~/Downloads/ii-vynx (dev clone),
# then ~/.local/share/ii-vynx (installed copy used by UI buttons),
# then this dir.
SETUP=""
for candidate in \
    "$HOME/Downloads/ii-vynx/setup-ii-vynx.sh" \
    "$HOME/.local/share/ii-vynx/setup-ii-vynx.sh" \
    "$SCRIPT_DIR/setup-ii-vynx.sh"; do
    if [ -f "$candidate" ]; then
        SETUP="$candidate"
        break
    fi
done

if [ -z "$SETUP" ]; then
    echo "✗ Could not locate setup-ii-vynx.sh" >&2
    exit 1
fi

exec bash "$SETUP" --update --no-confirm --preserve-config "$@"