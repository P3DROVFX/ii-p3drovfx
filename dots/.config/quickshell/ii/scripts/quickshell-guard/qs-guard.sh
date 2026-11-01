#!/usr/bin/env bash
# qs-guard.sh — start Quickshell, and say so when it cannot run.
#
# The shell is its own notification daemon, so when it fails to start nothing on
# screen says why. The usual reason is a Qt update: a Quickshell built against the
# previous Qt crashes, or runs without loading its config. This starts the shell
# and watches it:
#
#   - before starting, `qs --private-check-compat` compares the Qt the binary was
#     built against with the one installed;
#   - a shell that exits with an error in its first 30 s is tried once more, and
#     one that never answers over IPC (its config did not load) has not started;
#   - when it has not started and Qt is the reason, a terminal opens on
#     qs-rebuild.sh, which rebuilds the package once you say yes;
#   - a crash later on restarts it, at most 3 times in 10 minutes.
#
# Stopping the shell on purpose (`qs kill`, killall, Ctrl+Super+R) ends it with a
# clean exit or SIGTERM, which the guard takes as "stopped" and exits with it.
#
# Messages go through Hyprland's own notifications (`hyprctl notify`), which need
# no notification daemon. Settings: health.guard.enable, health.guard.openTerminal.
#
# Usage: qs-guard.sh [quickshell args]   (default: -c ii)
# QS_GUARD_DRY=1 prints the notifications and the terminal command instead.

set -u

dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
args=("$@")
((${#args[@]} > 0)) || args=(-c ii)
# The shell and every process it spawns inherit this directory. A launcher's
# temp dir gets deleted under it, and git then refuses to run at all
# ("Unable to read current working directory"), which the update check
# reported as "Remote unreachable" for the whole session.
cd "$HOME" 2>/dev/null || cd /
# The allocator setting every other shell start uses (see hyprland/execs.lua).
export MALLOC_CONF="${MALLOC_CONF:-narenas:1}"

config="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"

have() { command -v "$1" >/dev/null 2>&1; }

# opt <jq path> <default>: a boolean from the shell's config. jq's `//` would turn
# a stored false into the default, so null is tested for instead.
opt() {
    local v=""
    have jq && v="$(jq -r "$1 | if . == null then \"$2\" else tostring end" "$config" 2>/dev/null)"
    if [[ "$v" == true || "$v" == false ]]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

# notify <icon> <seconds> <text>. Hyprland's icons: 0 warning, 1 info, 3 error.
notify() {
    if [[ -n "${QS_GUARD_DRY:-}" ]]; then
        printf 'notify[%s]: %s\n' "$1" "$3" >&2
        return 0
    fi
    if have hyprctl && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] &&
        hyprctl notify "$1" "$(($2 * 1000))" 0 "fontsize:15 $3" >/dev/null 2>&1; then
        return 0
    fi
    # Only a daemon that already runs: activating one by D-Bus can hang here.
    if have notify-send && have busctl && busctl --user status org.freedesktop.Notifications >/dev/null 2>&1; then
        notify-send -u critical -a Quickshell Quickshell "$3"
    fi
    printf 'qs-guard: %s\n' "$3" >&2
}

if ! have qs; then
    notify 3 600 "Quickshell is not installed, so the shell cannot start."
    exit 127
fi
if [[ "$(opt .health.guard.enable true)" == false ]]; then
    exec qs "${args[@]}"
fi

# ── Qt ──────────────────────────────────────────────────────────────────
built="" installed=""
qt_ok=true
compat="$(qs --private-check-compat 2>&1)" || qt_ok=false
if [[ "$qt_ok" == false ]]; then
    compat="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$compat")"
    [[ "$compat" =~ built\ against\ Qt\ ([0-9.]+) ]] && built="${BASH_REMATCH[1]}"
    [[ "$compat" =~ updated\ to\ Qt\ ([0-9.]+) ]] && installed="${BASH_REMATCH[1]}"
fi
rebuild_cmd="${dir/#$HOME/\~}/qs-rebuild.sh"

qt_mismatch_text() {
    if [[ -n "$built" && -n "$installed" ]]; then
        printf 'Quickshell was built for Qt %s, but Qt %s is installed' "$built" "$installed"
    else
        printf 'Quickshell does not match the installed Qt'
    fi
}

open_terminal() {
    [[ "$(opt .health.guard.openTerminal true)" == true ]] || return 1
    local term=""
    have jq && term="$(jq -r '.apps.terminal // empty' "$config" 2>/dev/null)"
    [[ -n "$term" ]] || term="kitty -1"
    local cmd
    read -ra cmd <<<"$term"
    cmd+=(-e bash "$dir/qs-rebuild.sh" "${args[@]}")
    if [[ -n "${QS_GUARD_DRY:-}" ]]; then
        printf 'terminal: %s\n' "${cmd[*]}" >&2
        return 0
    fi
    setsid -f "${cmd[@]}" >/dev/null 2>&1 </dev/null
}

# describe <status>: "SIGSEGV" for a signal, "exit code 1" otherwise.
describe() {
    if (($1 > 128)); then
        printf 'SIG%s' "$(kill -l "$(($1 - 128))" 2>/dev/null || printf '%s' "$(($1 - 128))")"
    else
        printf 'exit code %s' "$1"
    fi
}

loaded() {
    qs "${args[@]}" ipc show 2>/dev/null | grep -q '^target '
}

not_started() {
    if [[ "$qt_ok" == false ]]; then
        if open_terminal; then
            notify 3 120 "The shell cannot start. $(qt_mismatch_text). A terminal is open to rebuild it."
        else
            notify 3 3600 "The shell cannot start. $(qt_mismatch_text). Rebuild it: $rebuild_cmd"
        fi
    else
        notify 3 600 "The shell cannot start ($1). See what it logged: qs log ${args[*]}"
    fi
}

# Still running is not enough: the log may be its only output.
if [[ "$qt_ok" == false ]]; then
    notify 0 600 "$(qt_mismatch_text). The shell may crash until it is rebuilt: $rebuild_cmd"
fi

# ── Running it ──────────────────────────────────────────────────────────
child=0
trap '((child > 0)) && kill -TERM "$child" 2>/dev/null; exit 0' TERM INT HUP

early=0
crashes=()
while :; do
    started=$SECONDS
    qs "${args[@]}" &
    child=$!

    # A shell whose config failed to load keeps running and shows nothing. It
    # answers over IPC once its config is up, which takes well under a second.
    up=false
    for ((i = 0; i < 45; i++)); do
        sleep 1
        kill -0 "$child" 2>/dev/null || break
        if loaded; then
            up=true
            break
        fi
    done
    if [[ "$up" == false ]] && kill -0 "$child" 2>/dev/null; then
        # Left running: a config fixed on disk hot-reloads into it.
        not_started "its config did not load"
    fi

    wait "$child"
    rc=$?
    child=0
    ran=$((SECONDS - started))

    # Quit, HUP, INT, KILL, TERM: stopped on purpose.
    case "$rc" in 0 | 129 | 130 | 137 | 143) exit 0 ;; esac
    # Started again from elsewhere in the meantime: that one is the shell now.
    loaded && exit 0

    if ((ran < 30)); then
        early=$((early + 1))
        if ((early < 2)); then
            sleep 2
            continue
        fi
        not_started "$(describe "$rc")"
        exit 1
    fi
    early=0

    now=$SECONDS
    recent=()
    for t in "${crashes[@]}"; do
        ((now - t < 600)) && recent+=("$t")
    done
    crashes=("${recent[@]}" "$now")
    if ((${#crashes[@]} > 3)); then
        notify 3 600 "The shell crashed again ($(describe "$rc")), 4 times in 10 minutes, so it was left stopped. Ctrl+Super+R starts it."
        exit 1
    fi
    if [[ "$qt_ok" == false ]]; then
        notify 0 30 "The shell crashed ($(describe "$rc")) and was restarted. $(qt_mismatch_text): $rebuild_cmd"
    else
        notify 0 15 "The shell crashed ($(describe "$rc")) and was restarted."
    fi
    sleep 1
done
