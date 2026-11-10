#!/usr/bin/env bash
# Tracked command for Modes & Routines (shell action with "Report result").
#
#   run_task.sh start  <dir> <command>   run <command> with `sh -c`, detached
#   run_task.sh status <dir>...          one JSON line per dir, for the shell
#   run_task.sh stop   <dir>             end a running command (its process group)
#
# A run directory holds:
#   command     the command line
#   boot        boot id at start, so a run cut by a power-off reads as lost
#   pid         pid of the wrapper
#   started     epoch ms
#   output.log  stdout + stderr
#   exit        exit status, written last (its presence means "finished")
#   ended       epoch ms
#
# The command may print `::ii-report {json}` lines; the last one is the
# result the shell shows: {status: ok|warn|error, title, summary,
# details: [{label, value, status}], notes: [..]}.
set -u

now_ms() { date +%s%3N; }
boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown; }

json_str() {
    # JSON string literal of $1 (no jq dependency).
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

case "${1:-}" in
start)
    dir="$2"
    cmd="$3"
    mkdir -p "$dir" || exit 1
    printf '%s' "$cmd" > "$dir/command"
    boot_id > "$dir/boot"
    now_ms > "$dir/started"
    # New session: survives a shell reload and does not get its SIGHUP.
    setsid bash -c '
        dir="$1"; cmd="$2"
        echo $$ > "$dir/pid"
        # Caught, not ignored: the command still gets the default TERM, and
        # this wrapper lives on to record how it ended.
        trap "" HUP
        trap ":" TERM
        sh -c "$cmd" > "$dir/output.log" 2>&1 < /dev/null
        code=$?
        date +%s%3N > "$dir/ended"
        echo "$code" > "$dir/exit.tmp" && mv "$dir/exit.tmp" "$dir/exit"
    ' _ "$dir" "$cmd" > /dev/null 2>&1 < /dev/null &
    disown
    ;;
status)
    shift
    current_boot="$(boot_id)"
    for dir in "$@"; do
        state=running
        code=null
        ended=0
        report=null
        if [[ -f "$dir/exit" ]]; then
            state=done
            code="$(cat "$dir/exit")"
            ended="$(cat "$dir/ended" 2>/dev/null || echo 0)"
        elif [[ ! -d "$dir" ]]; then
            state=lost
        else
            pid="$(cat "$dir/pid" 2>/dev/null || echo)"
            boot="$(cat "$dir/boot" 2>/dev/null || echo)"
            if [[ "$boot" != "$current_boot" ]] || [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                # No pid yet only right after start; give it a few seconds.
                started="$(cat "$dir/started" 2>/dev/null || echo 0)"
                if [[ "$boot" != "$current_boot" ]] || [[ -n "$pid" ]] || (( $(now_ms) - started > 10000 )); then
                    state=lost
                fi
            fi
        fi
        if [[ -f "$dir/output.log" ]]; then
            line="$(grep -a '^::ii-report ' "$dir/output.log" | tail -n 1)"
            if [[ -n "$line" ]]; then
                report="${line#::ii-report }"
                python3 -c 'import json,sys; json.loads(sys.argv[1])' "$report" 2>/dev/null || report=null
            fi
        fi
        printf '{"dir":%s,"state":"%s","exitCode":%s,"endedAt":%s,"report":%s}\n' \
            "$(json_str "$dir")" "$state" "${code:-null}" "${ended:-0}" "$report"
    done
    ;;
stop)
    # The wrapper leads its own session; signal the whole group.
    pid="$(cat "$2/pid" 2>/dev/null || echo)"
    [[ -n "$pid" ]] && kill -TERM -- "-$pid" 2>/dev/null
    ;;
*)
    echo "usage: run_task.sh start <dir> <command> | status <dir>... | stop <dir>" >&2
    exit 2
    ;;
esac
