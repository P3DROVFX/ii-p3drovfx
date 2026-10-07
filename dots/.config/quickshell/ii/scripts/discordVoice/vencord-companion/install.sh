#!/usr/bin/env bash
# Install the end4-pC Discord Voice companion plugin for Vesktop / Equibop /
# official Discord with Vencord injected via the standalone Vencord Installer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_NAME="iiDiscordVoice"

notify() {
    local title="$1"
    local msg="$2"
    local urgency="${3:-normal}"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" "$title" "$msg"
    fi
}

info() {
    printf '\033[1;34m:: %s\033[0m\n' "$*"
}

error() {
    local msg="$*"
    printf '\033[1;31m:: %s\033[0m\n' "$msg" >&2
    notify "Discord Voice Companion Error" "$msg" "critical"
    exit 1
}

# Environment setup: load NVM / Node / pnpm / Bun paths
if [ -d "$HOME/.nvm" ]; then
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh" || true
    fi
    latest_node="$(ls "$NVM_DIR/versions/node" 2>/dev/null | tail -1 || true)"
    if [ -n "$latest_node" ]; then
        export PATH="$NVM_DIR/versions/node/$latest_node/bin:$PATH"
    fi
fi

export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.local/share/pnpm:$PATH"

# Validate required tools
missing_tools=()
for cmd in git node pnpm; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_tools+=("$cmd")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    error "Missing required dependencies: ${missing_tools[*]}. Please install them to proceed."
fi

# A client's config directory can be left behind by theme installers or a
# previous uninstall without the client itself being present, so directory
# existence alone is not a reliable signal. Require either the binary or
# evidence of an actual Electron profile (created only once the app has run).
has_electron_profile() {
    local dir="$1"
    [ -d "$dir/Local Storage" ] || [ -d "$dir/Session Storage" ] || [ -d "$dir/Cache" ]
}

is_vesktop_installed() {
    command -v vesktop >/dev/null 2>&1 && return 0
    [ -x "/opt/Vesktop/vesktop" ] && return 0
    [ -d "$HOME/.config/vesktop" ] && has_electron_profile "$HOME/.config/vesktop"
}

is_equibop_installed() {
    command -v equibop >/dev/null 2>&1 && return 0
    [ -d "$HOME/.config/equibop" ] && has_electron_profile "$HOME/.config/equibop"
}

is_standalone_vencord_installed() {
    # Only the official Vencord Installer writes a patcher here; Vesktop and
    # Equibop bundle their own fork and never touch this path.
    [ -f "$HOME/.config/Vencord/dist/patcher.js" ] || return 1
    command -v discord >/dev/null 2>&1 && return 0
    [ -d "$HOME/.config/discord" ] && has_electron_profile "$HOME/.config/discord"
}

STANDALONE_VENCORD=0

# Detect client. Standalone Vencord-on-Discord is checked first: its marker
# (a patcher.js dropped by the official installer) is unambiguous, whereas
# leftover vesktop/equibop config dirs are not.
# Override with QS_DISCORD_CLIENT=vesktop|equibop|vencord if detection guesses wrong.
case "${QS_DISCORD_CLIENT:-}" in
    vesktop) DETECTED="vesktop" ;;
    equibop) DETECTED="equibop" ;;
    vencord) DETECTED="vencord" ;;
    "")
        if is_standalone_vencord_installed; then DETECTED="vencord"
        elif is_vesktop_installed; then DETECTED="vesktop"
        elif is_equibop_installed; then DETECTED="equibop"
        else DETECTED=""
        fi
        ;;
    *) error "Unknown QS_DISCORD_CLIENT '${QS_DISCORD_CLIENT}'. Use vesktop, equibop, or vencord." ;;
esac

