#!/usr/bin/env bash
# install-hook.sh — install or remove the pacman hook that warns, during the
# update itself, when Quickshell needs a rebuild for a new Qt.
#
# The hook runs as root, so its script is copied to /usr/local/lib/ii and owned by
# root: pacman never runs anything from the home directory, which the user can
# write to.
#
# Usage (install and remove run as root, through sudo or pkexec):
#   install-hook.sh install
#   install-hook.sh remove
#   install-hook.sh status    prints "installed", "outdated", "missing" or "unsupported"
set -euo pipefail

src="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
HOOK=/etc/pacman.d/hooks/ii-quickshell-qt.hook
CHECK=/usr/local/lib/ii/quickshell-qt-check

die() {
    printf 'install-hook: %s\n' "$1" >&2
    exit "${2:-1}"
}

need_root() {
    ((EUID == 0)) || die "run as root (sudo or pkexec)" 2
    command -v pacman >/dev/null 2>&1 || die "pacman is not installed" 3
}

case "${1:-}" in
install)
    need_root
    install -Dm644 -o root -g root "$src/ii-quickshell-qt.hook" "$HOOK"
    install -Dm755 -o root -g root "$src/quickshell-qt-check.sh" "$CHECK"
    ;;
remove)
    need_root
    rm -f "$HOOK" "$CHECK"
    rmdir /usr/local/lib/ii 2>/dev/null || true
    ;;
status)
    if ! command -v pacman >/dev/null 2>&1; then
        echo unsupported
    elif [[ ! -f "$HOOK" || ! -f "$CHECK" ]]; then
        echo missing
    elif cmp -s "$src/ii-quickshell-qt.hook" "$HOOK" && cmp -s "$src/quickshell-qt-check.sh" "$CHECK"; then
        echo installed
    else
        echo outdated
    fi
    ;;
*)
    die "usage: install-hook.sh install|remove|status" 2
    ;;
esac
