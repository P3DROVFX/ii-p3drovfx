#!/usr/bin/env bash
# exec, so stopping the shell's Process stops the generator itself.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")"

if [ -n "$VENV" ] && [ -x "$VENV/bin/python" ]; then
    exec "$VENV/bin/python" "$SCRIPT_DIR/thumbgen.py" "$@"
fi
exec python3 "$SCRIPT_DIR/thumbgen.py" "$@"
