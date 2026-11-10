#!/usr/bin/env bash
# qs-rebuild.sh — rebuild Quickshell for the installed Qt, then start the shell.
#
# qs-guard.sh opens it in a terminal when the shell cannot start, and the pacman
# hook's warning names it. It asks before every command it runs.
#
# - A package from the AUR (or built by hand) is rebuilt with yay or paru. The
#   `--rebuild` matters: without it yay finds the old build in its cache, prints
#   "already made -- skipping build" and installs the same binary again. So does
#   `aur/`: a repository package may provide the same name (CachyOS's noctalia-qs
#   provides quickshell-git), and the helper offers that one before the AUR.
# - A package from the distribution's repository cannot be rebuilt here; the
#   repository rebuilds it for each Qt release, so a full update is offered, and
#   the AUR's quickshell-git when the repository has no matching build yet.
#
# Usage: qs-rebuild.sh [quickshell args to start the shell with]   (default: -c ii)

set -u

dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
args=("$@")
((${#args[@]} > 0)) || args=(-c ii)

have() { command -v "$1" >/dev/null 2>&1; }
say() { printf '%s\n' "$*"; }
head_line() { printf '\n\033[1m%s\033[0m\n' "$*"; }

finish() {
    printf '\nPress Enter to close. '
    read -r _
    exit "${1:-0}"
}

# ask <question>: yes unless the answer starts with n.
ask() {
    local a
    printf '%s [Y/n] ' "$1"
    read -r a
    [[ ! "$a" =~ ^[Nn] ]]
}

# run <command…>: shows it, asks, runs it.
run() {
    say ""
    say "  $*"
    ask "Run this?" || return 1
    "$@"
}

compat=""
check() {
    local rc=0
    compat="$(qs --private-check-compat 2>&1)" || rc=$?
    compat="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$compat")"
    return "$rc"
}

start_shell() {
    if qs "${args[@]}" ipc show 2>/dev/null | grep -q '^target '; then
        ask "Restart the shell so it runs the new build?" || return 0
        qs kill "${args[@]}" >/dev/null 2>&1 || true
    else
        ask "Start the shell now?" || return 0
    fi
    setsid -f "$dir/qs-guard.sh" "${args[@]}" >/dev/null 2>&1 </dev/null
    say "Started."
}

head_line "Quickshell rebuild"

if ! have qs; then
    say "Quickshell is not installed."
    finish 1
fi
if check; then
    say "Quickshell already matches the installed Qt."
    start_shell
    finish 0
fi
say "$compat"

if ! have pacman; then
    say ""
    say "Rebuild the quickshell package with your package manager, then run this again."
    finish 1
fi

owner() { pacman -Qqo "$(readlink -f "$1")" 2>/dev/null; }

# A Quickshell built by hand into ~/.local (cmake --install) comes first on PATH
# and hides the package's: the package may already match Qt while the old
# hand-built binary is the one that runs. Moving it aside is then the fix.
packaged=""
if ! owner "$(command -v qs)" >/dev/null; then
    while IFS= read -r p; do
        if owner "$p" >/dev/null; then
            packaged="$p"
            break
        fi
    done < <(type -ap qs)
fi
if [[ -n "$packaged" ]]; then
    hand=()
    for name in qs quickshell; do
        p="$(command -v "$name")" || continue
        owner "$p" >/dev/null && continue
        for f in "$p" "$(readlink -f "$p")"; do
            [[ " ${hand[*]} " == *" $f "* ]] || hand+=("$f")
        done
    done
    head_line "A hand-built Quickshell hides the packaged one"
    say "$(command -v qs) runs instead of $packaged, from the package $(owner "$packaged")."
    say "Moving these aside lets the package's build run (nothing is deleted):"
    for f in "${hand[@]}"; do say "  $f -> $f.hand-built"; done
    if ! ask "Move them?"; then
        say "Remove them yourself, or rebuild them the way you installed them."
        finish 1
    fi
    for f in "${hand[@]}"; do
        mv -n -- "$f" "$f.hand-built" || finish 1
    done
    hash -r
    if check; then
        head_line "The packaged Quickshell matches the installed Qt."
        have hyprctl && hyprctl dismissnotify >/dev/null 2>&1
        start_shell
        finish 0
    fi
    say "$compat"
fi

bin="$(readlink -f "$(command -v qs)")"
if ! pkg="$(pacman -Qqo "$bin" 2>/dev/null)"; then
    say ""
    say "$bin does not belong to any package. Rebuild it from source the way you installed it."
    finish 1
fi
aur=""
for h in yay paru; do
    if have "$h"; then
        aur="$h"
        break
    fi
done

if pacman -Qqm "$pkg" >/dev/null 2>&1; then
    head_line "$pkg is built on this computer"
    if [[ -z "$aur" ]]; then
        say "No AUR helper (yay or paru) found. Rebuild it where its PKGBUILD is: makepkg -si"
        finish 1
    fi
    run "$aur" -S --rebuild "aur/$pkg"
else
    head_line "$pkg comes from your distribution's repository"
    say "The repository rebuilds it for each Qt release, so a full update usually brings the matching build."
    run sudo pacman -Syu
    if ! check && [[ -n "$aur" ]]; then
        head_line "The repository has no matching build yet"
        say "quickshell-git from the AUR builds from source against your Qt, in a few minutes."
        say "pacman will offer to replace $pkg with it."
        run "$aur" -S --rebuild aur/quickshell-git
    fi
fi

if check; then
    head_line "Quickshell matches the installed Qt again."
    have hyprctl && hyprctl dismissnotify >/dev/null 2>&1
    start_shell
    finish 0
fi
head_line "Quickshell still does not match the installed Qt."
say "$compat"
finish 1
