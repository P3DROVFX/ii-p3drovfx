#!/usr/bin/env bash
# Runs color_overrides.py inside the shell's venv (materialyoucolor lives there).
unset LD_LIBRARY_PATH PYTHONHOME PYTHONPATH
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv}"
exec "$(eval echo "$venv")/bin/python3" "$(dirname "$(readlink -f "$0")")/color_overrides.py" "$@"
