#!/usr/bin/env bash
# Installs or removes the ii-p3drovfx SDDM theme. Run as root (setup-ii-p3drovfx.sh sddm
# calls it through sudo). Everything it writes is listed here, and `remove` takes all of it back.
#
#   install.sh install <user> <state.json>   install/refresh, sync <user>'s lock look
#   install.sh remove [<user>]                uninstall
#
#   /usr/share/sddm/themes/ii-p3drovfx/          the theme (+ the shell's shapes library)
#   /usr/local/lib/ii-sddm/ii-sddm-sync          root half of the sync
#   /etc/systemd/system/ii-sddm-sync@.{path,service} (+ a drop-in per user)
#   /var/lib/ii-sddm/                            synced wallpaper, fonts, avatars, settings
#   /etc/sddm.conf.d/zz-ii-p3drovfx.conf         selects the theme
#   /etc/sddm.conf.d/zz-ii-p3drovfx-cursor.conf  the greeter cursor (written by the sync)
#   /usr/local/share/icons/<theme>/              only for a cursor theme found in a home dir
# The sync also sets the scale in /var/lib/sddm/.config/kwinoutputconfig.json (the greeter's
# KWin); that file belongs to SDDM and is left as is on removal.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
II_DIR="$(dirname "$HERE")"
THEME_ID="ii-p3drovfx"
THEME_DIR="/usr/share/sddm/themes/$THEME_ID"
LIB_DIR="/usr/local/lib/ii-sddm"
UNIT_DIR="/etc/systemd/system"
DATA_DIR="/var/lib/ii-sddm"
CONF="/etc/sddm.conf.d/zz-$THEME_ID.conf"
CURSOR_CONF="/etc/sddm.conf.d/zz-$THEME_ID-cursor.conf"
ICONS="/usr/local/share/icons"

die() { printf 'ii-sddm: %s\n' "$*" >&2; exit 1; }
say() { printf 'ii-sddm: %s\n' "$*"; }

[[ $EUID -eq 0 ]] || die "run as root"

valid_user() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && id -u "$1" >/dev/null 2>&1 || die "no such user: $1"
    [[ "$(id -u "$1")" -ne 0 ]] || die "refusing to install for root"
}

# Only ever delete a theme directory that is ours.
ours() { [[ -f "$THEME_DIR/metadata.desktop" ]] && grep -qx "Theme-Id=$THEME_ID" "$THEME_DIR/metadata.desktop"; }

install_theme() {
    local shapes="$II_DIR/modules/common/widgets/shapes"
    [[ -f "$HERE/theme/Main.qml" ]] || die "theme sources missing in $HERE/theme"
    [[ -f "$shapes/ShapeCanvas.qml" ]] || die "shapes library missing in $shapes (git submodule not checked out?)"
    if [[ -e "$THEME_DIR" ]] && ! ours; then
        die "$THEME_DIR exists and is not this theme; not touching it"
    fi
    local stage
    stage="$(mktemp -d "/usr/share/sddm/themes/.$THEME_ID.XXXXXX")"
    cp -r "$HERE/theme/." "$stage/"
    mkdir -p "$stage/components/shapes"
    (cd "$shapes" && find . -type f \( -name '*.js' -o -name 'ShapeCanvas.qml' -o -name LICENSE \) -print0 |
        xargs -0 cp --parents -t "$stage/components/shapes/")
    cp "$HERE/README.md" "$stage/README.md" 2>/dev/null || true
    ln -sfn "$DATA_DIR/theme.conf.user" "$stage/theme.conf.user"
    chown -R root:root "$stage"
    chmod -R u=rwX,go=rX "$stage"
    rm -rf "$THEME_DIR"
    mv "$stage" "$THEME_DIR"
    say "theme installed to $THEME_DIR"
}

install_sync() {
    local user="$1" state="$2"
    install -D -m 0755 -o root -g root "$HERE/ii-sddm-sync" "$LIB_DIR/ii-sddm-sync"
    install -m 0644 -o root -g root "$HERE/ii-sddm-sync@.service" "$UNIT_DIR/ii-sddm-sync@.service"
    install -m 0644 -o root -g root "$HERE/ii-sddm-sync@.path" "$UNIT_DIR/ii-sddm-sync@.path"
    install -d -m 0755 -o root -g root "$DATA_DIR" "$ICONS"
    # Where this user's shell stages its state (it follows their XDG_STATE_HOME).
    install -d -m 0755 "$UNIT_DIR/ii-sddm-sync@$user.path.d" "$UNIT_DIR/ii-sddm-sync@$user.service.d"
    printf '[Path]\nPathChanged=%s\n' "$state" >"$UNIT_DIR/ii-sddm-sync@$user.path.d/state.conf"
    printf '[Service]\nEnvironment="II_SDDM_STATE=%s"\n' "$state" >"$UNIT_DIR/ii-sddm-sync@$user.service.d/state.conf"
    systemctl daemon-reload
    systemctl enable --now "ii-sddm-sync@$user.path" >/dev/null
    say "sync enabled for $user (ii-sddm-sync@$user.path)"
}

