#!/usr/bin/env bash

# Command: vynx update
# Update the currently active fork+branch from GitHub.
# Usage: vynx update [--no-confirm] [-v]
echo -e "${BLUE}Updating current fork+branch from GitHub…${NC}"

SETUP_FLAGS="--update"
[[ "$VERBOSE" == "true" ]]   && SETUP_FLAGS="$SETUP_FLAGS -v"
[[ "$NO_CONFIRM" == "true" ]] && SETUP_FLAGS="$SETUP_FLAGS --no-confirm"
# preserve config by default for updates
SETUP_FLAGS="$SETUP_FLAGS --preserve-config"

bash "$SCRIPT_DIR/setup-ii-vynx.sh" $SETUP_FLAGS