case "$DETECTED" in
    vencord)
        CLIENT_NAME="Discord (Vencord)"
        REPO_URL="https://github.com/Vendicated/Vencord.git"
        BUILD_DIR="${HOME}/.local/share/quickshell-ii/Vencord"
        VENCORD_SETTINGS="${HOME}/.config/Vencord/settings/settings.json"
        STANDALONE_VENCORD=1
        ;;
    vesktop)
        CLIENT_NAME="Vesktop"
        REPO_URL="https://github.com/Vendicated/Vencord.git"
        BUILD_DIR="${HOME}/.local/share/quickshell-ii/Vencord"
        # Vesktop reads a custom Vencord build from state.json's vencordDir
        # (State.store.vencordDir); settings.json has no such key.
        STATE_FILE="${HOME}/.config/vesktop/state.json"
        VENCORD_SETTINGS="${HOME}/.config/vesktop/settings/settings.json"
        CONFIG_KEY="vencordDir"
        ;;
    equibop)
        CLIENT_NAME="Equibop"
        REPO_URL="https://github.com/Equicord/Equicord.git"
        BUILD_DIR="${HOME}/.local/share/quickshell-ii/Equicord"
        STATE_FILE="${HOME}/.config/equibop/state.json"
        VENCORD_SETTINGS="${HOME}/.config/equibop/settings/settings.json"
        CONFIG_KEY="equicordDir"
        ;;
    *)
        error "Could not detect Vesktop, Equibop, or a standalone Vencord-patched Discord install. Set QS_DISCORD_CLIENT=vesktop|equibop|vencord and re-run."
        ;;
esac

notify "Discord Voice Overlay" "Installing $CLIENT_NAME Companion plugin..." "normal"
info "Installing companion for $CLIENT_NAME in $BUILD_DIR"

if [ -d "$BUILD_DIR" ]; then
    info "Updating existing checkout at $BUILD_DIR"
    git -C "$BUILD_DIR" pull --ff-only || true
else
    info "Cloning $CLIENT_NAME source to $BUILD_DIR"
    git clone "$REPO_URL" "$BUILD_DIR"
fi

PLUGIN_DIR="$BUILD_DIR/src/userplugins/$PLUGIN_NAME"
info "Installing plugin source files to $PLUGIN_DIR"
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
cp "$SCRIPT_DIR/index.ts" "$SCRIPT_DIR/native.ts" "$PLUGIN_DIR/"

info "Building companion plugin (this may take a few moments)..."
cd "$BUILD_DIR"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install
pnpm build

DIST_DIR="$BUILD_DIR/dist"

if [ -f "$DIST_DIR/package.json" ]; then
    info "Build succeeded at $DIST_DIR"
else
    cp "$BUILD_DIR/package.json" "$DIST_DIR/" 2>/dev/null || true
fi

# Process name to watch/relaunch, per client. Matched with -x (exact comm
# name) rather than -f (full command line): this script's own path contains
# "discord" (scripts/discordVoice/...), so a substring/full-cmdline match
# would find and kill install.sh's own process before it finishes.
case "$DETECTED" in
    vencord) PROC_PATTERN="Discord" ;;
    equibop) PROC_PATTERN="equibop" ;;
    *) PROC_PATTERN="vesktop" ;;
esac

WAS_RUNNING=0
if pgrep -ix "$PROC_PATTERN" >/dev/null 2>&1; then
    WAS_RUNNING=1
    info "Closing $CLIENT_NAME to update settings cleanly..."
    pkill -ix "$PROC_PATTERN" 2>/dev/null || true
    # The client saves its state file on the way out; writing ours before it is
    # gone would be overwritten by that save.
    for _ in $(seq 50); do
        pgrep -ix "$PROC_PATTERN" >/dev/null 2>&1 || break
        sleep 0.2
    done
    if pgrep -ix "$PROC_PATTERN" >/dev/null 2>&1; then
        error "$CLIENT_NAME did not close; close it and run the install again."
    fi
fi

