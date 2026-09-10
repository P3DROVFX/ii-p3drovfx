#!/bin/bash

STATE_FILE="$HOME/.local/state/quickshell/user/generated/screenshare/apps.txt"
LOCK_FILE="${STATE_FILE}.lock"
BEAT_FILE="${STATE_FILE}.beat"
mkdir -p "$(dirname "$STATE_FILE")"

# Single producer per machine, since 2026-09-10 (RAM audit follow-up).
#
# ScreenShareIndicator ran one copy of this loop per widget instance — per bar
# section, per monitor, and surviving every hot-reload or kill -9: the
# 2026-09-08 audit measured eight coexisting producers, each running
# `pw-dump | jq` every 1.5 s, plus unkillable orphans reparented to init.
#
# Rules, enforced here rather than trusted to any launcher:
#   1. flock on LOCK_FILE, held for the loop's whole life. LOCK_FILE is never
#      written: contenders used to truncate a shared beat/lock file with their
#      own `exec 9>` before reading it, erasing the holder's heartbeat and
#      turning every would-be fast exit into a full lock wait.
#   2. The holder beats `pid + unix-time` into BEAT_FILE (atomic tmp+rename,
#      so readers only ever see a complete line). A contender whose flock is
#      blocked reads the beat: alive holder -> exit quietly; dead holder ->
#      bounded `flock -w 5` takeover.
#   3. Orphan guard: if this shell's parent pid changes, the owning Quickshell
#      died (we were reparented to init). Exit instead of polluting forever.

exec 9>"$LOCK_FILE"

beat() {
    printf '%s %s\n' "$$" "$(date +%s)" > "${BEAT_FILE}.tmp" 2>/dev/null
    mv -f "${BEAT_FILE}.tmp" "$BEAT_FILE" 2>/dev/null
}

if ! flock -n 9; then
    read -r holder_pid holder_beat < "$BEAT_FILE" 2>/dev/null
    now=$(date +%s)
    if [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null \
        && [ $(( now - ${holder_beat:-0} )) -lt 6 ]; then
        exit 0    # a live producer is already beating
    fi
    flock -w 5 9 || exit 0    # holder died; take over (bounded, never hang)
fi

ORIG_PPID=$(awk '{print $4}' /proc/self/stat)
beat

LAST_STATE=""

while true; do

    apps=$(pw-dump 2>/dev/null | jq -r '.[] | select((.info.props."media.class" == "Stream/Input/Video" or .info.props."media.role" == "Screen") and .info.state == "running") | (.info.props["application.name"] // .info.props["node.description"] // .info.props["node.name"]) | select(. != null and . != "")' | sort -u | paste -sd ", " -)

    CURRENT_STATE="${apps:-NONE}"
    if [ -z "$CURRENT_STATE" ]; then
        CURRENT_STATE="NONE"
    fi

    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        echo "$CURRENT_STATE" > "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"

        LAST_STATE="$CURRENT_STATE"
    fi

    # Orphan guard: parent changed means the shell that owned us died.
    [ "$(awk '{print $4}' /proc/self/stat)" != "$ORIG_PPID" ] && exit 0
    beat
    sleep 1.5
done
