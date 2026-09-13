#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"

if [ -f "$VENV_PATH/bin/activate" ]; then
    source "$VENV_PATH/bin/activate"
fi

# exec so the Python process replaces this shell and inherits its parent-death
# signal (ProcUtils.pdeath); otherwise Python would be a child of the wrapper
# and survive as an orphan when Quickshell is killed.
exec python3 "$SCRIPT_DIR/ytmusic-lyrics.py" "$@"