if [ "$STANDALONE_VENCORD" -eq 1 ]; then
    # There is no user-configurable "Vencord location" setting for a standalone
    # install: the injected patcher.js hardcodes ~/.config/Vencord/dist, so the
    # only way to get a custom userplugin loaded is to replace that directory
    # outright. Back up the existing build first since this overwrites the
    # user's live, daily-driver Vencord build.
    LIVE_DIST="${HOME}/.config/Vencord/dist"
    BACKUP_DIR="${HOME}/.config/Vencord/dist.bak-$(date +%Y%m%d%H%M%S)"
    if [ -d "$LIVE_DIST" ]; then
        info "Backing up existing Vencord build to $BACKUP_DIR"
        cp -a "$LIVE_DIST" "$BACKUP_DIR"
    fi
    info "Installing custom build into $LIVE_DIST"
    rm -rf "$LIVE_DIST"
    cp -a "$DIST_DIR" "$LIVE_DIST"
else
    # Update settings file
    if [ -f "$STATE_FILE" ]; then
        if command -v python3 &>/dev/null; then
            python3 -c "
import json
try:
    with open('$STATE_FILE') as f: data = json.load(f)
except Exception:
    data = {}
data['$CONFIG_KEY'] = '$DIST_DIR'
with open('$STATE_FILE', 'w') as f: json.dump(data, f, indent=4)
"
            if [ "$DETECTED" = vesktop ]; then
                # Earlier versions of this script wrote the build path under a key
                # Vesktop never reads; drop it so it cannot be mistaken for the real one.
                python3 -c "
import json
path = '${HOME}/.config/vesktop/settings.json'
try:
    with open(path) as f: data = json.load(f)
except Exception:
    data = None
if isinstance(data, dict) and data.pop('vencordLocation', None) is not None:
    with open(path, 'w') as f: json.dump(data, f, indent=4)
"
            fi
            info "Updated $CONFIG_KEY in $STATE_FILE"
        fi
    else
        mkdir -p "$(dirname "$STATE_FILE")"
        echo "{\"$CONFIG_KEY\": \"$DIST_DIR\"}" > "$STATE_FILE"
    fi
fi

# Enable plugin in Vencord settings
if [ -f "$VENCORD_SETTINGS" ]; then
    if command -v python3 &>/dev/null; then
        python3 -c "
import json
try:
    with open('$VENCORD_SETTINGS') as f: data = json.load(f)
except Exception:
    data = {}
if 'plugins' not in data: data['plugins'] = {}
data['plugins']['$PLUGIN_NAME'] = {'enabled': True}
if $STANDALONE_VENCORD:
    # Vencord's built-in updater re-downloads the official prebuilt dist and
    # would silently wipe out this custom build (and the plugin with it).
    data['autoUpdate'] = False
    data['autoUpdateNotification'] = False
with open('$VENCORD_SETTINGS', 'w') as f: json.dump(data, f, indent=4)
"
        info "Enabled $PLUGIN_NAME in Vencord settings"
        if [ "$STANDALONE_VENCORD" -eq 1 ]; then
            info "Disabled Vencord's auto-updater so it won't overwrite the custom build. Restore from $BACKUP_DIR and re-enable auto-update in Vencord settings to go back to official builds."
        fi
    fi
fi

if [ $WAS_RUNNING -eq 1 ]; then
    info "Relaunching $CLIENT_NAME..."
    if [ "$STANDALONE_VENCORD" -eq 1 ]; then
        if command -v discord >/dev/null 2>&1; then
            nohup discord >/dev/null 2>&1 &
        elif [ -x "/opt/discord/Discord" ]; then
            nohup /opt/discord/Discord >/dev/null 2>&1 &
        fi
    elif [ "$DETECTED" = equibop ]; then
        command -v equibop >/dev/null 2>&1 && nohup equibop >/dev/null 2>&1 &
    else
        if command -v vesktop >/dev/null 2>&1; then
            nohup vesktop >/dev/null 2>&1 &
        elif [ -x "/opt/Vesktop/vesktop" ]; then
            nohup /opt/Vesktop/vesktop >/dev/null 2>&1 &
        fi
    fi
fi

notify "Discord Voice Overlay" "Companion plugin installed and $CLIENT_NAME restarted!" "normal"
info "Done! $CLIENT_NAME restarted with companion plugin."
