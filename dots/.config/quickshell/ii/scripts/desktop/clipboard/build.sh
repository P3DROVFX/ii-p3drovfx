#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

xml=""
for p in \
    /usr/share/qt6/wayland/protocols/wlr-data-control/wlr-data-control-unstable-v1.xml \
    /usr/share/wlr-protocols/unstable/wlr-data-control/wlr-data-control-unstable-v1.xml \
    /usr/share/wayland-protocols/unstable/wlr-data-control/wlr-data-control-unstable-v1.xml; do
    [ -f "$p" ] && xml="$p" && break
done
[ -z "$xml" ] && { echo "wlr-data-control protocol xml not found"; exit 1; }

wayland-scanner client-header "$xml" wlr-data-control-unstable-v1-client-protocol.h
wayland-scanner private-code "$xml" wlr-data-control-unstable-v1-protocol.c
gcc -O2 -Wall -o fileclip fileclip.c wlr-data-control-unstable-v1-protocol.c -lwayland-client
echo "built fileclip ($xml)"
