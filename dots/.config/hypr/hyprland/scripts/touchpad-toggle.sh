#!/usr/bin/env bash
# Turns every touchpad on or off for the XF86TouchpadToggle/On/Off keys, and shows the
# change as an on/off pill in ii's OSD.
# Usage: touchpad-toggle.sh [toggle|on|off]
#
# Most laptops send the toggle key as F21 (systemd's hwdb maps touchpad-toggle scancodes
# to it), which xkb calls XF86TouchpadToggle; some hold Ctrl+Super with it, so the binds
# ignore modifiers.
# Hyprland's Lua config rejects `hyprctl keyword`, so devices are switched at runtime
# through `hyprctl repl` + hl.device{}. Hyprland doesn't report whether a device is
# enabled either, so the last state set here is kept in a marker tagged with the
# compositor instance: a new session starts with the touchpad on, and a leftover marker
# must not invert the toggle. (`hyprctl reload` also re-enables it; the next press then
# just clears the marker.)
set -u
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-touchpad-disabled"
SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"

pill() { qs -c "${qsConfig:-ii}" ipc call osd pill "$@" >/dev/null 2>&1; }

mapfile -t touchpads < <(hyprctl devices -j |
    jq -r '.mice[].name | select(test("touchpad|trackpad|glidepoint"; "i"))')
[[ ${#touchpads[@]} -gt 0 ]] || exit 0

set_enabled() {
    local lua="" dev
    for dev in "${touchpads[@]}"; do
        lua+="hl.device{ name='$dev', enabled=$1 } "
    done
    [[ $(hyprctl repl "${lua}return 'ok'" 2>/dev/null) == ok ]]
}

case "${1:-toggle}" in
    on) enable=true ;;
    off) enable=false ;;
    *) [[ -e $STATE && $(<"$STATE") == "$SIG" ]] && enable=true || enable=false ;;
esac

if [[ $enable == true ]]; then
    set_enabled true && rm -f "$STATE" && pill touch_app "Touchpad enabled" on
else
    set_enabled false && printf '%s\n' "$SIG" > "$STATE" && pill do_not_touch "Touchpad disabled" off
fi
