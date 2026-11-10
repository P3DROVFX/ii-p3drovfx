#!/usr/bin/env bash
# Plays one stream on several sinks at once with PipeWire's combine-stream
# module, run in its own `pipewire -c` process so it outlives shell restarts.
#
# Not pipewire-pulse's module-combine-sink: it gives no way to set properties
# on the per-device streams, and EasyEffects (processing all outputs) grabs
# them into its own sink, closing a loop that silences every device. The
# streams here carry node.dont-move, which EasyEffects and WirePlumber leave
# alone. Rules match sinks by node.name, so a Bluetooth sink that drops and
# reconnects is relinked instead of falling out of the group.
#
#   multi-output.sh status            prints the combined sink names, one per line
#   multi-output.sh set NAME [NAME…]  2+ names: (re)create the combined sink and
#                                     make it default; 1 name: tear down and make
#                                     that sink default; 0 names: tear down

set -u
COMBINED=ii_multi_output
STATE="${XDG_RUNTIME_DIR:-/tmp}/ii-multi-output"
CONF="$STATE/combine.conf"
PIDFILE="$STATE/pid"
SINKS="$STATE/sinks"

running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

status() {
    running && [ -f "$SINKS" ] && cat "$SINKS"
}

sink_exists() {
    pactl list short sinks | cut -f2 | grep -qx "$1"
}

teardown() {
    if running; then
        kill "$(cat "$PIDFILE")"
        for _ in $(seq 30); do
            sink_exists "$COMBINED" || break
            sleep 0.1
        done
    fi
    rm -f "$PIDFILE" "$SINKS"
    # Leftover from the module-combine-sink version of this script
    pactl list short modules | awk -F'\t' -v s="sink_name=$COMBINED" \
        '$2 == "module-combine-sink" && index($3, s) { print $1 }' \
        | while read -r id; do pactl unload-module "$id"; done
}

write_conf() {
    local matches="" name
    for name in "$@"; do
        matches+="                    { media.class = \"Audio/Sink\" node.name = \"$name\" }"$'\n'
    done
    cat > "$CONF" <<EOF
context.properties = { log.level = 1 }
context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}
context.modules = [
    { name = libpipewire-module-rt flags = [ ifexists nofail ] }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-combine-stream
        args = {
            combine.mode = sink
            node.name = "$COMBINED"
            node.description = "Multi-output"
            combine.latency-compensate = true
            combine.props = { audio.position = [ FL FR ] }
            stream.props = { node.dont-move = true }
            stream.rules = [
                {   matches = [
$matches                    ]
                    actions = { create-stream = { } }
                }
            ]
        }
    }
]
EOF
}

case "${1:-status}" in
    status)
        status
        ;;
    set)
        shift
        mkdir -p "$STATE"
        teardown
        if [ "$#" -ge 2 ]; then
            write_conf "$@"
            setsid pipewire -c "$CONF" >/dev/null 2>&1 < /dev/null &
            echo $! > "$PIDFILE"
            printf '%s\n' "$@" > "$SINKS"
            # The sink shows up a moment after the process starts, and
            # set-default-sink on a missing sink is silently ignored.
            for _ in $(seq 50); do
                pactl set-default-sink "$COMBINED" 2>/dev/null
                [ "$(pactl get-default-sink)" = "$COMBINED" ] && break
                sleep 0.1
            done
        elif [ "$#" -eq 1 ]; then
            pactl set-default-sink "$1"
        fi
        status
        ;;
esac
