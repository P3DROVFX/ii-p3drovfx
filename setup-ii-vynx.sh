#!/bin/bash

# ii-vynx setup / update / fork / branch manager
#
# Always downloads the latest version from GitHub and replaces the ii folder.
# No local cache — ~/.local/share is used only for backups of the previous ii.
#
# Usage:
#   ./setup-ii-vynx.sh                              # Install/Setup legacy (uses local clone)
#   ./setup-ii-vynx.sh --update                     # Update current fork+branch from GitHub
#   ./setup-ii-vynx.sh --fork <preset|url>          # Switch fork (default branch)
#   ./setup-ii-vynx.sh --branch <name>             # Switch branch on current fork
#   ./setup-ii-vynx.sh --fork end4 --branch main   # Switch fork + branch together
#   ./setup-ii-vynx.sh --switch                     # Used with --fork/--branch: only switch, no full install
#   ./setup-ii-vynx.sh --list-branches              # List current fork's remote branches
#   ./setup-ii-vynx.sh --list-forks                 # List known fork presets
#
# Flags:
#   -v, --verbose            Verbose output
#   --no-backup              Skip ~/.local backup of previous ii
#   --force-install          Skip illogical-impulse presence check
#   --no-confirm             Skip all confirmations
#   --preserve-config        Keep existing config.json (useful for updates/branch switch)
#   --rebuild-quickshell     Rebuild Quickshell from source
#   --ii-subdir <name>       Override auto-detection of ii* folder (rarely needed)

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
INVOKED_AS="$(basename "$0")"
if [[ "$INVOKED_AS" == "vynx" ]]; then
    LIB_DIR="$SCRIPT_DIR/sdata/cli/lib"
    BASE_DIR="$SCRIPT_DIR"
    VERBOSE=false
    NO_CONFIRM=false
    PASS_FLAGS=()
    TEMP_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)          VERBOSE=true; PASS_FLAGS+=("-v"); shift ;;
            --no-confirm)          NO_CONFIRM=true; PASS_FLAGS+=("--no-confirm"); shift ;;
            --preserve-config)     PASS_FLAGS+=("--preserve-config"); shift ;;
            --no-backup)           PASS_FLAGS+=("--no-backup"); shift ;;
            --force-install)       PASS_FLAGS+=("--force-install"); shift ;;
            --rebuild-quickshell)  PASS_FLAGS+=("--rebuild-quickshell"); shift ;;
            *) TEMP_ARGS+=("$1"); shift ;;
        esac
    done
    set -- "${TEMP_ARGS[@]}"

    COMMAND="$1"; shift
    case "$COMMAND" in
        run|restart|update|remove-cli|hyprset|fork|branch|switch|list-forks|list-branches)
            if [ -f "$LIB_DIR/${COMMAND}.sh" ]; then
                source "$LIB_DIR/${COMMAND}.sh" "$@"
                exit $?
            else
                echo -e "${RED}Error: $COMMAND not found${NC}"; exit 1
            fi
            ;;
        "")
            echo "Usage: vynx [-v] {run|restart|update|remove-cli|hyprset|fork|branch|switch|list-forks|list-branches}"; exit 1 ;;
        *)
            echo -e "${RED}Invalid command: $COMMAND${NC}"; exit 1
    esac
fi

# ── Paths ────────────────────────────────────────────────────────────────────
STANDARD_SCRIPT_DIR="$HOME/.local/share/ii-vynx"
BACKUP_BASE_DIR="$HOME/.local/share/ii-backups"
CONFIG_DIR="$HOME/.config"
CHECK_DIR="$CONFIG_DIR/illogical-impulse"
TARGET_DIR="$CONFIG_DIR/quickshell/ii"
STATE_DIR="$TARGET_DIR"  # state files (.active-*) live inside ii/

# ── Fork presets ─────────────────────────────────────────────────────────────
declare -A PRESET_URLS=(
    ["p3drovfx"]="https://github.com/P3DROVFX/ii-vynx"
    ["mine"]="https://github.com/P3DROVFX/ii-vynx"
    ["end4"]="https://github.com/end-4/dots-hyprland"
    ["vynx"]="https://github.com/vaguesyntax/ii-vynx"
    ["upstream"]="https://github.com/vaguesyntax/ii-vynx"
)
declare -A PRESET_DEFAULT_BRANCH=(
    ["p3drovfx"]="main" ["mine"]="main"
    ["end4"]="main"
    ["vynx"]="main" ["upstream"]="main"
)

