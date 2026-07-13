#!/usr/bin/env bash

# Command: vynx switch [--fork X] [--branch Y]
# Combination switch (default --preserve-config).
SETUP_FLAGS="--switch"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fork)   SETUP_FLAGS="$SETUP_FLAGS --fork $2"; shift 2 ;;
        --branch) SETUP_FLAGS="$SETUP_FLAGS --branch $2"; shift 2 ;;
        --no-preserve-config) ;;
        *) SETUP_FLAGS="$SETUP_FLAGS $1"; shift ;;
    esac
done

[[ "$VERBOSE" == "true" ]]    && SETUP_FLAGS="$SETUP_FLAGS -v"
[[ "$NO_CONFIRM" == "true" ]] && SETUP_FLAGS="$SETUP_FLAGS --no-confirm"
SETUP_FLAGS="$SETUP_FLAGS --preserve-config"

bash "$SCRIPT_DIR/setup-ii-vynx.sh" $SETUP_FLAGS