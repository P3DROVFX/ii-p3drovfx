#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# ── Resolve absolute path of this script (handles symlinks) ──────────────────
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"

# ── Log to file for debugging (called from QML Process) ─────────────────────
exec > >(tee -a /tmp/ii-vynx-install.log) 2>&1
echo "--- Starting setup at $(date) | args: $* ---"
echo "SCRIPT_DIR: $SCRIPT_DIR"

# ── CLI sub-command dispatcher (when invoked as "vynx") ─────────────────────
INVOKED_AS="$(basename "$SOURCE")"
if [[ "$INVOKED_AS" == "vynx" ]]; then
    LIB_DIR="$SCRIPT_DIR/sdata/cli/lib"
    VERBOSE=false
    TEMP_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) VERBOSE=true; shift ;;
            *) TEMP_ARGS+=("$1"); shift ;;
        esac
    done
    set -- "${TEMP_ARGS[@]}"

    COMMAND="$1"; shift
    case "$COMMAND" in
        run|restart|update|remove-cli|hyprset)
            if [ -f "$LIB_DIR/${COMMAND}.sh" ]; then
                source "$LIB_DIR/${COMMAND}.sh" "$@"
                exit $?
            else
                echo -e "${RED}Error: $COMMAND not found${NC}"; exit 1
            fi
            ;;
        "")
            echo "Usage: vynx [-v] {run|restart|update|remove-cli|hyprset}"; exit 1 ;;
        *)
            echo -e "${RED}Invalid command: $COMMAND${NC}"; exit 1 ;;
    esac
fi

# ── Default flags ────────────────────────────────────────────────────────────
DO_PULL=true
VERBOSE=false
FORCE_INSTALL=false
BACKUP=true
FULL_INSTALL=false
NO_CONFIRM=false
USE_II_VYNX=false
UPDATE_ONLY=false
SKIP_HYPRLAND=true
PRESERVE_CONFIG=false

UPSTREAM_REPO="https://github.com/vaguesyntax/ii-vynx"
UPSTREAM_DIR="$HOME/.local/share/ii-vynx-upstream"
STANDARD_SCRIPT_DIR="$HOME/.local/share/ii-vynx"

# Auto-detect fork directory:
# 1. If ~/.local/share/ii-vynx-fork exists (dedicated install), use it
# 2. Otherwise use SCRIPT_DIR itself (user running from their clone directly)
if [ -d "$HOME/.local/share/ii-vynx-fork/.git" ]; then
    FORK_DIR="$HOME/.local/share/ii-vynx-fork"
else
    FORK_DIR="$SCRIPT_DIR"
fi

# ── Parse arguments ──────────────────────────────────────────────────────────
for arg in "$@"; do
    case $arg in
        --no-pull)        DO_PULL=false ;;
        --no-backup)      BACKUP=false ;;
        -v|--verbose)     VERBOSE=true ;;
        --force-install)  FORCE_INSTALL=true ;;
        --full-install)   FULL_INSTALL=true ;;
        --no-confirm)     NO_CONFIRM=true; FORCE_INSTALL=true ;;
        --ii-vynx)        USE_II_VYNX=true ;;
        --update-only)    UPDATE_ONLY=true; DO_PULL=true ;;
        --include-hyprland) SKIP_HYPRLAND=false ;;
        --preserve-config)  PRESERVE_CONFIG=true ;;
        *)
            echo -e "${RED}Unknown flag: $arg${NC}"
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-pull          Skip git pull (use local repos as-is)"
            echo "  --no-backup        Skip backup of existing config"
            echo "  --force-install    Skip illogical-impulse check"
            echo "  --full-install     Install original dots first, then ii-vynx"
            echo "  --no-confirm       Skip all confirmations"
            echo "  --ii-vynx          Switch to official vaguesyntax/ii-vynx quickshell"
             echo "  --update-only      Pull latest changes for current source, no switch"
             echo "  --include-hyprland  Include hyprland config setup (default: skip)"
             echo "  --preserve-config   Keep existing config.json (use with --no-confirm for update buttons)"
             echo "  -v, --verbose      Enable verbose output"
            exit 1
            ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE] $1${NC}"
    fi
}

# Files that must NEVER be overwritten during any install or switch
PROTECTED_FILES=(
    "modules/settings/About.qml"
)

# Patterns for files that must NEVER be overwritten (glob-style, relative to TARGET_DIR)
PROTECTED_PATTERNS=(
    "*.env"
    ".env"
    "user/generated/*.json"
)

