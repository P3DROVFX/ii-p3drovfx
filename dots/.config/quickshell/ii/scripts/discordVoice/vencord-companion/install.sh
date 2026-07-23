#!/usr/bin/env bash
# Install the end4-pC Discord Voice companion plugin for Equibop.
# This clones Equicord, adds the companion plugin, and builds it.
# The equicordDir in ~/.config/equibop/state.json is updated automatically.
set -euo pipefail

EQUICORD_DIR="${HOME}/.local/share/end4-pC/Equicord"
PLUGIN_NAME="end4DiscordVoice"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="${HOME}/.config/equibop/state.json"

info()  { printf '\033[1;34m:: %s\033[0m\n' "$*"; }
error() { printf '\033[1;31m:: %s\033[0m\n' "$*" >&2; exit 1; }

# Source nvm if available (common for user-space node installs)
if [ -z "$(command -v node 2>/dev/null)" ] && [ -s "$HOME/.nvm/nvm.sh" ]; then
    info "Loading nvm..."
    export NVM_DIR="$HOME/.nvm"
    . "$HOME/.nvm/nvm.sh"
fi

for cmd in git node pnpm; do
    command -v "$cmd" >/dev/null 2>&1 || error "'$cmd' is not installed. Please install it first."
done

if [ -d "$EQUICORD_DIR" ]; then
    info "Updating existing Equicord checkout at $EQUICORD_DIR"
    git -C "$EQUICORD_DIR" pull --ff-only || true
else
    info "Cloning Equicord source to $EQUICORD_DIR"
    git clone https://github.com/Equicord/Equicord.git "$EQUICORD_DIR"
fi

PLUGIN_DIR="$EQUICORD_DIR/src/userplugins/$PLUGIN_NAME"
info "Installing companion plugin to $PLUGIN_DIR"
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp "$SCRIPT_DIR/index.ts" "$SCRIPT_DIR/native.ts" "$PLUGIN_DIR/"

info "Building Equicord (this may take a few minutes)"
cd "$EQUICORD_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build

DIST_DIR="$EQUICORD_DIR/dist"

# Update equicordDir in Equibop's state.json
if [ -f "$STATE_FILE" ]; then
    if command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$STATE_FILE') as f: data = json.load(f)
data['equicordDir'] = '$DIST_DIR'
with open('$STATE_FILE', 'w') as f: json.dump(data, f, indent=4)
"
        info "Updated equicordDir in $STATE_FILE"
    else
        info "Manually set equicordDir in $STATE_FILE to: $DIST_DIR"
    fi
fi

info "Done! Fully restart Equibop to load the companion plugin."
