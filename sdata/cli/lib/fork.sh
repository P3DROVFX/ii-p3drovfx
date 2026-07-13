#!/usr/bin/env bash

# Command: vynx fork <preset|url> [branch]
# Switch to a fork. Optionally pass a branch name as positional arg.
# Usage: vynx fork end4
#        vynx fork end4 hefty-hype
#        vynx fork https://github.com/USER/REPO
if [ -z "$1" ]; then
    echo -e "${RED}Usage: vynx fork <preset|url> [branch]${NC}"
    echo "Presets: p3drovfx (mine), end4, vynx (upstream)"
    exit 1
fi
FORK_VAL="$1"; shift
BRANCH_VAL="$1"; shift

SETUP_FLAGS="--switch --fork $FORK_VAL"
[ -n "$BRANCH_VAL" ] && SETUP_FLAGS="$SETUP_FLAGS --branch $BRANCH_VAL"
[[ "$VERBOSE" == "true" ]]    && SETUP_FLAGS="$SETUP_FLAGS -v"
[[ "$NO_CONFIRM" == "true" ]] && SETUP_FLAGS="$SETUP_FLAGS --no-confirm"

bash "$SCRIPT_DIR/setup-ii-vynx.sh" $SETUP_FLAGS