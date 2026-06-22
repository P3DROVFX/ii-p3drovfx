#!/usr/bin/env bash
# droidcam_status.sh — Emits JSON state of DroidCam installation and active devices.
# Called from PhoneCameraService / PhoneMicService on demand.
#
# Output shape:
# {
#   "installed": true|false,
#   "v4l2_device": "/dev/videoN" or "",
#   "audio_source": "alsa_output.droidcam_input.monitor" or "",
#   "audio_running": true|false,
#   "video_running": true|false
# }
#
# This script is READ-ONLY — it never starts/stops anything.

set -u
IFS=$'\n\t'

installed=false
v4l2_device=""
audio_source=""
audio_running=false
video_running=false

if command -v droidcam-cli >/dev/null 2>&1; then
    installed=true
fi

# Detect /dev/videoN associated with DroidCam (v4l2loopback).
# `v4l2-ctl --list-devices` output looks like:
#   DroidCam (usb-0000:00:14.0-...):
#       /dev/video10
#       /dev/video11
# We pick the first /dev/videoN that appears under a DroidCam-named block.
if command -v v4l2-ctl >/dev/null 2>&1; then
    list_output="$(v4l2-ctl --list-devices 2>/dev/null || true)"
    if [ -n "$list_output" ]; then
        in_droidcam_block=false
        for line in $list_output; do
            if echo "$line" | grep -qi "droidcam"; then
                in_droidcam_block=true
                continue
            fi
            if $in_droidcam_block; then
                if echo "$line" | grep -qE '^\s*/dev/video[0-9]+'; then
                    v4l2_device="$(echo "$line" | awk '{print $1}')"
                    break
                else
                    # Block ended (a new device name line appeared).
                    in_droidcam_block=false
                fi
            fi
        done
    fi
fi

# Detect if droidcam-cli process is running (covers both video and audio modes).
# We look for any droidcam-cli process; the QML service distinguishes by tracking its own PID.
if pgrep -f 'droidcam-cli' >/dev/null 2>&1; then
    video_running=true
fi

# Detect virtual null-sink created for DroidCam mic routing (PipeWire/PulseAudio).
# A null-sink named "DroidCam-Mic" will expose a ".monitor" source.
if command -v pactl >/dev/null 2>&1; then
    sources_output="$(pactl list sources short 2>/dev/null || true)"
    if [ -n "$sources_output" ]; then
        match="$(echo "$sources_output" | awk '$0 ~ /DroidCam-Mic/ || $0 ~ /droidcam/ {print $1; exit}')"
        if [ -n "$match" ]; then
            audio_source="$match"
        fi
        if echo "$sources_output" | grep -qi 'droidcam'; then
            audio_running=true
        fi
    fi
fi

# Emit JSON. printf to avoid echo interpreting backslashes.
printf '{"installed":%s,"v4l2_device":%s,"audio_source":%s,"audio_running":%s,"video_running":%s}\n' \
    "$( $installed && echo true || echo false )" \
    "\"$v4l2_device\"" \
    "\"$audio_source\"" \
    "$( $audio_running && echo true || echo false )" \
    "$( $video_running && echo true || echo false )"