backup_protected_files() {
    local target="$1"
    local tmpdir="/tmp/ii-vynx-protected"
    rm -rf "$tmpdir"
    mkdir -p "$tmpdir"

    for rel in "${PROTECTED_FILES[@]}"; do
        local src="$target/$rel"
        if [ -f "$src" ]; then
            local dest_dir="$tmpdir/$(dirname "$rel")"
            mkdir -p "$dest_dir"
            cp "$src" "$tmpdir/$rel"
            log_verbose "Protected (backed up): $rel"
        fi
    done

    # Glob patterns
    for pattern in "${PROTECTED_PATTERNS[@]}"; do
        while IFS= read -r -d '' f; do
            local rel="${f#$target/}"
            local dest_dir="$tmpdir/$(dirname "$rel")"
            mkdir -p "$dest_dir"
            cp "$f" "$tmpdir/$rel"
            log_verbose "Protected (backed up pattern): $rel"
        done < <(find "$target" -path "$target/$pattern" -print0 2>/dev/null)
    done
}

restore_protected_files() {
    local target="$1"
    local tmpdir="/tmp/ii-vynx-protected"

    for rel in "${PROTECTED_FILES[@]}"; do
        local src="$tmpdir/$rel"
        if [ -f "$src" ]; then
            local dest_dir="$target/$(dirname "$rel")"
            mkdir -p "$dest_dir"
            cp "$src" "$target/$rel"
            log_verbose "Restored protected: $rel"
        fi
    done

    # Glob patterns
    find "$tmpdir" -type f 2>/dev/null | while read -r f; do
        local rel="${f#$tmpdir/}"
        local dest_dir="$target/$(dirname "$rel")"
        mkdir -p "$dest_dir"
        cp "$f" "$target/$rel"
        log_verbose "Restored protected pattern: $rel"
    done

    rm -rf "$tmpdir"
}

fetch_upstream() {
    if [ -d "$UPSTREAM_DIR/.git" ]; then
        echo -e "${NC}• Updating official ii-vynx repo...${NC}"
        git -C "$UPSTREAM_DIR" pull --ff-only
        git -C "$UPSTREAM_DIR" submodule update --init --recursive
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠ git update failed for upstream, using cached version.${NC}"
        else
            echo -e "${GREEN}✓ Official ii-vynx repo updated${NC}"
        fi
    else
        echo -e "${NC}• Cloning official ii-vynx repo (first time)...${NC}"
        git clone --depth=1 --recurse-submodules "$UPSTREAM_REPO" "$UPSTREAM_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}✗ Failed to clone: $UPSTREAM_REPO${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Official ii-vynx repo cloned${NC}"
    fi
}

