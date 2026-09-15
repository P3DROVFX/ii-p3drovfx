#!/usr/bin/env bash
# Compile every panel-family SDF shader with qsb, mirroring install.sh's build phase.
# usage: build.sh [status]
#   status : exit 0 when every *.frag under assets/shaders has its .qsb compiled; print the missing ones.
#   (none) : compile everything, print how many.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QSB="$(command -v qsb || echo /usr/lib/qt6/bin/qsb)"

[[ -x "$QSB" ]] || { echo "qsb not found, install qt6-shadertools" >&2; exit 3; }

if [[ "${1:-}" == "status" ]]; then
    missing=0
    while IFS= read -r f; do
        [[ -f "$f.qsb" ]] || { echo "$f" >&2; missing=1; }
    done < <(find "$ROOT/assets/shaders" -name '*.frag')
    exit $missing
fi

n=0
while IFS= read -r f; do
    "$QSB" --qt6 -o "$f.qsb" "$f" || { echo "qsb failed on $f" >&2; exit 1; }
    n=$((n + 1))
done < <(find "$ROOT/assets/shaders" -name '*.frag')
echo "compiled $n shaders"