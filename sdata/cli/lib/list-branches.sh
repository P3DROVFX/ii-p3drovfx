#!/usr/bin/env bash

# Command: vynx list-branches [fork]
FORK_VAL="$1"
SETUP_FLAGS="--list-branches"
[ -n "$FORK_VAL" ] && SETUP_FLAGS="$SETUP_FLAGS --fork $FORK_VAL"
bash "$SCRIPT_DIR/setup-ii-vynx.sh" $SETUP_FLAGS