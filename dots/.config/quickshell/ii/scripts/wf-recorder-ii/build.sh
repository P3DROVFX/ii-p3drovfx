#!/usr/bin/env bash
# Builds ii-wf-recorder: wf-recorder with the patches in ./patches (README.md), installed
# for this user only, beside the distribution's wf-recorder (which it never replaces):
#   ${XDG_DATA_HOME:-~/.local/share}/ii-wf-recorder/bin/ii-wf-recorder
# where ii link's second screen looks for it. On NixOS the flake's package puts it on PATH.
#
#   build.sh [install|status|remove]
#
# Needs git, meson, ninja, a C++ compiler, and the dev files of wayland, wayland-protocols,
# FFmpeg (libavcodec, libavformat, libavfilter, libavutil, libswresample), libdrm and gbm
# (Arch: meson ninja wayland-protocols ffmpeg mesa; Fedora: meson ninja-build
# wayland-devel wayland-protocols-devel ffmpeg-free-devel libdrm-devel mesa-libgbm-devel).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=/dev/null
. "$here/revision"
dest="${XDG_DATA_HOME:-$HOME/.local/share}/ii-wf-recorder"
bin="$dest/bin/ii-wf-recorder"

case "${1:-install}" in
status)
    if [[ -x "$bin" ]]; then
        echo "installed: $bin ($(cat "$dest/.revision" 2>/dev/null || echo unknown))"
        [[ "$(cat "$dest/.revision" 2>/dev/null)" == "$WFR_COMMIT $(cat "$here"/patches/*.patch | sha256sum | cut -c1-16)" ]] || echo "outdated: run build.sh install"
    else
        echo "not installed"
    fi
    exit 0 ;;
remove)
    rm -rf "$dest"
    echo "removed $dest"
    exit 0 ;;
install) ;;
*) echo "usage: build.sh [install|status|remove]" >&2; exit 2 ;;
esac

for t in git meson ninja; do
    command -v "$t" >/dev/null || { echo "build.sh: $t is not installed" >&2; exit 1; }
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q src
git -C "$work/src" fetch -q --depth 1 https://github.com/ammen99/wf-recorder "$WFR_COMMIT"
git -C "$work/src" checkout -q FETCH_HEAD
git -C "$work/src" apply "$here"/patches/*.patch
# Audio is off: the second screen streams the PC's sound itself (screen.rs Audio).
log="$work/build.log"
meson setup "$work/build" "$work/src" --buildtype=release -Dpulse=disabled -Dpipewire=disabled >"$log" 2>&1 &&
    ninja -C "$work/build" >>"$log" 2>&1 || { rg -m5 -B2 -A3 "error:" "$log" >&2 || tail -n 30 "$log" >&2; echo "build.sh: build failed" >&2; exit 1; }
mkdir -p "$dest/bin"
install -m 755 "$work/build/wf-recorder" "$bin.new"
mv -f "$bin.new" "$bin"
echo "$WFR_COMMIT $(cat "$here"/patches/*.patch | sha256sum | cut -c1-16)" > "$dest/.revision"
echo "installed $bin"
