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
#   rust-helpers.sh prebuilt              names the CI publishes prebuilt
#   rust-helpers.sh fetch [name...]       download the CI's build of the current
#                                         sources, verify, install and stamp
#   rust-helpers.sh install [name...]     fetch, or build when there is no
#                                         prebuilt (or it fails) and cargo is here
#   rust-helpers.sh install-outdated      install whatever `outdated` lists
#
# Prebuilt helpers (PREBUILT below) are compiled by .github/workflows/rust-helpers.yml
# into one GitHub release per source hash: tag <prefix>-<first 16 hex of the hash>,
# assets <name>-x86_64 / <name>-aarch64 (static, musl) and SHA256SUMS. The hash is the
# same one the stamp holds, so the download is exactly the sources beside it; a fork
# with other sources finds no release and builds instead. II_HELPERS_REPO overrides
# where releases are looked for (owner/repo).
#
# The four states:
#   ok       the binary matches the sources beside it
#   stale    it was built from sources that have since changed
#   unknown  a binary from before stamps existed, or one built by hand — it may
#            well be current, but nothing on disk says so
#   missing  never built. Never built implicitly either: a helper nobody
#            compiled is one nobody asked for, and an updater that compiles it
#            anyway is a surprise.
#
# A binary that is gone while its stamp is still there (or the binary or stamp
# of the name it had before a rename) was built once and then lost, usually to
# an updater that did not know its name yet. That reads as `stale`, not
# `missing`: the user did ask for it, so the next update offers it back.
set -uo pipefail

SCRIPTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# name:directory, relative to the scripts dir. The binary is <dir>/<name>, the
# sources <dir>/<name>_src, the stamp <dir>/.<name>.stamp.
HELPERS=(
    "osk_autoshow:osk"
    "touch_gestures:touchGestures"
    "app_stats:appStats"
    "workspace_arranger:hyprland"
    "workspace_profile_manager:hyprland"
    "sni_watcher:tray"
    "health_watch:health"
    "ii_link:iiLink"
)

# name:release tag prefix, for the helpers the CI publishes.
PREBUILT=(
    "ii_link:ii-link"
)
RELEASES_REPO="${II_HELPERS_REPO:-P3DROVFX/ii-p3drovfx}"

# name:former name, in the same directory. An updater from before the rename
# carries the old binary and stamp across and drops the new binary.
FORMER_NAMES=(
    "workspace_arranger:workspace_compactor"
)

former_name() {
    local entry
    for entry in "${FORMER_NAMES[@]}"; do
        [[ "${entry%%:*}" == "$1" ]] && {
            printf '%s' "${entry#*:}"
            return 0
        }
    done
    return 1
}

# was_built <name> <dir> — a stamp, or anything left under the former name.
was_built() {
    local name="$1" dir="$2" old
    [[ -f "$dir/.$name.stamp" ]] && return 0
    old="$(former_name "$name")" || return 1
    [[ -e "$dir/$old" || -f "$dir/.$old.stamp" ]]
}

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
        was_built "$name" "$dir" && printf 'stale' || printf 'missing'
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
    write_stamp "$name" || return 1
    # Whatever is left under the former name only keeps `was_built` answering.
    local old
    old="$(former_name "$name")" && rm -f "$dir/$old" "$dir/.$old.stamp"
    return 0
}

prebuilt_prefix() {
    local entry
    for entry in "${PREBUILT[@]}"; do
        [[ "${entry%%:*}" == "$1" ]] && {
            printf '%s' "${entry#*:}"
            return 0
        }
    done
    return 1
}

# fetch_one <name> — the CI's build of exactly these sources, checked against the
# release's SHA256SUMS, installed through the same rename as a local build.
fetch_one() {
    local name="$1" prefix dir hash arch base tmp want have
    prefix="$(prebuilt_prefix "$name")" || {
        printf 'rust-helpers: %s is not published prebuilt\n' "$name" >&2
        return 1
    }
    dir="$(helper_dir "$name")" || return 1
    hash="$(src_hash "$dir/${name}_src")" || return 1
    case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *)
        printf 'rust-helpers: no prebuilt %s for %s\n' "$name" "$(uname -m)" >&2
        return 1
        ;;
    esac
    command -v curl >/dev/null 2>&1 || {
        printf 'rust-helpers: curl is not installed\n' >&2
        return 1
    }
    base="https://github.com/$RELEASES_REPO/releases/download/$prefix-${hash:0:16}"
    tmp="$(mktemp -d)" || return 1
    if ! curl -fsSL --proto '=https' --retry 2 --connect-timeout 10 -o "$tmp/$name" "$base/$name-$arch" ||
        ! curl -fsSL --proto '=https' --retry 2 --connect-timeout 10 -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"; then
        rm -rf "$tmp"
        printf 'rust-helpers: no prebuilt %s for these sources (%s) yet\n' "$name" "${hash:0:16}" >&2
        return 1
    fi
    want="$(awk -v f="$name-$arch" '$2 == f || $2 == "*" f { print $1 }' "$tmp/SHA256SUMS")"
    have="$(sha256sum "$tmp/$name" | cut -d' ' -f1)"
    if [[ -z "$want" || "$want" != "$have" ]]; then
        rm -rf "$tmp"
        printf 'rust-helpers: the downloaded %s does not match SHA256SUMS\n' "$name" >&2
        return 1
    fi
    chmod 755 "$tmp/$name"
    # Copied beside the binary first: /tmp is often another filesystem, and only a
    # rename on the same one leaves a running helper on its old inode.
    cp "$tmp/$name" "$dir/$name.new" && mv -f "$dir/$name.new" "$dir/$name" || {
        rm -rf "$tmp" "$dir/$name.new"
        return 1
    }
    rm -rf "$tmp"
    write_stamp "$name"
}

# install_one <name> — the prebuilt when there is one, else a local build.
install_one() {
    local name="$1"
    if prebuilt_prefix "$name" >/dev/null; then
        fetch_one "$name" && return 0
        printf 'rust-helpers: building %s here instead\n' "$name" >&2
    fi
    build_one "$name"
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
prebuilt)
    for entry in "${PREBUILT[@]}"; do printf '%s\n' "${entry%%:*}"; done
    ;;
fetch)
    if (($# == 0)); then
        set -- $(for entry in "${PREBUILT[@]}"; do printf '%s ' "${entry%%:*}"; done)
    fi
    for name in "$@"; do
        fetch_one "$name" || rc=1
    done
    ;;
install)
    while IFS= read -r name; do
        install_one "$name" || rc=1
    done < <(names_from_args "$@")
    ;;
install-outdated)
    while IFS= read -r name; do
        case "$(state_of "$name")" in
        stale | unknown) ;;
        *) continue ;;
        esac
        install_one "$name" || rc=1
    done < <(names_from_args "$@")
    ;;
*)
    # The usage block itself, rather than a second copy of it kept in sync.
    awk '/^# Usage:/{u=1} u&&/^#/{sub(/^# ?/, ""); print; next} u{exit}' "${BASH_SOURCE[0]}"
    exit 2
    ;;
esac

exit "$rc"
