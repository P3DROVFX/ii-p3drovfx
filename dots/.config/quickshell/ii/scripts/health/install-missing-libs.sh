#!/usr/bin/env bash
# install-missing-libs.sh — find which packages provide libraries a program misses,
# and install them after asking. System Health opens it in a terminal for prebuilt
# packages (rebuilding those would only download the same files again).
#
# Usage: install-missing-libs.sh <library>...    e.g. libgtk4-layer-shell.so.0
#
# pacman's file list is not synced by default, so it is synced first (sudo). A
# library no repository package provides was usually replaced by a newer version:
# then the program needs an update from its packager, or a rebuild if it has one.

set -u
(($# > 0)) || { echo "No library given."; exit 2; }

echo "Looking up which packages provide: $*"
echo
sudo pacman -Fy || { echo "Could not sync pacman's file list."; exit 1; }
echo

pkgs=()
for lib in "$@"; do
    # -q prints "repo/package"; the first repository wins, as pacman's own order.
    provider="$(pacman -Fq "$lib" 2>/dev/null | head -1)"
    if [[ -n "$provider" ]]; then
        pkgs+=("${provider#*/}")
        printf '  %-32s ← %s\n' "$lib" "${provider#*/}"
    else
        printf '  %-32s ← no package provides it: a newer version probably replaced it\n' "$lib"
    fi
done
echo

if ((${#pkgs[@]} == 0)); then
    echo "Nothing to install. Update the program that needs these, or rebuild it if it builds from source."
    exit 1
fi
mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | sort -u)
read -rp "Install ${pkgs[*]}? [Y/n] " answer
[[ "$answer" =~ ^[Nn] ]] && exit 0
sudo pacman -S --needed "${pkgs[@]}" && echo && echo "Done. System Health checks again on its own now."
