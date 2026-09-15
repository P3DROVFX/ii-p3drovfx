#!/usr/bin/env bash
# Runs library_index.py inside the shell's shared Python environment, where its
# dependencies are declared (sdata/uv/requirements.in); a bare python3 only works
# on machines that happen to have them installed system-wide.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate
python3 "$SCRIPT_DIR/library_index.py" "$@"
EXIT_CODE=$?
deactivate

exit $EXIT_CODE
