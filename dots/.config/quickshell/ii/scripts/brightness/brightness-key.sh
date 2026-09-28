#!/usr/bin/env bash
# brightness-key.sh up|down [step%]: the default XF86MonBrightnessUp/Down binds.
#
# The backlight is written with brightnessctl directly, so the keys keep working while the
# shell reloads or is not running at all. The shell watches the backlight and draws the OSD
# on its own; the press is reported to it (`ipc call brightness keyPressed`) so that, with
# osd.brightnessKeysOnly on, a key can be told apart from an ambient-light daemon.
#
# Only on the backlight's floor does the key go through the shell: there "dim below minimum"
# (light.gamma.dimBelowMinimum) walks gamma down, and back up before the backlight moves
# again. If the shell does not answer, brightnessctl runs anyway.
set -u

dir=${1-}
step=${2:-5}
case $dir in
    up) op=increment sign=+ ;;
    down) op=decrement sign=- ;;
    *) echo "usage: brightness-key.sh up|down [step%]" >&2; exit 2 ;;
esac

config=${qsConfig:-ii}
ipc() { timeout 1 qs -c "$config" ipc call brightness "$1" >/dev/null 2>&1; }

# brightnessctl never writes below 1 (its --min-value default), so 1 is the floor.
current=$(brightnessctl --class backlight get 2>/dev/null) || current=
if [[ $current =~ ^[0-9]+$ ]] && ((current <= 1)) && ipc "$op"; then
    exit 0
fi

ipc keyPressed &
brightnessctl --class backlight --quiet set "$step%$sign"
