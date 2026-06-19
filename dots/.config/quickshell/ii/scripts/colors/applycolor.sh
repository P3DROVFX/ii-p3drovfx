#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

colornames=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f1)
colorstrings=$(cat $STATE_DIR/user/generated/material_colors.scss | cut -d: -f2 | cut -d ' ' -f2 | cut -d ";" -f1)
IFS=$'\n'
colorlist=($colornames)     # Array of color names
colorvalues=($colorstrings) # Array of color values

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Apply colors using Python for robust literal string replacement (no regex or sed shell escaping issues)
  python3 -c '
import sys
import os
scss_path, template_path, output_path = sys.argv[1:4]
vars_dict = {}
try:
    with open(scss_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("$") or ":" not in line:
                continue
            name, val = line.split(":", 1)
            name = name.strip()
            val = val.strip().rstrip(";").lstrip("#")
            vars_dict[name + " #"] = val
except Exception as e:
    print(f"Error reading colors scss: {e}", file=sys.stderr)
    sys.exit(1)

if len(vars_dict) < 10:
    print("Error: Too few colors generated. Aborting Kitty theme update.", file=sys.stderr)
    sys.exit(1)

with open(template_path, "r") as f:
    content = f.read()

for name, val in vars_dict.items():
    content = content.replace(name, val)

import re
if re.search(r"#\$[a-zA-Z0-9_]+", content):
    print("Error: Unreplaced placeholders found in Kitty theme. Aborting update.", file=sys.stderr)
    sys.exit(1)

tmp_path = output_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(content)
os.rename(tmp_path, output_path)
' "$STATE_DIR/user/generated/material_colors.scss" "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR/user/generated/terminal/kitty-theme.conf"

  # Ensure current-theme.conf is a symlink to our generated kitty-theme.conf
  local kitty_theme_dir="$XDG_CONFIG_HOME/kitty"
  local kitty_theme_file="$kitty_theme_dir/current-theme.conf"
  local gen_kitty_theme="$STATE_DIR/user/generated/terminal/kitty-theme.conf"
  if [ -d "$kitty_theme_dir" ]; then
    if [ ! -L "$kitty_theme_file" ] || [ "$(readlink -f "$kitty_theme_file")" != "$gen_kitty_theme" ]; then
      echo "Restoring Kitty current-theme.conf symlink to dynamic theme..."
      rm -f "$kitty_theme_file"
      ln -sf "$gen_kitty_theme" "$kitty_theme_file"
    fi
  fi

  # Reload
  if ! pgrep -f kitty >/dev/null; then
    return
  fi
  kill -SIGUSR1 $(pidof kitty)
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  # Apply colors using Python for robust literal string replacement (no regex or sed shell escaping issues)
  python3 -c '
import sys
import os
scss_path, template_path, output_path, alpha = sys.argv[1:5]
vars_dict = {}
try:
    with open(scss_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith("$") or ":" not in line:
                continue
            name, val = line.split(":", 1)
            name = name.strip()
            val = val.strip().rstrip(";").lstrip("#")
            vars_dict[name + " #"] = val
except Exception as e:
    print(f"Error reading colors scss: {e}", file=sys.stderr)
    sys.exit(1)

if len(vars_dict) < 10:
    print("Error: Too few colors generated. Aborting sequences update.", file=sys.stderr)
    sys.exit(1)

with open(template_path, "r") as f:
    content = f.read()

for name, val in vars_dict.items():
    content = content.replace(name, val)

content = content.replace("$alpha", alpha)

import re
if re.search(r"#\$[a-zA-Z0-9_]+", content):
    print("Error: Unreplaced placeholders found in Terminal sequences. Aborting update.", file=sys.stderr)
    sys.exit(1)

tmp_path = output_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(content)
os.rename(tmp_path, output_path)
' "$STATE_DIR/user/generated/material_colors.scss" "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR/user/generated/terminal/sequences.txt" "$term_alpha"

  for file in /dev/pts/*; do
    if [[ $file =~ ^/dev/pts/[0-9]+$ ]]; then
      {
      cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file"
      } & disown || true
    fi
  done
}

apply_term() {
  apply_anyterm &
  apply_kitty &
}

apply_openrgb() {
    python "$CONFIG_DIR/scripts/colors/openRGB/apply_openrgb.py"
}

# Check if terminal theming is enabled in config
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
if [ -f "$CONFIG_FILE" ]; then
  enable_terminal=$(jq -r '.appearance.wallpaperTheming.enableTerminal' "$CONFIG_FILE")
  enable_openrgb=$(jq -r '.appearance.openrgb.enable' "$CONFIG_FILE")
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
  if [ "$enable_openrgb" = "true" ]; then
    openrgb_duration=$(jq -r '.appearance.openrgb.fadeDuration' "$CONFIG_FILE")
    python "$CONFIG_DIR/scripts/colors/openRGB/apply_openrgb.py" -d $openrgb_duration
  fi
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

# apply_qt & # Qt theming is already handled by kde-material-colors
