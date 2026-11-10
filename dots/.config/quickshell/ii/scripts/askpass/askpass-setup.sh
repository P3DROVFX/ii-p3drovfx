#!/usr/bin/env bash
# Puts the island's password prompts into (or takes them out of) the user's session.
# Run by AskpassService whenever the opt-in changes and once at shell start:
#
#   askpass-setup.sh <askpass 0|1> <terminal 0|1> <ssh 0|1> <fallback-askpass>
#
# The pieces live outside the shell's own tree, which a fork or branch switch replaces:
#   ~/.local/share/illogical-impulse/askpass/ii-askpass   the client every route runs
#   ~/.local/bin/sudo                                      the wrapper (marker-checked)
#   ~/.local/state/ii-askpass/mode                         what the wrapper obeys
# and the environment gets SUDO_ASKPASS (plus SSH_ASKPASS/GIT_ASKPASS when asked), in
# Hyprland for the programs it starts next and in the systemd/D-Bus activation
# environment for the rest. Terminals already open keep what they had.
set -u

askpass=${1:-0} terminal=${2:-0} ssh=${3:-0} previous=${4:-}
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
data="${XDG_DATA_HOME:-$HOME/.local/share}/illogical-impulse/askpass"
state="${XDG_STATE_HOME:-$HOME/.local/state}/ii-askpass"
client="$data/ii-askpass"
bin="$HOME/.local/bin"
wrapper="$bin/sudo"
marker="ii-askpass-wrapper"

ours() { [[ -f $1 ]] && sed -n '2p' "$1" | grep -q "$marker"; }

setenv() {
    command -v hyprctl >/dev/null 2>&1 && hyprctl eval "hl.env([[$1]], [[$2]])" >/dev/null 2>&1
    command -v systemctl >/dev/null 2>&1 && systemctl --user set-environment "$1=$2" 2>/dev/null
    command -v dbus-update-activation-environment >/dev/null 2>&1 \
        && dbus-update-activation-environment --systemd "$1=$2" >/dev/null 2>&1
}

unsetenv() {
    # Hyprland has no unsetenv; an empty value is what sudo/ssh/git treat as unset.
    command -v hyprctl >/dev/null 2>&1 && hyprctl eval "hl.env([[$1]], [[]])" >/dev/null 2>&1
    command -v systemctl >/dev/null 2>&1 && systemctl --user unset-environment "$1" 2>/dev/null
}

any=0
(( askpass || terminal || ssh )) && any=1

if (( any )); then
    mkdir -p "$data" "$state"
    install -m 755 "$here/ii-askpass" "$client.tmp" && mv -f "$client.tmp" "$client"
    printf 'askpass=%s\nterminal=%s\n' "$askpass" "$terminal" > "$state/mode.tmp" \
        && mv -f "$state/mode.tmp" "$state/mode"
else
    rm -f "$state/mode"
fi

# The wrapper: only for the sudo routes, never over a sudo that isn't ours.
wrapper_state="absent"
if (( askpass || terminal )); then
    if [[ -e $wrapper ]] && ! ours "$wrapper"; then
        wrapper_state="foreign"
    else
        mkdir -p "$bin"
        install -m 755 "$here/sudo-wrapper" "$wrapper.tmp" && mv -f "$wrapper.tmp" "$wrapper"
        wrapper_state="installed"
    fi
elif ours "$wrapper"; then
    rm -f "$wrapper"
fi

# The askpass the user had before stays reachable as the fallback. Never point it at
# ourselves: after a shell restart the environment already carries our client.
if (( any )) && [[ -n $previous && $(readlink -f -- "$previous" 2>/dev/null) != "$(readlink -f -- "$client")" ]]; then
    setenv II_ASKPASS_FALLBACK "$previous"
fi

# The environment is only ever touched for a route that is on, or to undo what an
# earlier run set (remembered in $state, which outlives the shell).
if (( askpass )); then
    setenv SUDO_ASKPASS "$client"
    touch "$state/env-sudo"
elif [[ -e $state/env-sudo ]]; then
    if [[ -n $previous && $(readlink -f -- "$previous" 2>/dev/null) != "$(readlink -f -- "$client")" ]]; then
        setenv SUDO_ASKPASS "$previous"
    else
        unsetenv SUDO_ASKPASS
    fi
    rm -f "$state/env-sudo"
fi

if (( ssh )); then
    setenv SSH_ASKPASS "$client"
    setenv SSH_ASKPASS_REQUIRE prefer
    setenv GIT_ASKPASS "$client"
    touch "$state/env-ssh"
elif [[ -e $state/env-ssh ]]; then
    unsetenv SSH_ASKPASS
    unsetenv SSH_ASKPASS_REQUIRE
    unsetenv GIT_ASKPASS
    rm -f "$state/env-ssh"
fi

onpath=0
case ":$PATH:" in *":$bin:"*) onpath=1 ;; esac
printf '{"wrapper":"%s","binOnPath":%s,"client":"%s"}\n' "$wrapper_state" \
    "$( ((onpath)) && echo true || echo false)" "$client"
