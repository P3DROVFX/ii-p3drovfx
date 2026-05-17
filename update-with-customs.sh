#!/usr/bin/env bash
set -euo pipefail

VERBOSE=false
DRY_RUN=false

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        -v|--verbose) VERBOSE=true ;;
    esac
done

log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "\e[1;34m[INFO]\e[0m $1"
    fi
}
warn() { echo -e "\e[1;33m[WARN]\e[0m $1"; }
err() { echo -e "\e[1;31m[ERROR]\e[0m $1"; }

FORK_DIR=""
for candidate in "$HOME/Downloads/project/ii-vynx" "$HOME/.local/share/ii-vynx-fork"; do
    if [ -d "$candidate/.git" ]; then
        FORK_DIR="$candidate"
        break
    fi
done

if [ -z "$FORK_DIR" ]; then
    err "Cannot find ii-vynx fork repository"
    exit 1
fi

log "Using fork at: $FORK_DIR"

# ── Dry Run ────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    cd "$FORK_DIR"
    git fetch origin 2>/dev/null || { warn "Cannot reach remote."; exit 1; }

    DEFAULT_BRANCH="$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' || echo "main")"
    BEHIND="$(git rev-list --count "HEAD..origin/$DEFAULT_BRANCH" 2>/dev/null || echo "0")"

    if [ "$BEHIND" -eq 0 ]; then
        echo "Already up to date."
        exit 0
    fi

    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        warn "Uncommitted changes in fork clone."
    fi

    git fetch origin "$DEFAULT_BRANCH" 2>/dev/null
    LOCAL_TREE="$(git rev-parse HEAD)"
    REMOTE_TREE="$(git rev-parse "origin/$DEFAULT_BRANCH")"
    MERGE_BASE="$(git merge-base "$LOCAL_TREE" "$REMOTE_TREE")"

    if git merge-tree "$MERGE_BASE" "$LOCAL_TREE" "$REMOTE_TREE" 2>/dev/null | grep -q "^changed in both"; then
        warn "Merge conflicts detected. Manual resolution needed."
        exit 1
    fi

    echo "Ready to update ($BEHIND new commit(s)). No conflicts."
    exit 0
fi

# ── Full Update ────────────────────────────────────────────────────
log "Pulling latest changes from your fork..."
cd "$FORK_DIR"

if ! git pull --ff-only; then
    err "Git pull failed."
    exit 1
fi

log "Fork updated. Re-applying config..."

VERBOSE_FLAG=""
[ "$VERBOSE" = true ] && VERBOSE_FLAG="-v"

if ! bash "$FORK_DIR/setup-ii-vynx.sh" --no-confirm --preserve-config $VERBOSE_FLAG; then
    err "Setup failed."
    exit 1
fi

echo ""
echo -e "\e[1;32m✓ Update complete. Preferences preserved.\e[0m"
exit 0