setup_hyprland_rules() {
    local REPO_HYPR_DIR="$SCRIPT_DIR/dots/.config/hypr"
    local DEST_HYPR_DIR="$HOME/.config/hypr"
    local SKIP_FILES=("colors.conf" "general.conf")

    echo -e "${NC}• Copying Hyprland config files...${NC}"

    if [ ! -d "$REPO_HYPR_DIR" ]; then
        echo -e "${YELLOW}⚠ Hyprland config directory not found in repo, skipping.${NC}"
        return 0
    fi

    local REPO_CONF_DIR="$REPO_HYPR_DIR/hyprland"
    local DEST_CONF_DIR="$DEST_HYPR_DIR/hyprland"

    if [ -d "$REPO_CONF_DIR" ]; then
        mkdir -p "$DEST_CONF_DIR"
        for f in "$REPO_CONF_DIR"/*.conf; do
            [ -f "$f" ] || continue
            local fname; fname="$(basename "$f")"
            local skip=false
            for skip_file in "${SKIP_FILES[@]}"; do
                [ "$fname" = "$skip_file" ] && skip=true && break
            done
            $skip && continue
            [ -f "$DEST_CONF_DIR/$fname" ] && cp "$DEST_CONF_DIR/$fname" "$DEST_CONF_DIR/${fname}.bak"
            cp "$f" "$DEST_CONF_DIR/$fname"
            log_verbose "Copied $fname → $DEST_CONF_DIR/$fname"
        done
        echo -e "${GREEN}✓ Hyprland configs updated${NC}"
    fi
}

setup_hyprland_source() {
    local II_VYNX_DIR="$HOME/.local/share/ii-vynx"
    local II_VYNX_CONF="$II_VYNX_DIR/hyprland.conf"
    local MAIN_HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
    local REPO_HYPR_CONF="$SCRIPT_DIR/dots/.local/share/ii-vynx/hyprland.conf"
    local HYPRMERGE="$SCRIPT_DIR/sdata/cli/lib/hyprmerge.sh"

    echo -e "${NC}• Checking Hyprland source config...${NC}"
    mkdir -p "$II_VYNX_DIR"

    if [ ! -f "$REPO_HYPR_CONF" ]; then
        echo -e "${RED}⚠ Error: Hyprland config not found: $REPO_HYPR_CONF${NC}"
        return 1
    fi

    if [ ! -f "$II_VYNX_CONF" ]; then
        cp "$REPO_HYPR_CONF" "$II_VYNX_CONF"
        echo -e "${GREEN}✓ Fresh install: copied hyprland.conf${NC}"
    else
        echo -e "${BLUE}• Merging hyprland.conf...${NC}"
        if [ -f "$HYPRMERGE" ]; then
            bash "$HYPRMERGE" "$REPO_HYPR_CONF" "$II_VYNX_CONF"
        else
            cp "$REPO_HYPR_CONF" "$II_VYNX_CONF"
            echo -e "${GREEN}✓ Copied hyprland.conf (fallback)${NC}"
        fi
    fi

    if [ -f "$MAIN_HYPR_CONF" ]; then
        if ! grep -q "$II_VYNX_CONF" "$MAIN_HYPR_CONF"; then
            cp "$MAIN_HYPR_CONF" "${MAIN_HYPR_CONF}.bak"
            echo -e "\n# ii-vynx\nsource = $II_VYNX_CONF" >> "$MAIN_HYPR_CONF"
            echo -e "${GREEN}✓ Appended source to hyprland.conf${NC}"
        fi
    fi
}

run_bundled_setup() {
    echo -e "${RED}This fork's base dotfiles are not installed yet. Install them now? (y/n): ${NC}"
    read -r setup_response
    [[ ! "$setup_response" =~ ^[Yy]$ ]] && echo -e "${RED}✗ Setup cancelled.${NC}" && exit 1

    bash "$SCRIPT_DIR/setup" "install"
    [ $? -eq 0 ] || { echo -e "${RED}✗ Setup failed!${NC}"; exit 1; }
}

install_cli() {
    local BIN_PATH="$HOME/.local/bin"
    local TARGET="$BIN_PATH/vynx"

    echo -e "${BLUE}• Installing Vynx CLI...${NC}"
    mkdir -p "$BIN_PATH"

    if [[ ":$PATH:" != *":$BIN_PATH:"* ]]; then
        echo -e "${YELLOW}⚠ $BIN_PATH is not in PATH. Add to ~/.bashrc or ~/.zshrc:${NC}"
        echo -e "${GREEN}   export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    fi

    chmod +x "$SCRIPT_DIR/setup-ii-vynx.sh"
    [ -d "$SCRIPT_DIR/sdata/cli/lib" ] && chmod +x "$SCRIPT_DIR/sdata/cli/lib/"*.sh
    ln -sf "$SCRIPT_DIR/setup-ii-vynx.sh" "$TARGET"
    echo -e "${GREEN}✓ Symlinked vynx → $TARGET${NC}"
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}          ii-vynx setup     ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Bootstrap: ensure standard locations exist for new users ─────────────────
# About.qml calls the script from ~/.local/share/ii-vynx/setup-ii-vynx.sh
# If the script is being run from a different location (e.g. ~/Downloads/my-fork),
# copy it to the standard location so the UI buttons keep working after install.
if [ "$SCRIPT_DIR" != "$STANDARD_SCRIPT_DIR" ]; then
    if [ ! -f "$STANDARD_SCRIPT_DIR/setup-ii-vynx.sh" ]; then
        echo -e "${BLUE}• Installing setup script to standard location...${NC}"
        mkdir -p "$STANDARD_SCRIPT_DIR"
        cp "$SOURCE" "$STANDARD_SCRIPT_DIR/setup-ii-vynx.sh"
        chmod +x "$STANDARD_SCRIPT_DIR/setup-ii-vynx.sh"
        echo -e "${GREEN}✓ Script installed to $STANDARD_SCRIPT_DIR${NC}"
    fi
fi

UPDATE_SCRIPT_SRC="$SCRIPT_DIR/update-with-customs.sh"
UPDATE_SCRIPT_DST="$STANDARD_SCRIPT_DIR/update-with-customs.sh"
if [ -f "$UPDATE_SCRIPT_SRC" ]; then
    cp "$UPDATE_SCRIPT_SRC" "$UPDATE_SCRIPT_DST"
    chmod +x "$UPDATE_SCRIPT_DST"
    log_verbose "Update script installed to $UPDATE_SCRIPT_DST"
fi

UPDATE_FORK_SRC="$SCRIPT_DIR/update-fork.sh"
UPDATE_FORK_DST="$STANDARD_SCRIPT_DIR/update-fork.sh"
if [ -f "$UPDATE_FORK_SRC" ]; then
    cp "$UPDATE_FORK_SRC" "$UPDATE_FORK_DST"
    chmod +x "$UPDATE_FORK_DST"
    log_verbose "Fork update wrapper installed to $UPDATE_FORK_DST"
fi

# If ii-vynx-fork doesn't exist yet, bootstrap it from SCRIPT_DIR
if [ ! -d "$HOME/.local/share/ii-vynx-fork/.git" ] && [ "$SCRIPT_DIR" != "$HOME/.local/share/ii-vynx-upstream" ]; then
    echo -e "${BLUE}• Setting up local fork at ~/.local/share/ii-vynx-fork...${NC}"
    cp -r "$SCRIPT_DIR" "$HOME/.local/share/ii-vynx-fork"
    FORK_DIR="$HOME/.local/share/ii-vynx-fork"
    echo -e "${GREEN}✓ Fork bootstrapped at $FORK_DIR${NC}"
fi

# ── Handle --update-only: just pull, no switch ───────────────────────────────
if [ "$UPDATE_ONLY" = true ]; then
    echo -e "${BLUE}• Update-only mode: pulling latest changes...${NC}"
    if [ "$USE_II_VYNX" = true ]; then
        fetch_upstream
    else
        if [ -d "$FORK_DIR/.git" ]; then
            cd "$FORK_DIR" && git pull
        else
            echo -e "${RED}✗ Fork not found at $FORK_DIR${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ Update complete. Run without --update-only to apply.${NC}"
    exit 0
fi

# ── Resolve source directory ─────────────────────────────────────────────────
CONFIG_DIR="$HOME/.config"
CHECK_DIR="$CONFIG_DIR/illogical-impulse"
TARGET_DIR="$CONFIG_DIR/quickshell/ii"

if [ "$USE_II_VYNX" = true ]; then
    # Official upstream source (local cache only when --no-pull)
    if [ "$DO_PULL" = false ]; then
        if [ -d "$UPSTREAM_DIR/dots/.config/quickshell/ii" ]; then
            SOURCE_DIR="$UPSTREAM_DIR/dots/.config/quickshell/ii"
            echo -e "${YELLOW}Using cached official ii-vynx quickshell at $SOURCE_DIR${NC}"
        else
            echo -e "${RED}✗ Official ii-vynx not cached locally yet.${NC}"
            echo -e "${RED}  Click 'Update ii-vynx' first to download it.${NC}"
            exit 1
        fi
    else
        fetch_upstream
        SOURCE_DIR="$UPSTREAM_DIR/dots/.config/quickshell/ii"
    fi
else
    # Fork source: ~/Downloads/ii-vynx (P3DROVFX/ii-vynx)
    if [ ! -d "$FORK_DIR/dots/.config/quickshell/ii" ]; then
        echo -e "${RED}✗ Fork not found at $FORK_DIR${NC}"
        echo -e "${RED}  Expected your fork at ~/Downloads/ii-vynx${NC}"
        exit 1
    fi
    SOURCE_DIR="$FORK_DIR/dots/.config/quickshell/ii"
    if [ "$DO_PULL" = true ]; then
        echo -e "${NC}• Updating your fork...${NC}"
        git -C "$FORK_DIR" pull --ff-only
        git -C "$FORK_DIR" submodule update --init --recursive
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠ git update failed for fork, using local version.${NC}"
        else
            echo -e "${GREEN}✓ Fork updated and submodules synced${NC}"
        fi
    else
        # Even if not pulling, ensure submodules are initialized if they exist in the repo
        if [ -d "$FORK_DIR/.git" ]; then
            echo -e "${NC}• Ensuring fork submodules are initialized...${NC}"
            git -C "$FORK_DIR" submodule update --init --recursive >/dev/null 2>&1
        fi
    fi
fi

echo ""
log_verbose "TARGET_DIR=$TARGET_DIR"
log_verbose "SOURCE_DIR=$SOURCE_DIR"
log_verbose "USE_II_VYNX=$USE_II_VYNX"
log_verbose "DO_PULL=$DO_PULL"

# ── Confirm (interactive mode only) ─────────────────────────────────────────
if [ "$NO_CONFIRM" = false ]; then
    echo -e "${BLUE}This will switch your Quickshell config to:${NC}"
    [ "$USE_II_VYNX" = true ] && \
        echo -e "${CYAN}  Official ii-vynx${NC}" || \
        echo -e "${CYAN}  Your fork${NC}"
    echo -e "${BLUE}Protected files (About.qml, .env) will NOT be overwritten.${NC}"
    echo -e "${RED}Continue? (y/n): ${NC}"
    read -r response
    [[ ! "$response" =~ ^[Yy]$ ]] && echo -e "${RED}Cancelled.${NC}" && exit 0
    echo ""
fi

# ── Check source exists ──────────────────────────────────────────────────────
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${RED}✗ Source directory not found: $SOURCE_DIR${NC}"
    exit 1
fi

# ── Check illogical-impulse ──────────────────────────────────────────────────
if [ "$FORCE_INSTALL" = false ] && [ "$FULL_INSTALL" = false ]; then
    if [ ! -d "$CHECK_DIR" ]; then
        run_bundled_setup
    fi
fi

# ── CLI install ──────────────────────────────────────────────────────────────
if command -v vynx &>/dev/null || [ "$NO_CONFIRM" = true ]; then
    install_cli
fi

# ── Backup + Copy (preserving protected files) ───────────────────────────────
echo ""
echo -e "${NC}• Switching quickshell source...${NC}"
mkdir -p "$(dirname "$TARGET_DIR")"

# Step 1: Save protected files from current TARGET_DIR
if [ -d "$TARGET_DIR" ]; then
    backup_protected_files "$TARGET_DIR"
fi

# Step 2: Backup the whole directory
if [ "$BACKUP" = true ] && [ -d "$TARGET_DIR" ]; then
    BACKUP_DIR="${TARGET_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backing up current config to: $BACKUP_DIR${NC}"
    mv "$TARGET_DIR" "$BACKUP_DIR"
fi

# Step 3: Copy new source
cp -r "$SOURCE_DIR/." "$TARGET_DIR/"
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Copy failed!${NC}"
    exit 1
fi

# Ensure all scripts are executable
find "$TARGET_DIR/scripts" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) -exec chmod +x {} + 2>/dev/null

# Step 4: Restore protected files (overwrite what was just copied)
restore_protected_files "$TARGET_DIR"

echo -e "${GREEN}✓ Quickshell source switched successfully${NC}"

# ── Config Reset ─────────────────────────────────────────────────────────────
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
if [ "$UPDATE_ONLY" = false ] && [ "$PRESERVE_CONFIG" = false ] && [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}• Existing config detected at: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}⚠ This fork uses a different config structure (pages vs toggles). Keeping the old file may cause crashes.${NC}"
    
    do_reset=false
    if [ "$NO_CONFIRM" = true ]; then
        do_reset=true
    else
        echo -ne "${CYAN}Reset config.json now? (The file will be renamed as backup) (y/n): ${NC}"
        read -r response
        [[ "$response" =~ ^[Yy]$ ]] && do_reset=true
    fi

    if [ "$do_reset" = true ]; then
        BACKUP_CFG="${CONFIG_FILE}_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$CONFIG_FILE" "$BACKUP_CFG"
        echo -e "${GREEN}✓ Config reset complete (Backup: $(basename "$BACKUP_CFG"))${NC}"
    else
        echo -e "${RED}⚠ Warning: You chose NOT to reset. If Quickshell crashes, delete config.json manually.${NC}"
    fi
fi

# ── Hyprland config ──────────────────────────────────────────────────────────
if [ "$SKIP_HYPRLAND" = false ]; then
    sleep 0.5
    setup_hyprland_rules
    setup_hyprland_source
else
    echo -e "${YELLOW}• Skipping hyprland config setup (--skip-hyprland)${NC}"
fi

# ── Restart ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${NC}• Restarting Quickshell...${NC}"
pkill -x qs
sleep 0.5
hyprctl reload
sleep 0.5
nohup qs --path "$HOME/.config/quickshell/ii" >/dev/null 2>&1 &

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}         Setup completed!    ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""