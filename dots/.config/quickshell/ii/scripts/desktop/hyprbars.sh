#!/usr/bin/env bash
# usage: hyprbars.sh load|style|font|reload|disable|unload [font] [glyphs|semaphore] [mac|themed]

set -uo pipefail

GENERATED="$HOME/.local/state/quickshell/ii/user/generated"
COLORS="$GENERATED/colors.json"
FONTFILE="$GENERATED/hyprbars-font.txt"
DEFAULT_BAR_COLOR=2285056819
TRANSPARENT='rgba(00000000)'
FG=
FONT="${2:-}"
STYLE="${3:-semaphore}"
BTNCOL="${4:-themed}"
BAR_HEIGHT="${5:-34}"
SIZE=15

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/akebono-hyprbars.lock"
flock 9

so_path() {
    [ -f "$HOME/.local/share/hyprbars/hyprbars.so" ] && { echo "$HOME/.local/share/hyprbars/hyprbars.so"; return; }
    find "$HOME/.local/share/hyprpm" "/var/cache/hyprpm/$USER" -name 'hyprbars.so' 2>/dev/null | head -1
}
loaded()  { hyprctl plugins list 2>/dev/null | grep -qiF hyprbars; }

col() {
    local hex
    hex="$(jq -r --arg k "$1" '.[$k] // empty' "$COLORS" 2>/dev/null)"
    [ -z "$hex" ] && hex="$2"
    printf 'rgb(%s)' "${hex#\#}"
}

MINSCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/minimize-active.sh"

add_btn() {
    local action="hyprctl dispatch \"$3\""
    [ -n "${4:-}" ] && action="$4"
    hyprctl eval "hl.plugin.hyprbars.add_button({ bg_color = '$1', fg_color = '$FG', size = $SIZE, icon = '$2', action = [[$action]] })" >/dev/null
}

style() {
    loaded || return 0
    local bar text fontfile fontarg
    bar="$(col surface 131313)"; FG="$bar"
    text="$(col on_surface e2e2e2)"
    fontfile="$(cat "$FONTFILE" 2>/dev/null || true)"
    fontarg="bar_text_font = '${fontfile}'"
    [ -z "$fontfile" ] && fontarg=""
    hyprctl eval "hl.config({ plugin = { hyprbars = { enabled = true, bar_color = '$bar', bar_height = ${BAR_HEIGHT:-34}, bar_blur = false, bar_padding = 14, bar_button_padding = 8, bar_buttons_alignment = 'right', bar_text_align = 'center', bar_text_size = 16, bar_part_of_window = true, bar_precedence_over_border = true${fontarg:+, ${fontarg}}, col = { text = '${text}' } } } })" >/dev/null

    local ec tc pc
    if [ "$BTNCOL" = mac ]; then
        ec='rgb(ff5f57)'; tc='rgb(febc2e)'; pc='rgb(28c840)'
    else
        ec="$(col error ffb4ab)"; tc="$(col tertiary ffb787)"; pc="$(col primary ffb0cb)"
    fi
    if [ "$STYLE" = glyphs ]; then
        SIZE=28
        FG="$ec"; add_btn "$TRANSPARENT" '󰖭' "hl.dsp.window.close()"
        FG="$pc"; add_btn "$TRANSPARENT" '󰖯' "hl.dsp.window.float({ action = 'toggle' })"
        FG="$tc"; add_btn "$TRANSPARENT" '󰖰' "" "bash \"$MINSCRIPT\""
    else
        add_btn "$ec" '' "hl.dsp.window.close()"
        add_btn "$pc" '' "hl.dsp.window.float({ action = 'toggle' })"
        add_btn "$tc" '' "" "bash \"$MINSCRIPT\""
    fi
}

restyle() {
    [ "$(hyprctl -j getoption plugin:hyprbars:bar_color 2>/dev/null | jq -r '.int // empty')" = "$DEFAULT_BAR_COLOR" ] || return 0
    style
}

write_font() {
    [ -n "$FONT" ] || return 1
    [ "$(cat "$FONTFILE" 2>/dev/null)" = "$FONT" ] && return 1
    mkdir -p "$GENERATED"
    printf '%s\n' "$FONT" >"$FONTFILE"
}

case "${1:-}" in
    load)
        if ! loaded; then
            so="$(so_path)"
            [ -z "$so" ] && { echo "hyprbars.so not found; run: sudo hyprpm add https://github.com/hyprwm/hyprland-plugins" >&2; exit 1; }
            write_font
            hyprctl plugin load "$so" >/dev/null
            hyprctl reload >/dev/null
        elif write_font; then
            hyprctl reload >/dev/null
        else
            hyprctl eval "hl.config({ plugin = { hyprbars = { enabled = true } } })" >/dev/null
            restyle
        fi
        ;;
    style)
        style ;;
    restyle)
        restyle ;;
    font)
        loaded && write_font && hyprctl reload >/dev/null ;;
    disable)
        loaded && hyprctl eval "hl.config({ plugin = { hyprbars = { enabled = false } } })" >/dev/null
        ;;
    reload)
        loaded && hyprctl reload >/dev/null
        ;;
    unload)
        so="$(so_path)"
        [ -n "$so" ] && hyprctl plugin unload "$so" >/dev/null 2>&1
        ;;
    *)
        echo "usage: ${0##*/} load|style|restyle|font|reload|disable|unload [font] [glyphs|semaphore] [mac|themed] [bar-height]" >&2; exit 2 ;;
esac