# ── Default flags ─────────────────────────────────────────────────────────────
VERBOSE=false
BACKUP=true
FORCE_INSTALL=false
NO_CONFIRM=false
PRESERVE_CONFIG=false
REBUILD_QS=false
ACTION=""            # "update" | "switch"
FORK_ARG=""
BRANCH_ARG=""
II_SUBDIR_OVERRIDE=""
LIST_BRANCHES=false
LIST_FORKS=false

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)         VERBOSE=true; shift ;;
        --no-backup)          BACKUP=false; shift ;;
        --force-install)      FORCE_INSTALL=true; shift ;;
        --no-confirm)         NO_CONFIRM=true; FORCE_INSTALL=true; shift ;;
        --preserve-config)    PRESERVE_CONFIG=true; shift ;;
        --rebuild-quickshell) REBUILD_QS=true; shift ;;
        --update)             ACTION="update"; shift ;;
        --switch)             ACTION="switch"; shift ;;
        --fork)               FORK_ARG="$2"; ACTION="${ACTION:-switch}"; shift 2 ;;
        --branch)             BRANCH_ARG="$2"; ACTION="${ACTION:-switch}"; shift 2 ;;
        --ii-subdir)          II_SUBDIR_OVERRIDE="$2"; shift 2 ;;
        --list-branches)      LIST_BRANCHES=true; shift ;;
        --list-forks)         LIST_FORKS=true; shift ;;
        -h|--help|help)
            sed -n '1,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo -e "${RED}Unknown flag: $1${NC}"
            echo "Run '$0 --help' for usage."
            exit 1 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
log_verbose() {
    [ "$VERBOSE" = true ] && echo -e "${BLUE}[VERBOSE] $1${NC}"
}

