#!/usr/bin/env bash
# Point every copy of the icon theme setting at one theme, and tell running apps to re-read it.
#
# There are five copies of this setting and they have to move together: gsettings for GNOME and
# GTK, kdeglobals for Qt and KDE apps - this shell included - the GTK 3 and GTK 4 inis, and
# XSETTINGS for X11 apps. Leaving one behind is not a partial success: the next time anything
# asks the icon loader to reload, it reads kdeglobals, and the whole desktop silently reverts to
# whatever that one still says. That is why this is one script with one caller-supplied name,
# rather than a write in each place that happens to need one.
#
# Usage: apply_icon_theme.sh <theme-name>

set -u

pack="${1:-}"
[ -n "$pack" ] || { echo "apply_icon_theme.sh: no theme name given" >&2; exit 1; }

gsettings set org.gnome.desktop.interface icon-theme "$pack" 2>/dev/null || true

if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "$pack"
fi

set_ini() {
    file="$1"
    mkdir -p "${file%/*}"
    [ -f "$file" ] || printf '[Settings]\n' > "$file"
    grep -v '^gtk-icon-theme-name=' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    printf 'gtk-icon-theme-name=%s\n' "$pack" >> "$file"
}

conf="${XDG_CONFIG_HOME:-$HOME/.config}"
set_ini "$conf/gtk-3.0/settings.ini"
set_ini "$conf/gtk-4.0/settings.ini"

if command -v xsettingsd >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    xconf="$conf/xsettingsd/xsettingsd.conf"
    mkdir -p "${xconf%/*}"
    touch "$xconf"
    grep -v '^Net/IconThemeName ' "$xconf" > "$xconf.tmp" && mv "$xconf.tmp" "$xconf"
    printf 'Net/IconThemeName "%s"\n' "$pack" >> "$xconf"
    if pgrep -x xsettingsd >/dev/null 2>&1; then
        pkill -HUP -x xsettingsd || true
    else
        setsid -f xsettingsd >/dev/null 2>&1 || true
    fi
fi

# Twice, with a gap. KIconLoader answers this signal by reading the theme name and then
# rebuilding the theme it names, in that order, so the first refresh hands Qt the name from
# before this change and every icon comes out one theme behind. The second refresh, once the
# rebuild has happened, is the one that lands the new theme. The group argument is ignored -
# each signal rebuilds all of them - so this is two refreshes, not the fourteen it once sent.
for _ in 1 2; do
    dbus-send --session --type=signal /KIconLoader \
        org.kde.KIconLoader.iconChanged int32:0 2>/dev/null || true
    sleep 0.4
done
