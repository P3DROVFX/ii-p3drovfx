#!/usr/bin/env bash
# Installs the Anki tab's backend into ~/.local/share/ii-anki:
#   venv/     Python venv with the official `anki` package (the same Rust scheduler,
#             renderer and AnkiWeb sync as Anki desktop) and Pillow (image sizes)
#   mathjax/  MathJax 3 for \( \) / \[ \] (optional: skipped without node/npm)
#
# Used by the tab's "Install" button (services/Anki.qml); safe to run standalone and
# to re-run (upgrades in place). Progress lines start with "STEP".
set -euo pipefail

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/ii-anki"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$DATA"

echo "STEP 1/3 Creating the Python environment"
if [ ! -x "$DATA/venv/bin/python" ]; then
    python3 -m venv "$DATA/venv"
fi

echo "STEP 2/3 Installing Anki"
"$DATA/venv/bin/pip" install --quiet --disable-pip-version-check --upgrade anki pillow

echo "STEP 3/3 Installing MathJax"
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    mkdir -p "$DATA/mathjax"
    (cd "$DATA/mathjax" && { [ -f package.json ] || npm init -y >/dev/null; } \
        && npm install --silent --no-audit --no-fund mathjax-full@3.2.2 >/dev/null)
    cp "$HERE/tex2svg.mjs" "$DATA/mathjax/tex2svg.mjs"
else
    echo "WARN node/npm not found: formulas will show as TeX source"
fi

"$DATA/venv/bin/python" -c "import PIL; from anki.buildinfo import version; print('DONE anki', version)"
