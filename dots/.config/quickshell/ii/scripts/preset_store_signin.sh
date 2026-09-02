#!/usr/bin/env bash
# Install the GitHub CLI if it is missing, then sign it in.
#
# This runs in a terminal on purpose: installing a package asks for a password,
# and a password prompt belongs in a tty rather than behind a shell surface.
# Everything here is idempotent -- run it again and it only does what is left.

set -u

BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

say() { printf '%s\n' "${BOLD}$*${RESET}"; }
note() { printf '%s\n' "${DIM}$*${RESET}"; }

finish() {
    printf '\n'
    read -rsn1 -p "Press any key to close this window… " _ || true
    printf '\n'
    exit "${1:-0}"
}

install_gh() {
    # Whichever package manager is actually here. yay and paru handle their own
    # privilege escalation; the rest need sudo, which is why this is a terminal.
    if command -v yay >/dev/null 2>&1; then
        yay -S --needed --noconfirm github-cli
    elif command -v paru >/dev/null 2>&1; then
        paru -S --needed --noconfirm github-cli
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm github-cli
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y gh
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y gh
    elif command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y gh
    elif command -v nix-env >/dev/null 2>&1; then
        nix-env -iA nixpkgs.gh
    else
        return 127
    fi
}

if ! command -v gh >/dev/null 2>&1; then
    say "The GitHub CLI is not installed yet."
    note "It is what publishing a preset uses to create and push your repository."
    printf '\n'
    if ! install_gh; then
        printf '\n'
        say "Could not install it automatically."
        note "Install the github-cli package with your package manager, then run this again."
        finish 1
    fi
    printf '\n'
    if ! command -v gh >/dev/null 2>&1; then
        say "The installation did not finish."
        finish 1
    fi
    say "Installed."
    printf '\n'
fi

# Already signed in *and* allowed to create repositories? Then there is
# nothing to do, and re-running the login would only throw away a working
# session. A fine-grained token reports no scopes at all, so an empty scope
# list is taken at face value rather than read as "missing everything".
if gh auth token >/dev/null 2>&1; then
    scopes=$(gh api -i user 2>/dev/null | tr -d '\r' | grep -i '^x-oauth-scopes:' | head -1 | cut -d: -f2-)
    trimmed=${scopes// /}
    if [[ -z "$trimmed" ]] || grep -qw 'repo' <<<"$scopes"; then
        say "Already signed in with everything publishing needs."
        finish 0
    fi
    say "Signed in, but this session cannot create repositories."
    note "Signing in again, this time asking for the permission publishing needs."
    printf '\n'
else
    say "Signing in to GitHub."
    note "Pick HTTPS when asked. A one-time code is printed that you can enter"
    note "on any device -- no browser has to open on this machine."
    printf '\n'
fi

# --scopes repo every time: an existing session signed in without it can read
# GitHub perfectly well and still fail at the moment it creates the repository.
if ! gh auth login --hostname github.com --git-protocol https --scopes repo; then
    printf '\n'
    say "Sign-in did not complete."
    note "Nothing was changed. You can run this again whenever you like."
    finish 1
fi

printf '\n'
say "Done. The Presets page picks this up on its own."
finish 0
