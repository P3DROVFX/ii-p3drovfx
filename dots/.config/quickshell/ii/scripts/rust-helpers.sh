#!/usr/bin/env bash
# rust-helpers.sh — the shell's Rust helpers: what they are, what they were
# built from, and whether that is still true.
#
# The helpers ship as source and are built on the machine that runs them, which
# leaves one thing nobody can see: an update replaces `*_src/` and carries the
# old binary across untouched (PROTECTED_PATTERNS in setup-ii-p3drovfx.sh), so a
# helper keeps running last month's code with no sign anywhere that it does.
#
# The signal is a stamp written beside each binary holding a hash of the sources
# it was built from. Stale is "stamp missing, or stamp no longer matches", which
# needs nobody to remember to bump a version and catches local edits too.
#
# Usage:
#   rust-helpers.sh list                  names of every helper
#   rust-helpers.sh status [name...]      "<name> <state>" per line
#   rust-helpers.sh outdated              names worth rebuilding: stale + unknown
#   rust-helpers.sh dir <name>            directory holding binary, sources, stamp
#   rust-helpers.sh hash <name>           hash of the current sources
#   rust-helpers.sh stamp <name>          record the current sources as built
#   rust-helpers.sh build [name...]       build, install and stamp
#   rust-helpers.sh build-outdated        build whatever `outdated` lists
#
# The four states:
#   ok       the binary matches the sources beside it
#   stale    it was built from sources that have since changed
#   unknown  a binary from before stamps existed, or one built by hand — it may
#            well be current, but nothing on disk says so
#   missing  never built. Never built implicitly either: a helper nobody
#            compiled is one nobody asked for, and an updater that compiles it
#            anyway is a surprise.
set -uo pipefail

SCRIPTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# name:directory, relative to the scripts dir. The binary is <dir>/<name>, the
# sources <dir>/<name>_src, the stamp <dir>/.<name>.stamp.
HELPERS=(
    "osk_autoshow:osk"
    "touch_gestures:touchGestures"
    "app_stats:appStats"
    "workspace_compactor:hyprland"
    "workspace_profile_manager:hyprland"
    "sni_watcher:tray"
)

helper_dir() {
    local entry
    for entry in "${HELPERS[@]}"; do
        [[ "${entry%%:*}" == "$1" ]] && {
            printf '%s' "$SCRIPTS_DIR/${entry#*:}"
            return 0
        }
    done
    printf 'rust-helpers: unknown helper "%s"\n' "$1" >&2
    return 1
}

# Everything cargo actually compiles, hashed under relative names so the result
# does not change when the config directory moves. Cargo.lock is deliberately
# untracked, so a dependency bump is seen through Cargo.toml.
src_hash() {
    local src="$1"
    [[ -d "$src" ]] || return 1
    (
        cd "$src" || exit 1
        find Cargo.toml src -type f -print0 2>/dev/null |
            LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
    )
}

state_of() {
    local name="$1" dir bin stamp want have
    dir="$(helper_dir "$name")" || return 1
    bin="$dir/$name"
    stamp="$dir/.$name.stamp"
    [[ -x "$bin" ]] || {
        printf 'missing'
        return 0
    }
    want="$(src_hash "$dir/${name}_src")" || {
        # Sources gone but a binary present: nothing to compare against, and
        # nothing the user can do about it either. Not a complaint worth making.
        printf 'ok'
        return 0
    }
    [[ -f "$stamp" ]] || {
        printf 'unknown'
        return 0
    }
    have="$(cut -d' ' -f1 <"$stamp")"
    [[ "$have" == "$want" ]] && printf 'ok' || printf 'stale'
}

write_stamp() {
    local name="$1" dir hash
    dir="$(helper_dir "$name")" || return 1
    hash="$(src_hash "$dir/${name}_src")" || return 1
    printf '%s %s\n' "$hash" "$(date -Is)" >"$dir/.$name.stamp"
}

build_one() {
    local name="$1" dir src bin
    dir="$(helper_dir "$name")" || return 1
    src="$dir/${name}_src"
    bin="$dir/$name"
    [[ -d "$src" ]] || {
        printf 'rust-helpers: no sources for %s\n' "$name" >&2
        return 1
    }
    command -v cargo >/dev/null 2>&1 || {
        printf 'rust-helpers: cargo is not installed\n' >&2
        return 1
    }
    ( cd "$src" && cargo build --release ) || return 1
    # Installed through a rename: the previous helper is usually still running,
    # and writing over a running executable is ETXTBSY — cp fails and throws
    # away a compile that worked. A rename leaves it on the old inode.
    cp "$src/target/release/$name" "$bin.new" || return 1
    mv -f "$bin.new" "$bin" || return 1
    write_stamp "$name"
}

names_from_args() {
    if (($# > 0)); then
        printf '%s\n' "$@"
        return 0
    fi
    local entry
    for entry in "${HELPERS[@]}"; do printf '%s\n' "${entry%%:*}"; done
}

cmd="${1:-status}"
shift || true
rc=0

case "$cmd" in
list)
    names_from_args
    ;;
status)
    while IFS= read -r name; do
        printf '%s %s\n' "$name" "$(state_of "$name")" || rc=1
    done < <(names_from_args "$@")
    ;;
outdated)
    while IFS= read -r name; do
        case "$(state_of "$name")" in
        stale | unknown) printf '%s\n' "$name" ;;
        esac
    done < <(names_from_args "$@")
    ;;
dir)
    helper_dir "${1:?helper name required}" || exit 1
    printf '\n'
    ;;
hash)
    dir="$(helper_dir "${1:?helper name required}")" || exit 1
    src_hash "$dir/${1}_src" || exit 1
    ;;
stamp)
    write_stamp "${1:?helper name required}" || exit 1
    ;;
build)
    while IFS= read -r name; do
        build_one "$name" || rc=1
    done < <(names_from_args "$@")
    ;;
build-outdated)
    while IFS= read -r name; do
        case "$(state_of "$name")" in
        stale | unknown) ;;
        *) continue ;;
        esac
        build_one "$name" || rc=1
    done < <(names_from_args "$@")
    ;;
*)
    # The usage block itself, rather than a second copy of it kept in sync.
    awk '/^# Usage:/{u=1} u&&/^#/{sub(/^# ?/, ""); print; next} u{exit}' "${BASH_SOURCE[0]}"
    exit 2
    ;;
esac

exit "$rc"
