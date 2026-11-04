#!/usr/bin/env bash
# scrolloverview plugin manager (github.com/yayuuu/hyprland-scroll-overview).
#
# The zscroll layout's overview. A Hyprland plugin is compiled against one exact
# Hyprland commit, so this builds the plugin commit the upstream hyprpm.toml pins
# for the running Hyprland, then loads it. Settings -> Hyprland -> Layout calls it.
#
#   scrolloverview.sh status    one JSON line: {"hyprland","supported","built","builtFor","loaded","path"}
#   scrolloverview.sh install   clone/fetch, check out the pin, build, load
#   scrolloverview.sh load      load the built .so if it matches the running Hyprland (startup)
#   scrolloverview.sh unload
#
# Progress goes to stderr as "step: <text>" lines; the last stdout line is the status JSON.
set -uo pipefail

REPO="https://github.com/yayuuu/hyprland-scroll-overview.git"
DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/plugins/hyprland-scroll-overview"
SO="$DIR/scrolloverview.so"
STAMP="$DIR/.ii-built-for"

hypr_commit() { hyprctl version -j 2>/dev/null | jq -r '.commit // empty'; }
hypr_tag() { hyprctl version -j 2>/dev/null | jq -r '.tag // empty'; }

# The plugin commit pinned for a Hyprland commit, from the repo's hyprpm.toml.
# Read from origin's newest copy: the checked-out (pinned) commit's list is older.
# Pins upstream has ported to but not yet listed in hyprpm.toml (each is a commit
# on its main branch). Upstream's own list wins once it has the entry.
#   v0.57.0 -> dcdd3b5 (PR #88 port; pin pending in PR #89)
KNOWN_PINS="0aa6745f705f2c4b0a5004eb019ef76e5bbdb426 dcdd3b502617e70fb3a9fd3b568d20440048008a"

pinned_for() {
    local pin=""
    if [ -d "$DIR/.git" ]; then
        pin="$(git -C "$DIR" show origin/HEAD:hyprpm.toml 2>/dev/null \
            | grep -o "\[\"$1\", *\"[0-9a-f]*\"\]" | head -n1 | sed -E 's/.*, *"([0-9a-f]+)"\]/\1/')"
    fi
    if [ -z "$pin" ]; then
        set -- "$1" $KNOWN_PINS
        local commit="$1"; shift
        while [ $# -ge 2 ]; do
            [ "$1" = "$commit" ] && { pin="$2"; break; }
            shift 2
        done
    fi
    [ -n "$pin" ] && echo "$pin"
}

is_loaded() { hyprctl plugin list 2>/dev/null | grep -qi 'scrolloverview\|scroll-overview\|scroll overview'; }

status() {
    local commit tag pin supported=false built=false built_for="" loaded=false
    commit="$(hypr_commit)"; tag="$(hypr_tag)"
    pin="$(pinned_for "$commit" 2>/dev/null || true)"
    [ -n "$pin" ] && supported=true
    [ -f "$SO" ] && built=true
    [ -f "$STAMP" ] && built_for="$(cat "$STAMP")"
    is_loaded && loaded=true
    printf '{"hyprland":"%s","supported":%s,"built":%s,"builtFor":"%s","current":%s,"loaded":%s,"path":"%s"}\n' \
        "$tag" "$supported" "$built" "$built_for" \
        "$([ -n "$commit" ] && [ "$built_for" = "$commit" ] && echo true || echo false)" "$loaded" "$SO"
}

step() { echo "step: $*" >&2; }
fail() { echo "error: $*" >&2; status; exit 1; }

load() {
    local commit; commit="$(hypr_commit)"
    is_loaded && return 0
    [ -f "$SO" ] || return 1
    # A plugin built for another Hyprland can crash the compositor: never load it.
    [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$commit" ] || return 1
    hyprctl plugin load "$SO" >/dev/null
}

install() {
    command -v git >/dev/null || fail "git is not installed"
    command -v g++ >/dev/null || fail "g++ is not installed"
    pkg-config --exists hyprland || fail "Hyprland development headers (pkg-config hyprland) are missing"
    if [ -d "$DIR/.git" ]; then
        step "Updating the plugin source"
        git -C "$DIR" fetch --quiet --tags origin 2>&1 >&2 || fail "git fetch failed"
        [ "$(git -C "$DIR" rev-parse --is-shallow-repository)" = true ] && git -C "$DIR" fetch --quiet --unshallow >&2
    else
        step "Downloading the plugin source"
        mkdir -p "$(dirname "$DIR")"
        git clone --quiet "$REPO" "$DIR" >&2 || fail "git clone failed"
    fi
    local commit pin
    commit="$(hypr_commit)"
    [ -n "$commit" ] || fail "Hyprland is not answering"
    pin="$(pinned_for "$commit")"
    [ -n "$pin" ] || fail "the plugin has no build for Hyprland $(hypr_tag) yet"
    step "Checking out the build for Hyprland $(hypr_tag)"
    git -C "$DIR" checkout --quiet "$pin" >&2 || fail "checkout of $pin failed"
    step "Compiling (about a minute)"
    make -C "$DIR" clean >/dev/null 2>&1
    make -C "$DIR" all >"$DIR/.ii-build.log" 2>&1 || { tail -n 5 "$DIR/.ii-build.log" >&2; fail "the build failed"; }
    echo "$commit" > "$STAMP"
    is_loaded && { step "Reloading the plugin"; hyprctl plugin unload "$SO" >/dev/null 2>&1; }
    step "Loading the plugin"
    load || fail "Hyprland refused to load the plugin"
    status
}

case "${1:-status}" in
    status) status ;;
    install) install ;;
    load) load; status ;;
    unload) hyprctl plugin unload "$SO" >/dev/null 2>&1; status ;;
    *) echo "usage: $0 status|install|load|unload" >&2; exit 2 ;;
esac
