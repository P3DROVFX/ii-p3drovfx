#!/usr/bin/env bash
# generate-lockscreen-colors.sh
# Pre-generates M3 color scheme for the lockscreen wallpaper using matugen --dry-run.
# Does NOT touch colors.json or any other active theme file.
# Output: $STATE_DIR/user/generated/lockscreen_colors.json
# Also backs up current desktop colors to: $STATE_DIR/user/generated/desktop_colors.json

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"

CURRENT_COLORS="$STATE_DIR/user/generated/colors.json"
LOCKSCREEN_COLORS="$STATE_DIR/user/generated/lockscreen_colors.json"
DESKTOP_COLORS="$STATE_DIR/user/generated/desktop_colors.json"

imgpath=""
mode_flag=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image) imgpath="$2"; shift 2 ;;
        --mode)  mode_flag="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$imgpath" || ! -f "$imgpath" ]]; then
    echo "[generate-lockscreen-colors] ERROR: --image <path> required and file must exist" >&2
    exit 1
fi

# Auto-detect mode if not set
if [[ -z "$mode_flag" ]]; then
    current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
    [[ "$current_mode" == "prefer-dark" ]] && mode_flag="dark" || mode_flag="light"
fi

# Get scheme type from config
type_flag=$(jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "scheme-tonal-spot")
allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot scheme-vibrant scheme-intense auto scheme-auto)
valid=0
for t in "${allowed_types[@]}"; do [[ "$type_flag" == "$t" ]] && { valid=1; break; }; done
[[ $valid -eq 0 ]] && type_flag="scheme-tonal-spot"
[[ "$type_flag" == "auto" || "$type_flag" == "scheme-auto" ]] && type_flag="scheme-tonal-spot"
[[ "$type_flag" == "scheme-intense" ]] && type_flag="scheme-fidelity"

echo "[generate-lockscreen-colors] Generating for: $imgpath (mode=$mode_flag type=$type_flag)"

mkdir -p "$STATE_DIR/user/generated"

# Step 1: backup current desktop colors (cp = new inode, does NOT trigger inotify on existing watch)
if [[ -f "$CURRENT_COLORS" ]]; then
    cp "$CURRENT_COLORS" "$DESKTOP_COLORS"
    echo "[generate-lockscreen-colors] Desktop colors backed up → $DESKTOP_COLORS"
fi

# Step 2: use matugen --dry-run --json hex to get colors WITHOUT writing any files
#         then transform the JSON to match the colors.json format (snake_case keys, hex values)
matugen_json=$(matugen image "$imgpath" \
    --json hex \
    --source-color-index 0 \
    --mode "$mode_flag" \
    --type "$type_flag" \
    --dry-run --quiet 2>/dev/null)

if [[ -z "$matugen_json" ]]; then
    echo "[generate-lockscreen-colors] ERROR: matugen returned empty output" >&2
    exit 1
fi

# Transform matugen JSON output → colors.json format
python3 - <<'PYEOF' "$matugen_json" "$mode_flag" > "$LOCKSCREEN_COLORS.tmp"
import json, sys

raw = sys.argv[1]
mode = sys.argv[2]  # "dark" or "light"

try:
    data = json.loads(raw)
except Exception as e:
    print(f"[generate-lockscreen-colors] ERROR: failed to parse matugen JSON: {e}", file=sys.stderr)
    sys.exit(1)

colors = data.get("colors", {})
result = {}

# Keys to skip (MaterialThemeLoader skips these, and they can cause type issues)
SKIP_KEYS = {"darkmode", "transparent", "source_color"}

for k, v in colors.items():
    if k in SKIP_KEYS:
        continue
    if isinstance(v, dict):
        # Pick the correct color variant based on mode
        variant = "dark" if mode == "dark" else "light"
        color_entry = v.get(variant) or v.get("default") or {}
        hex_val = color_entry.get("color", "")
        if hex_val:
            result[k] = hex_val

print(json.dumps(result, indent=2))
PYEOF

py_status=$?
if [[ $py_status -ne 0 || ! -s "$LOCKSCREEN_COLORS.tmp" ]]; then
    echo "[generate-lockscreen-colors] ERROR: failed to generate lockscreen_colors.json" >&2
    rm -f "$LOCKSCREEN_COLORS.tmp"
    exit 1
fi

mv "$LOCKSCREEN_COLORS.tmp" "$LOCKSCREEN_COLORS"
echo "[generate-lockscreen-colors] Done → $LOCKSCREEN_COLORS"
