#!/usr/bin/env bash
# Runs depth.py inside the shell's venv (numpy, opencv and pillow live there),
# at the lowest CPU and IO priority: cutting out a wallpaper is never urgent.
unset LD_LIBRARY_PATH PYTHONHOME PYTHONPATH
export PATH="$HOME/.local/bin:$PATH"
venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/.venv}"
exec nice -n 19 ionice -c 3 "$(eval echo "$venv")/bin/python3" -E "$(dirname "$(readlink -f "$0")")/depth.py" "$@"
