#!/usr/bin/env bash
# teardown_droidcam_input.sh — Unloads the virtual null-sink created by
# setup_droidcam_input.sh, cleaning up audio routing after DroidCam stops.
#
# Idempotent: does nothing if the null-sink isn't loaded.
# Exit codes: 0 on success or no-op.

set -u

SINK_NAME="DroidCam-Mic"

if ! command -v pactl >/dev/null 2>&1; then
    exit 0
fi

# Find the module ID of the null-sink with our name and unload it.
# `pactl list short modules` is the safest cross-server (PA/PW) way.
module_id="$(pactl list short modules 2>/dev/null | awk -v sink="$SINK_NAME" '
    $0 ~ "sink_name="sink { print $1; exit }
' || true)"

if [ -n "$module_id" ]; then
    pactl unload-module "$module_id" >/dev/null 2>&1 || true
fi

exit 0
