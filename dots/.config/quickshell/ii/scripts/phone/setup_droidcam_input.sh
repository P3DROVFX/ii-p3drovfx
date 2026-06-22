#!/usr/bin/env bash
# setup_droidcam_input.sh — Creates a virtual null-sink for routing the DroidCam
# audio stream as a microphone source in PulseAudio/PipeWire.
#
# Why: droidcam-cli (in audio mode) writes PCM to the default sink. To use it
# as a *microphone* (source), we create a null-sink named "DroidCam-Mic" whose
# `.monitor` source becomes an available input device for system apps.
#
# Output: prints the monitor source name on stdout (e.g. "alsa_output.DroidCam-Mic.monitor")
#         so the QML service can use it with `pactl set-source-*` commands.
# Exit codes: 0 on success (sink already existed or was created), 1 on failure.

set -u

SINK_NAME="DroidCam-Mic"
SINK_DESC="DroidCam Microphone"

if ! command -v pactl >/dev/null 2>&1; then
    echo "pactl not installed" >&2
    exit 1
fi

# Check if the null-sink is already loaded (idempotent).
existing="$(pactl list short sinks 2>/dev/null | awk -v sink="$SINK_NAME" '$2 == sink {print $1; exit}' || true)"
if [ -n "$existing" ]; then
    # Already loaded — emit the monitor source name.
    monitor_name=""
    # PulseAudio convention: <driver>.<sink_name>.monitor
    monitor_name="$(pactl list short sources 2>/dev/null | awk -v sink="$SINK_NAME" -v monitor="$SINK_NAME.monitor" '$2 == monitor {print $2; exit}')"
    if [ -z "$monitor_name" ]; then
        # Fallback: search by description match
        monitor_name="$(pactl list sources 2>/dev/null | awk -v desc="$SINK_DESC" '
            /Name:/ { name=$2 }
            /Description:/ && $0 ~ desc { print name; exit }
        ')"
    fi
    if [ -n "$monitor_name" ]; then
        echo "$monitor_name"
        exit 0
    fi
    # Fall through to recreate if monitor not found.
fi

# Load module-null-sink with the DroidCam name and description.
pactl load-module module-null-sink \
    sink_name="$SINK_NAME" \
    sink_properties="device.description='$SINK_DESC'" \
    >/dev/null 2>&1 || {
        echo "Failed to load module-null-sink" >&2
        exit 1
    }

# The monitor source follows the naming convention:
#   <server_type>.<sink_name>.monitor
# PipeWire (most common now): "alsa_output.DroidCam-Mic.monitor"
# PulseAudio: same convention.
MONITOR="alsa_output.${SINK_NAME}.monitor"
found="$(pactl list short sources 2>/dev/null | awk -v m="$MONITOR" '$2 == m {print $2; exit}')"

if [ -z "$found" ]; then
    # Try alternate naming: just <sink_name>.monitor
    MONITOR="${SINK_NAME}.monitor"
    found="$(pactl list short sources 2>/dev/null | awk -v m="$MONITOR" '$2 == m {print $2; exit}')"
fi

if [ -z "$found" ]; then
    # Last resort: search by description.
    found="$(pactl list sources 2>/dev/null | awk -v desc="$SINK_DESC" '
        /Name:/ { name=$2 }
        /Description:/ && $0 ~ desc { print name; exit }
    ')"
fi

if [ -z "$found" ]; then
    echo "Could not find monitor source after loading null-sink" >&2
    exit 1
fi

echo "$found"
exit 0