select_theme() {
    install -d -m 0755 /etc/sddm.conf.d
    local env_line="GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1"
    # GreeterEnvironment is one key: setting it here would replace another file's value.
    # The battery chip is the only thing that needs it, so leave others' settings alone.
    local other
    other="$(grep -ls '^GreeterEnvironment=' /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null | grep -v "^$CONF\$" || true)"
    # Nothing to say when that file already carries the variable.
    if [[ -n "$other" ]] && grep -qs '^GreeterEnvironment=.*QML_XHR_ALLOW_FILE_READ=1' $other; then
        env_line="# GreeterEnvironment (with QML_XHR_ALLOW_FILE_READ=1) is set in: ${other//$'\n'/, }"
        other=""
    elif [[ -n "$other" ]]; then
        env_line="# GreeterEnvironment is set in: ${other//$'\n'/, } (add QML_XHR_ALLOW_FILE_READ=1 there for the battery chip)"
    fi
    printf '# Written by the ii-p3drovfx SDDM installer; removed by `install.sh remove`.\n[General]\n%s\n\n[Theme]\nCurrent=%s\n' \
        "$env_line" "$THEME_ID" >"$CONF"
    chmod 0644 "$CONF"
    say "SDDM theme set to $THEME_ID ($CONF)"
    [[ -n "$other" ]] && say "note: another file sets GreeterEnvironment; the battery chip stays hidden until it includes QML_XHR_ALLOW_FILE_READ=1"
    # The theme has no on-screen keyboard: Qt's own then opens in a window of
    # its own, takes focus from the password field and pops up again and again.
    local osk
    osk="$(grep -ls -e '^GreeterEnvironment=.*QT_IM_MODULE=qtvirtualkeyboard' -e '^InputMethod=qtvirtualkeyboard' \
        /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null || true)"
    [[ -n "$osk" ]] && say "warning: Qt's on-screen keyboard is on for the greeter and loops with this theme; remove QT_IM_MODULE=qtvirtualkeyboard (or InputMethod=qtvirtualkeyboard) from: ${osk//$'\n'/, }"
    return 0
}

do_install() {
    local user="$1" state="$2"
    valid_user "$user"
    local home
    home="$(getent passwd "$user" | cut -d: -f6)"
    [[ "$state" == "$home"/* && "$state" == *.json && "$state" != *..* && "$state" != *[[:space:]\"\\%]* ]] ||
        die "state file must be a .json under $home, without spaces, quotes or %"
    command -v sddm >/dev/null 2>&1 || die "SDDM is not installed"
    [[ -x /usr/bin/sddm-greeter-qt6 ]] || say "warning: no Qt 6 greeter (sddm-greeter-qt6); this theme needs it"
    install_theme
    install_sync "$user" "$state"
    select_theme
    systemctl start "ii-sddm-sync@$user.service" || say "first sync failed; see: journalctl -u ii-sddm-sync@$user.service"
}

do_remove() {
    local user="${1:-}"
    local unit
    for unit in $(systemctl list-units --all --plain --no-legend 'ii-sddm-sync@*.path' | awk '{print $1}'); do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
    done
    [[ -n "$user" ]] && systemctl disable --now "ii-sddm-sync@$user.path" >/dev/null 2>&1 || true
    rm -rf "$UNIT_DIR"/ii-sddm-sync@*.path.d "$UNIT_DIR"/ii-sddm-sync@*.service.d
    rm -f "$UNIT_DIR/ii-sddm-sync@.path" "$UNIT_DIR/ii-sddm-sync@.service"
    systemctl daemon-reload
    rm -rf "$LIB_DIR" "$DATA_DIR"
    rm -f "$CONF" "$CURSOR_CONF"
    if ours; then rm -rf "$THEME_DIR"; fi
    local dir
    for dir in "$ICONS"/*/; do
        [[ -f "$dir.ii-sddm-copy" ]] && rm -rf "$dir"
    done
    say "removed; SDDM falls back to whatever theme /etc/sddm.conf(.d) names"
}

case "${1:-}" in
    install) [[ $# -eq 3 ]] || die "usage: install.sh install <user> <state.json>"; do_install "$2" "$3" ;;
    remove) do_remove "${2:-}" ;;
    *) die "usage: install.sh install <user> <state.json> | remove [<user>]" ;;
esac
