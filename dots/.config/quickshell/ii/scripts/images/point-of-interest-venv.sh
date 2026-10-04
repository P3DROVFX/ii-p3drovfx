#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv="$(eval echo "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv}")"
if [ -f "$venv/bin/activate" ]; then
    source "$venv/bin/activate"
fi
python3 "$SCRIPT_DIR/point_of_interest.py" "$@"
