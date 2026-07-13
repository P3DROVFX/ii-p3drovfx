#!/usr/bin/env bash

# Command: vynx branch <name>
# Switch branch on the currently active fork.
if [ -z "$1" ]; then
    echo -e "${RED}Usage: vynx branch <name>${NC}"
    echo "Run 'vynx list-branches' to see available branches."
    exit 1
fi
BRANCH_VAL="$1"; shift

SETUP_FLAGS="--switch --branch $BRANCH_VAL"
[[ "$VERBOSE" == "true" ]]    && SETUP_FLAGS="$SETUP_FLAGS -v"
[[ "$NO_CONFIRM" == "true" ]] && SETUP_FLAGS="$SETUP_FLAGS --no-confirm"
SETUP_FLAGS="$SETUP_FLAGS --preserve-config"

bash "$SCRIPT_DIR/setup-ii-vynx.sh" $SETUP_FLAGS ${PASS_FLAGS+"${PASS_FLAGS[@]}"}