#!/usr/bin/env bash
#
# Regenerates the colour previews that ship beside the default wallpaper.
#
# The shell shows assets/images/default_wallpaper.png whenever the user has not
# chosen a wallpaper yet, and every scheme swatch (Settings -> Colors & Themes,
# and the Welcome's "Make it yours") is painted from
# wallpaper_preview_colors.json - which only a wallpaper switch ever writes.
# Nothing runs one on a fresh install, so these two files are what keep the first
# run from showing empty buttons, and from paying one generate_colors_material.py
# per visible scheme to get them.
#
# Run this whenever assets/images/default_wallpaper.png changes:
#
#     bash scripts/colors/generate-default-previews.sh
#
# Both modes ship because switchwall generates the previews with the mode it was
# called with, and the Welcome carries a dark/light toggle right above the grids.

set -euo pipefail

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

WALLPAPER="$SHELL_DIR/assets/images/default_wallpaper.png"
OUT_DIR="$SHELL_DIR/assets/data"
TERMSCHEME="$SCRIPT_DIR/terminal/scheme-base.json"

if [[ ! -f "$WALLPAPER" ]]; then
    echo "Missing default wallpaper: $WALLPAPER" >&2
    exit 1
fi

# The same activation switchwall.sh performs, for the same reason: the
# generator's `#!/usr/bin/env -S _/bin/sh_ -c_...` shebang is fragile enough that
# running the file directly is not worth relying on.
venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$XDG_STATE_HOME/quickshell/.venv}"
# shellcheck disable=SC1090
source "$(eval echo "$venv")/bin/activate"

mkdir -p "$OUT_DIR"

for mode in dark light; do
    out="$OUT_DIR/default_preview_colors_${mode}.json"
    echo "Generating $(basename "$out")"
    # --termscheme is not optional: without it the generator reaches
    # term_source_colors undefined and exits non-zero after writing the previews.
    python3 "$SCRIPT_DIR/generate_colors_material.py" \
        --path "$WALLPAPER" \
        --mode "$mode" \
        --termscheme "$TERMSCHEME" --blend_bg_fg \
        --all-previews "$out" \
        > /dev/null
done

echo "Done. Regenerate these together with assets/images/default_wallpaper.png."