# Normalize git@github.com:USER/REPO[.git] and https://github.com/USER/REPO[.git]
# to canonical https URL: https://github.com/USER/REPO
normalize_github_url() {
    local raw="$1"
    raw="${raw%.git}"
    raw="${raw%/}"
    if [[ "$raw" == git@github.com:* ]]; then
        raw="https://github.com/${raw#git@github.com:}"
    elif [[ "$raw" == https://github.com/* ]]; then
        : # already canonical-ish
    elif [[ "$raw" == http://github.com/* ]]; then
        raw="https://${raw#http://}"
    fi
    echo "$raw"
}

# Always clone over HTTPS (more portable, supports anonymous public clones)
clone_url_for() {
    local url="$1"
    echo "$url"
}

# Match a normalized URL back to a preset id (or "custom")
fork_id_from_url() {
    local norm_url
    norm_url="$(normalize_github_url "$1")"
    for id in "${!PRESET_URLS[@]}"; do
        if [ "$(normalize_github_url "${PRESET_URLS[$id]}")" = "$norm_url" ]; then
            echo "$id"
            return 0
        fi
    done
    echo "custom"
}

# Resolve a --fork argument (preset id or raw URL) into (url, default_branch)
# Returns "url|branch" on stdout.
resolve_fork_arg() {
    local arg="$1"
    local key
    # case-insensitive preset match
    key="$(echo "$arg" | tr '[:upper:]' '[:lower:]')"
    if [ -n "${PRESET_URLS[$key]:-}" ]; then
        echo "${PRESET_URLS[$key]}|${PRESET_DEFAULT_BRANCH[$key]}"
        return 0
    fi
    # Not a preset — treat as URL (normalize)
    local norm
    norm="$(normalize_github_url "$arg")"
    if [[ "$norm" == https://github.com/* ]]; then
        echo "$norm|default"
        return 0
    fi
    echo -e "${RED}Invalid fork: $arg${NC}" >&2
    return 1
}

# Auto-detect the ii* directory inside a freshly cloned repo.
# Honors $II_SUBDIR_OVERRIDE if set; otherwise picks first dots/.config/quickshell/ii*
detect_ii_subdir() {
    local repo="$1"
    local base="$repo/dots/.config/quickshell"
    if [ -n "$II_SUBDIR_OVERRIDE" ]; then
        if [ -d "$base/$II_SUBDIR_OVERRIDE" ]; then
            echo "$base/$II_SUBDIR_OVERRIDE"
            return 0
        fi
        echo -e "${RED}--ii-subdir '$II_SUBDIR_OVERRIDE' not found under $base${NC}" >&2
        return 1
    fi
    if [ ! -d "$base" ]; then
        echo -e "${RED}No dots/.config/quickshell in repository${NC}" >&2
        return 1
    fi
    local found
    found="$(find "$base" -maxdepth 1 -type d -name 'ii*' ! -path "$base" | sort | head -n1)"
    if [ -z "$found" ]; then
        echo -e "${RED}No 'ii*' directory found under $base${NC}" >&2
        return 1
    fi
    # Warn if multiple
    local count
    count="$(find "$base" -maxdepth 1 -type d -name 'ii*' ! -path "$base" | wc -l)"
    if [ "$count" -gt 1 ]; then
        echo -e "${YELLOW}• Found $count ii* dirs. Using: $(basename "$found")${NC}" >&2
    fi
    echo "$found"
}

# Read current state files (echoes `remote|branch|fork_id`)
read_current_state() {
    local remote="" branch="" fork_id=""
    [ -f "$STATE_DIR/.active-remote" ] && remote="$(cat "$STATE_DIR/.active-remote" 2>/dev/null)"
    [ -f "$STATE_DIR/.active-branch" ] && branch="$(cat "$STATE_DIR/.active-branch" 2>/dev/null)"
    [ -f "$STATE_DIR/.active-fork" ] && fork_id="$(cat "$STATE_DIR/.active-fork" 2>/dev/null)"
    [ -z "$fork_id" ] && [ -n "$remote" ] && fork_id="$(fork_id_from_url "$remote")"
    [ -z "$branch" ] && branch="main"
    [ -z "$remote" ] && remote="https://github.com/P3DROVFX/ii-vynx"
    echo "$remote|$branch|$fork_id"
}

# Backup ~/.config/quickshell/ii to ~/.local/share/ii-backups/ii_<fork>_<branch>_<ts>
# Keeps only the 3 most recent backups.
backup_to_local() {
    if [ "$BACKUP" = false ] || [ ! -d "$TARGET_DIR" ]; then
        return 0
    fi
    mkdir -p "$BACKUP_BASE_DIR"
    local ts fork_id branch
    ts="$(date +%Y%m%d_%H%M%S)"
    fork_id="$1"
    branch="$2"
    [ -z "$fork_id" ] && fork_id="unknown"
    [ -z "$branch" ] && branch="unknown"
    local dest="$BACKUP_BASE_DIR/ii_${fork_id}_${branch}_${ts}"
    echo -e "${YELLOW}Backing up current ii to: $dest${NC}"
    mv "$TARGET_DIR" "$dest"
    # Keep only the 3 most recent
    local n
    n=$(ls -1d "$BACKUP_BASE_DIR"/ii_* 2>/dev/null | wc -l)
    if [ "$n" -gt 3 ]; then
        ls -1dt "$BACKUP_BASE_DIR"/ii_* 2>/dev/null | tail -n +4 | while read -r old; do
            rm -rf "$old"
            log_verbose "Pruned old backup: $old"
        done
    fi
}

# ── Protected files (decided dynamically per destination fork) ───────────────
# Patterns for files that must NEVER be overwritten (glob-style, relative to TARGET_DIR)
PROTECTED_PATTERNS=(
    "*.env"
    ".env"
    "user/generated/*.json"
)

# populate PROTECTED_FILES array based on whether destination == current fork
compute_protected_files() {
    local dest_fork_id="$1"
    local current_fork_id="$2"

    PROTECTED_FILES=()

    # config.json — handle separately via PRESERVE_CONFIG logic in backup/restore
    # Always consider it for the explicit prompt-based reset flow
    PROTECTED_FILES+=("config.json")
}

backup_protected_files() {
    local target="$1"
    local tmpdir="/tmp/ii-vynx-protected"
    rm -rf "$tmpdir"
    mkdir -p "$tmpdir"

    for rel in "${PROTECTED_FILES[@]}"; do
        local src="$target/$rel"
        if [ -f "$src" ]; then
            if [ "$rel" = "config.json" ] && [ "$PRESERVE_CONFIG" = false ]; then
                echo -e "${YELLOW}• Resetting config.json (not preserving).${NC}"
                continue
            fi
            if [ "$rel" = "modules/settings/configs/AboutConfig.qml" ]; then
                # Only preserve our custom AboutConfig if the active one is ours (has 'update-fork' or '--fork' buttons)
                if ! grep -q -e "update-fork" -e "Fork Switcher" -e "--fork" "$src" 2>/dev/null; then
                    echo -e "${YELLOW}• AboutConfig lacks our switcher. Letting new fork's version replace it.${NC}"
                    continue
                fi
            fi
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
        # skip files already restored by explicit list
        case " ${PROTECTED_FILES[*]} " in
            *" $rel "*) continue ;;
        esac
        local dest_dir="$target/$(dirname "$rel")"
        mkdir -p "$dest_dir"
        cp "$f" "$target/$rel"
        log_verbose "Restored protected pattern: $rel"
    done

    rm -rf "$tmpdir"
}

# ── Qt mismatch check + Quickshell rebuild (existing helpers) ────────────────
check_qt_mismatch() {
    if command -v quickshell &>/dev/null; then
        local warning_msg=$(quickshell --version 2>&1 | grep -i -E "warning|mismatch|abi|symbol")
        if [ -n "$warning_msg" ]; then
            echo -e "${YELLOW}⚠ WARNING: A Qt ABI or symbol mismatch was detected in your current Quickshell installation:${NC}"
            echo -e "${RED}  $warning_msg${NC}"
            echo ""
            return 0
        fi
    fi
    return 1
}

build_quickshell() {
    echo -e "${BLUE}• Rebuilding Quickshell from source to match your system's Qt ABI...${NC}"
    if [ -f /etc/fedora-release ]; then
        echo -e "${NC}• Fedora detected. Installing build dependencies...${NC}"
        sudo dnf install -y cmake extra-cmake-modules qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtwayland-devel wayland-devel libxkbcommon-devel gcc-c++ git
    elif [ -f /etc/arch-release ]; then
        echo -e "${NC}• Arch Linux detected. Installing build dependencies...${NC}"
        sudo pacman -Sy --needed cmake extra-cmake-modules qt6-base qt6-declarative qt6-wayland wayland libxkbcommon gcc git
    elif [ -f /etc/debian_version ]; then
        echo -e "${NC}• Debian/Ubuntu detected. Installing build dependencies...${NC}"
        sudo apt-get update && sudo apt-get install -y cmake extra-cmake-modules qt6-base-dev qt6-declarative-dev qt6-wayland-dev libwayland-dev libxkbcommon-dev g++ git
    else
        echo -e "${YELLOW}⚠ Unknown distribution. Please ensure you have cmake, extra-cmake-modules, Qt6 development libraries, and a C++ compiler installed.${NC}"
    fi

    local temp_dir="/tmp/quickshell-build-$(date +%s)"
    echo -e "${NC}• Cloning Quickshell source code into $temp_dir...${NC}"
    git clone https://github.com/outfoxxed/quickshell.git --recursive "$temp_dir"
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to clone Quickshell repository!${NC}"
        return 1
    fi

    cd "$temp_dir"
    echo -e "${NC}• Configuring build...${NC}"
    cmake -B build -S . -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DCRASH_HANDLER=OFF
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ CMake configuration failed!${NC}"
        return 1
    fi
    echo -e "${NC}• Building DBus bindings first...${NC}"
    cmake --build build -t quickshell-dbus -j$(nproc)
    echo -e "${NC}• Compiling Quickshell...${NC}"
    cmake --build build -j$(nproc)
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Compilation failed!${NC}"
        return 1
    fi
    echo -e "${NC}• Installing binaries to ~/.local/bin/...${NC}"
    cmake --install build
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Installation failed!${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Quickshell compiled and installed successfully to ~/.local/bin!${NC}"
    cd - >/dev/null
    rm -rf "$temp_dir"
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

# ── Core pipeline: clone → backup → rsync → restore state ────────────────────
# Usage: apply_fork_branch <remote_https_url> <branch_name> [<dest_fork_id>]
apply_fork_branch() {
    local remote_url="$1"
    local branch="$2"
    local dest_fork_id="${3:-}"

    [ -z "$remote_url" ] && { echo -e "${RED}apply_fork_branch: empty remote URL${NC}"; return 1; }
    [ -z "$branch" ]    && branch="main"

    # Normalize to canonical HTTPS URL — always clone over HTTPS
    remote_url="$(normalize_github_url "$remote_url")"

    # If fork_id not provided, infer from URL
    [ -z "$dest_fork_id" ] && dest_fork_id="$(fork_id_from_url "$remote_url")"

    # Read current state for protected-files decision
    local current_state current_remote current_branch current_fork_id
    current_state="$(read_current_state)"
    current_remote="${current_state%%|*}"
    local rest="${current_state#*|}"
    current_branch="${rest%%|*}"
    current_fork_id="${rest##*|}"

    local clone_url
    clone_url="$(clone_url_for "$remote_url")"
    local clone_dir="/tmp/ii-switch-$$"

    echo -e "${BLUE}• Cloning $clone_url (branch: $branch)…${NC}"
    rm -rf "$clone_dir"
    
    local clone_success=false
    if [ "$branch" = "default" ]; then
        if git clone --depth=1 --recurse-submodules "$clone_url" "$clone_dir"; then
            clone_success=true
            branch="$(git -C "$clone_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
        fi
    else
        if git clone --depth=1 --recurse-submodules --branch "$branch" "$clone_url" "$clone_dir"; then
            clone_success=true
        fi
    fi

    if [ "$clone_success" = false ]; then
        echo -e "${RED}✗ Clone failed. Check that branch '$branch' exists on $clone_url${NC}"
        echo -e "${RED}  Try: $0 --list-branches${NC}"
        rm -rf "$clone_dir"
        return 1
    fi
    # Defensive: ensure submodules are initialized even when --recurse-submodules
    # silently skipped some (e.g. submodule pinned to a SHA not reachable via --depth=1).
    git -C "$clone_dir" submodule update --init --recursive --depth=1 2>/dev/null || true
    log_verbose "Cloned to $clone_dir"

    # Record the remote HEAD commit SHA (best-effort, for update badges)
    local remote_head=""
    remote_head="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || true)"

    # Auto-detect ii* subdir inside the fresh clone
    local source_dir
    if ! source_dir="$(detect_ii_subdir "$clone_dir")"; then
        echo -e "${RED}✗ Could not locate ii* in $clone_dir${NC}"
        rm -rf "$clone_dir"
        return 1
    fi
    log_verbose "Source ii dir: $source_dir"

    # Decide which files to protect dynamically
    compute_protected_files "$dest_fork_id" "$current_fork_id"
    log_verbose "PROTECTED_FILES: ${PROTECTED_FILES[*]}"

    # Step 1: backup protected files from current TARGET_DIR (if exists)
    if [ -d "$TARGET_DIR" ]; then
        backup_protected_files "$TARGET_DIR"
    fi

    # Step 2: backup whole dir to ~/.local/share/ii-backups/
    backup_to_local "$current_fork_id" "$current_branch"

    # Step 3: ensure parent exists
    mkdir -p "$(dirname "$TARGET_DIR")"

    # Step 4: rsync (or cp fallback) the fresh source into TARGET_DIR
    echo -e "${NC}• Replacing $TARGET_DIR with fresh source…${NC}"
    if command -v rsync &>/dev/null; then
        rsync -a --exclude=".git" "$source_dir/" "$TARGET_DIR/"
    else
        cp -r "$source_dir/." "$TARGET_DIR/"
        find "$TARGET_DIR" -name ".git" -exec rm -rf {} + 2>/dev/null
    fi
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Copy failed!${NC}"
        rm -rf "$clone_dir"
        return 1
    fi

    # Step 5: persist new state files in TARGET_DIR
    mkdir -p "$TARGET_DIR"
    echo "$remote_url" > "$TARGET_DIR/.active-remote"
    echo "$branch"     > "$TARGET_DIR/.active-branch"
    echo "$dest_fork_id" > "$TARGET_DIR/.active-fork"
    [ -n "$remote_head" ] && echo "$remote_head" > "$TARGET_DIR/.active-commit"
    log_verbose "State written: $dest_fork_id @ $branch (HEAD=$remote_head)"

    # Ensure all scripts are executable
    find "$TARGET_DIR/scripts" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) -exec chmod +x {} + 2>/dev/null

    # Step 6: restore protected files (overwrites just-copied versions)
    restore_protected_files "$TARGET_DIR"

    # Step 7: mirror setup scripts to standard location so UI keeps working
    if [ "$SCRIPT_DIR" != "$STANDARD_SCRIPT_DIR" ]; then
        mkdir -p "$STANDARD_SCRIPT_DIR"
        cp "$SOURCE" "$STANDARD_SCRIPT_DIR/setup-ii-vynx.sh" 2>/dev/null || cp "$SCRIPT_DIR/setup-ii-vynx.sh" "$STANDARD_SCRIPT_DIR/setup-ii-vynx.sh"
        chmod +x "$STANDARD_SCRIPT_DIR/setup-ii-vynx.sh"
        for s in update-fork.sh; do
            if [ -f "$SCRIPT_DIR/$s" ]; then
                cp "$SCRIPT_DIR/$s" "$STANDARD_SCRIPT_DIR/$s"
                chmod +x "$STANDARD_SCRIPT_DIR/$s"
            fi
        done
        # Prune obsolete scripts that we no longer ship but may linger from older installs.
        for obsolete in update-with-customs.sh; do
            if [ -f "$STANDARD_SCRIPT_DIR/$obsolete" ] && [ ! -f "$SCRIPT_DIR/$obsolete" ]; then
                rm -f "$STANDARD_SCRIPT_DIR/$obsolete"
                log_verbose "Pruned obsolete script: $STANDARD_SCRIPT_DIR/$obsolete"
            fi
        done
        # sdata cli libs (for vynx subcommands)
        if [ -d "$SCRIPT_DIR/sdata" ]; then
            mkdir -p "$STANDARD_SCRIPT_DIR/sdata/cli/lib"
            cp -r "$SCRIPT_DIR/sdata/cli/lib/." "$STANDARD_SCRIPT_DIR/sdata/cli/lib/" 2>/dev/null
            chmod +x "$STANDARD_SCRIPT_DIR/sdata/cli/lib/"*.sh 2>/dev/null
        fi
        log_verbose "Mirrored scripts to $STANDARD_SCRIPT_DIR"
    fi

    # Cleanup clone
    rm -rf "$clone_dir"
    echo -e "${GREEN}✓ Switched to $dest_fork_id @ $branch${NC}"
    return 0
}

# ── List helpers ─────────────────────────────────────────────────────────────
do_list_forks() {
    echo -e "${CYAN}Available fork presets:${NC}"
    local seen=()
    for id in "${!PRESET_URLS[@]}"; do
        local url="${PRESET_URLS[$id]}"
        # de-dup aliases that point to the same URL
        local dup=false
        for s in "${seen[@]}"; do [ "$s" = "$url" ] && dup=true && break; done
        if [ "$dup" = false ]; then
            seen+=("$url")
            printf "  ${GREEN}%-12s${NC}  %s\n" "$id" "$url"
        fi
    done
    echo ""
    echo "Custom forks are supported by passing a GitHub URL to --fork."
}

do_list_branches() {
    local remote_url="$1"
    [ -z "$remote_url" ] && remote_url="$(read_current_state | cut -d'|' -f1)"
    echo -e "${CYAN}Remote branches of $remote_url:${NC}"
    if ! git ls-remote --heads "$remote_url" 2>/dev/null | sed 's@^.*refs/heads/@@' | sed 's/^/  /'; then
        echo -e "${RED}✗ Failed to reach remote $remote_url${NC}"
        return 1
    fi
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}          ii-vynx setup     ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Handle --list-forks / --list-branches ───────────────────────────────────
if [ "$LIST_FORKS" = true ]; then
    do_list_forks
    exit 0
fi
if [ "$LIST_BRANCHES" = true ]; then
    remote_url=""
    [ -n "$FORK_ARG" ] && remote_url="$(resolve_fork_arg "$FORK_ARG" | cut -d'|' -f1)" || remote_url="$(read_current_state | cut -d'|' -f1)"
    do_list_branches "$remote_url"
    exit $?
fi

# ── Validate illogical-impulse presence (skip with --force-install) ──────────
if [ "$FORCE_INSTALL" = false ]; then
    if [ ! -d "$CHECK_DIR" ]; then
        echo -e "${YELLOW}• illogical-impulse base dotfiles not found. Running the bundled setup install…${NC}"
        run_bundled_setup
    fi
fi

# ── Quickshell Qt ABI check ──────────────────────────────────────────────────
if [ "$REBUILD_QS" = true ]; then
    build_quickshell
elif check_qt_mismatch; then
    if [ "$NO_CONFIRM" = true ]; then
        echo -e "${YELLOW}Automatic rebuild triggered due to Qt ABI mismatch in no-confirm mode...${NC}"
        build_quickshell
    else
        echo -ne "${CYAN}Do you want to automatically rebuild Quickshell from source now to fix this mismatch? (y/n): ${NC}"
        read -r qs_response
        if [[ "$qs_response" =~ ^[Yy]$ ]]; then build_quickshell
        else echo -e "${YELLOW}⚠ Skipping rebuild. Warning/crashes might persist if system Qt version does not match Quickshell binary.${NC}"
        fi
    fi
fi

# ── Resolve action ────────────────────────────────────────────────────────────
# Build the (remote_url, branch, dest_fork_id) tuple from flags / current state.
RESOLVED_URL=""
RESOLVED_BRANCH=""
RESOLVED_FORK_ID=""

if [ "$ACTION" = "update" ]; then
    # Read current state and apply
    current_state="$(read_current_state)"
    RESOLVED_URL="${current_state%%|*}"
    rest="${current_state#*|}"
    RESOLVED_BRANCH="${rest%%|*}"
    RESOLVED_FORK_ID="${rest##*|}"
    if [ -z "$RESOLVED_URL" ]; then
        echo -e "${RED}✗ No active fork recorded ($STATE_DIR/.active-remote missing). Pass --fork <preset|url>.${NC}"
        exit 1
    fi
elif [ "$ACTION" = "switch" ]; then
    if [ -z "$FORK_ARG" ] && [ -z "$BRANCH_ARG" ]; then
        echo -e "${RED}✗ --switch requires --fork <x> and/or --branch <name>${NC}"
        exit 1
    fi

    # Resolve FORK_ARG (if provided) or fall back to current state
    if [ -n "$FORK_ARG" ]; then
        resolved_pair="$(resolve_fork_arg "$FORK_ARG")" || exit 1
        RESOLVED_URL="${resolved_pair%|*}"
        default_branch="${resolved_pair#*|}"
        RESOLVED_FORK_ID="$(fork_id_from_url "$RESOLVED_URL")"
    else
        current_state="$(read_current_state)"
        RESOLVED_URL="${current_state%%|*}"
        rest="${current_state#*|}"
        default_branch="${rest%%|*}"
        RESOLVED_FORK_ID="${rest##*|}"
    fi

    # Branch override
    if [ -n "$BRANCH_ARG" ]; then
        RESOLVED_BRANCH="$BRANCH_ARG"
    else
        RESOLVED_BRANCH="$default_branch"
    fi
fi

# ── Confirm (interactive mode only) ─────────────────────────────────────────
if [ "$ACTION" != "" ] && [ "$NO_CONFIRM" = false ]; then
    echo -e "${BLUE}This will pull & replace ${CYAN}$TARGET_DIR${NC}${BLUE} with:${NC}"
    echo -e "  fork:   ${CYAN}$RESOLVED_FORK_ID${NC}"
    echo -e "  branch: ${CYAN}$RESOLVED_BRANCH${NC}"
    echo -e "  remote: ${CYAN}$RESOLVED_URL${NC}"
    if [ "$PRESERVE_CONFIG" = true ]; then
        echo -e "${BLUE}config.json will be preserved.${NC}"
    else
        echo -e "${YELLOW}config.json will be reset (you'll be asked to confirm).${NC}"
    fi
    echo -e "${RED}Continue? (y/n): ${NC}"
    read -r response
    [[ ! "$response" =~ ^[Yy]$ ]] && echo -e "${RED}Cancelled.${NC}" && exit 0
    echo ""
fi

# ── Pre-action: CLI install (best-effort) ────────────────────────────────────
if [ "$NO_CONFIRM" = true ]; then
    install_cli 2>/dev/null || true
fi

# ── Execute ──────────────────────────────────────────────────────────────────
EXIT_CODE=0
if [ "$ACTION" != "" ]; then
    # Switch / Update path
    apply_fork_branch "$RESOLVED_URL" "$RESOLVED_BRANCH" "$RESOLVED_FORK_ID"
    EXIT_CODE=$?
else
    # ── Install legacy path: detect local origin, switch from there ──────────
    LOCAL_REMOTE=""
    LOCAL_BRANCH=""
    LOCAL_FORK_ID=""

    if [ -d "$SCRIPT_DIR/.git" ]; then
        raw_remote="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)"
        [ -n "$raw_remote" ] && LOCAL_REMOTE="$(normalize_github_url "$raw_remote")"
        LOCAL_BRANCH="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        [ -z "$LOCAL_BRANCH" ] && LOCAL_BRANCH="main"
        LOCAL_FORK_ID="$(fork_id_from_url "$LOCAL_REMOTE")"
    fi

    if [ -z "$LOCAL_REMOTE" ]; then
        # No git remote in SCRIPT_DIR — fall back to default preset
        echo -e "${YELLOW}• SCRIPT_DIR is not a git repo. Defaulting to P3DROVFX/ii-vynx @ main.${NC}"
        LOCAL_REMOTE="https://github.com/P3DROVFX/ii-vynx"
        LOCAL_BRANCH="main"
        LOCAL_FORK_ID="p3drovfx"
    fi

    # Confirm legacy install
    if [ "$NO_CONFIRM" = false ]; then
        echo -e "${BLUE}Installing illogical-impulse from:${NC}"
        echo -e "  fork:   ${CYAN}$LOCAL_FORK_ID${NC}"
        echo -e "  branch: ${CYAN}$LOCAL_BRANCH${NC}"
        echo -e "  remote: ${CYAN}$LOCAL_REMOTE${NC}"
        echo -e "${RED}Continue? (y/n): ${NC}"
        read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && echo -e "${RED}Cancelled.${NC}" && exit 0
        echo ""
    fi

    # Ensure CLI is installed in legacy path too
    install_cli 2>/dev/null || true

    apply_fork_branch "$LOCAL_REMOTE" "$LOCAL_BRANCH" "$LOCAL_FORK_ID"
    EXIT_CODE=$?
fi

if [ "$EXIT_CODE" -ne 0 ]; then
    echo -e "${RED}✗ Action failed with code $EXIT_CODE${NC}"
    exit $EXIT_CODE
fi

# ── Config Reset (interactive prompt when not preserving) ────────────────────
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
if [ "$PRESERVE_CONFIG" = false ] && [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}• Existing config detected at: $CONFIG_FILE${NC}"
    do_reset=false
    if [ "$NO_CONFIRM" = true ]; then
        do_reset=true
    else
        echo -ne "${CYAN}Reset config.json now? (Backup will be made) (y/n): ${NC}"
        read -r response
        [[ "$response" =~ ^[Yy]$ ]] && do_reset=true
    fi
    if [ "$do_reset" = true ]; then
        BACKUP_CFG="${CONFIG_FILE}_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$CONFIG_FILE" "$BACKUP_CFG"
        echo -e "${GREEN}✓ Config reset complete (Backup: $(basename "$BACKUP_CFG"))${NC}"
    else
        echo -e "${YELLOW}Kept existing config.json. If Quickshell crashes, reset it manually.${NC}"
    fi
fi

# ── Restart Quickshell ───────────────────────────────────────────────────────
echo ""
echo -e "${NC}• Restarting Quickshell...${NC}"
pkill -x qs
sleep 0.5
hyprctl reload
sleep 0.5
nohup qs --path "$TARGET_DIR" >/dev/null 2>&1 &

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}         Setup completed!    ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""