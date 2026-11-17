#!/usr/bin/env bash
# cpp-helpers.sh — the shell's C++ helpers: building them on this machine instead
# of running the binaries committed next to their sources, and knowing afterwards
# which of the two is in place.
#
# Each helper ships twice: as `<name>.cpp`, and as a stripped binary built from it
# on the author's machine and committed beside it. The committed binary is what
# runs by default, and it is enough on any distribution with glibc at
# /lib64/ld-linux-x86-64.so.2 (on NixOS, through nix-ld). Building here is a
# choice: an auditable binary, linked against this system's own libraries.
#
# A local build replaces the binary at the same path, so nothing that launches it
# changes. What marks it as local is a stamp beside it, `.<name>.stamp`, holding
# a hash of what it was built from (the source file plus the recipe below) and a
# hash of the binary that build produced. The updater (setup-ii-p3drovfx.sh)
# reads the stamp to decide whether to keep the local binary across an update or
# to take the repository's, so the stamp is also the user's choice: no stamp,
# the committed binary; a stamp, built here.
#
# Usage:
#   cpp-helpers.sh [--out-dir DIR] <command> [name...]
#
#   list                  names of every helper
#   path <name>           binary path, relative to the config dir
#   dir <name>            directory holding the binary and its stamp
#   status [name...]      "<name> <state>" per line
#   outdated [name...]    names built here that need building again
#   check [name...]       "<name> ok" or "<name> missing: <what>" — can it be built here
#   hash <name>           hash of the current source and recipe
#   build [name...]       build, install and stamp (all helpers when none named)
#   build-outdated        build whatever `outdated` lists
#   prebuilt [name...]    forget the local build: the next update installs the
#                         repository's binary again (or now: ii-p3drovfx update
#                         --force --prebuilt-helpers)
#   mark-fallback <name>  record that a local build is wanted but the committed
#                         binary is in place (the updater, after a failed build)
#
# --out-dir (or CPP_HELPERS_OUT_DIR) puts binaries and stamps under another root,
# in the same layout; sources are always read from the config dir this script is
# in. For trying a build without touching the installed binaries. Without it,
# `build` refuses to write over a binary git tracks: run from the fork's own
# checkout it would replace the committed binaries with ones linked against this
# machine. The updater always names its output root.
#
# The states:
#   prebuilt  no stamp: the committed binary, as shipped. Nothing to do.
#   ok        built here from the sources beside it
#   stale     built here from sources (or a recipe) that have since changed
#   replaced  stamped as built here, but the binary in place is not the one that
#             build produced, or is gone: something put another one there (an
#             older updater that did not know these helpers, or a copy by hand)
#   broken    built here, and its libraries or loader no longer resolve (on NixOS:
#             a garbage-collected store path; elsewhere: a soname bump)
#   fallback  built here once, but the last rebuild failed, so the committed
#             binary is running until a rebuild works
#   missing   no binary at all
#
# `outdated` is stale, replaced, broken and fallback: helpers somebody chose to
# build here that are not, right now, a current local build. `prebuilt` is never
# outdated — compiling a helper nobody asked to compile would be a surprise.
#
# Build requirements: a C++20 compiler (g++ or clang++), pkg-config, and the
# development files of glib2 (gio-2.0, gio-unix-2.0) and libxkbcommon. On Arch
# the glib2 and libxkbcommon packages carry their headers; Fedora needs the
# -devel packages. On NixOS the .pc files must be on PKG_CONFIG_PATH; the
# system and user profiles' lib/pkgconfig are added when they exist.
set -uo pipefail

SCRIPTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
II_DIR="$(cd -P "$SCRIPTS_DIR/.." >/dev/null 2>&1 && pwd)"

# name:directory:libraries. The directory is relative to the config dir; the
# source is <dir>/<name>.cpp, the binary <dir>/<name>, the stamp <dir>/.<name>.stamp.
# Libraries are pkg-config groups, spelled out in PKG_MODULES below.
HELPERS=(
    "agent:scripts/bluetooth:gio"
    "discord_voice_bridge:scripts/discordVoice:"
    "drag_monitor:scripts/hyprland:"
    "contacts_monitor:scripts/kdeconnect:"
    "monitor:scripts/kdeconnect:gio"
    "privacy_probe:scripts:"
    "tablet_scroll:scripts/tablet:"
    "keypress_monitor:scripts/videos:xkbcommon"
    "jobview_monitor:services:gio"
)

declare -A PKG_MODULES=(
    [gio]="gio-2.0 gio-unix-2.0"
    [xkbcommon]="xkbcommon"
)

# The flags the committed binaries were built with (commit ac3186087: C++20,
# -O2, stripped). Part of the stamp's hash, so changing them rebuilds everything.
CXXFLAGS_FIXED=(-std=c++20 -O2 -s)

OUT_DIR="${CPP_HELPERS_OUT_DIR:-}"

entry_of() {
    local entry
    for entry in "${HELPERS[@]}"; do
        [[ "${entry%%:*}" == "$1" ]] && {
            printf '%s' "$entry"
            return 0
        }
    done
    printf 'cpp-helpers: unknown helper "%s"\n' "$1" >&2
    return 1
}

rel_dir() {
    local entry rest
    entry="$(entry_of "$1")" || return 1
    rest="${entry#*:}"
    printf '%s' "${rest%%:*}"
}

modules_of() {
    local entry lib
    entry="$(entry_of "$1")" || return 1
    lib="${entry##*:}"
    [[ -n "$lib" ]] && printf '%s' "${PKG_MODULES[$lib]}"
    return 0
}

src_of() { printf '%s/%s/%s.cpp' "$II_DIR" "$(rel_dir "$1")" "$1"; }
out_root() { printf '%s' "${OUT_DIR:-$II_DIR}"; }
bin_of() { printf '%s/%s/%s' "$(out_root)" "$(rel_dir "$1")" "$1"; }
stamp_of() { printf '%s/%s/.%s.stamp' "$(out_root)" "$(rel_dir "$1")" "$1"; }

# The recipe, written out the way it is hashed: what changes the binary.
recipe_of() {
    printf 'c++ %s | pkg-config %s\n' "${CXXFLAGS_FIXED[*]}" "$(modules_of "$1")"
}

# Hash of the source plus the recipe. Sources are single files with no local
# includes, so nothing else can change what they compile to — short of the
# compiler and the libraries, which `broken` covers where it matters.
src_hash() { src_hash_of "$1" "$(src_of "$1")"; }

# src_hash_of <name> <file> — the same hash, of a given copy of the source.
src_hash_of() {
    [[ -f "$2" ]] || return 1
    { recipe_of "$1"; cat "$2"; } | sha256sum | cut -d' ' -f1
}

file_hash() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# On NixOS nothing is on pkg-config's default path; the profiles are where a
# package with a dev output installed system-wide or per user shows up.
nixos_pkg_config_path() {
    [[ -d /run/current-system ]] || return 0
    local d extra=""
    for d in /run/current-system/sw/lib/pkgconfig /run/current-system/sw/share/pkgconfig \
        "/etc/profiles/per-user/${USER:-$(id -un)}/lib/pkgconfig" "$HOME/.nix-profile/lib/pkgconfig"; do
        [[ -d "$d" ]] && extra="$extra${extra:+:}$d"
    done
    [[ -n "$extra" ]] && export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:+$PKG_CONFIG_PATH:}$extra"
    return 0
}

CXX_BIN=""
PKG_CONFIG_BIN=""
find_tools() {
    local c
    if [[ -n "${CXX:-}" ]] && command -v "$CXX" >/dev/null 2>&1; then
        CXX_BIN="$CXX"
    else
        for c in g++ clang++ c++; do
            command -v "$c" >/dev/null 2>&1 && {
                CXX_BIN="$c"
                break
            }
        done
    fi
    for c in "${PKG_CONFIG:-pkg-config}" pkg-config pkgconf; do
        command -v "$c" >/dev/null 2>&1 && {
            PKG_CONFIG_BIN="$c"
            break
        }
    done
    nixos_pkg_config_path
}

# missing_for <name> — what stands between this machine and a build, or nothing.
missing_for() {
    local name="$1" mods m out=()
    [[ -f "$(src_of "$name")" ]] || out+=("source")
    [[ -n "$CXX_BIN" ]] || out+=("C++ compiler")
    mods="$(modules_of "$name")"
    if [[ -n "$mods" ]]; then
        if [[ -z "$PKG_CONFIG_BIN" ]]; then
            out+=("pkg-config")
        else
            for m in $mods; do
                "$PKG_CONFIG_BIN" --exists "$m" 2>/dev/null || out+=("$m")
            done
        fi
    fi
    ((${#out[@]} > 0)) && printf '%s' "${out[*]}"
    return 0
}

# loads <binary> — its loader and libraries still resolve. Only asked of local
# builds: a committed binary that does not load is not something a stamp can fix.
loads() {
    local bin="$1" interp
    # PT_INTERP sits in the first page of the file, as a plain string.
    interp="$(head -c 4096 "$bin" 2>/dev/null | tr -c '[:print:]' '\n' | grep -m1 -E '^/.*/ld-[^/ ]*\.so[.0-9]*$')"
    [[ -z "$interp" || -e "$interp" ]] || return 1
    command -v ldd >/dev/null 2>&1 || return 0
    local out
    out="$(ldd "$bin" 2>&1)" || return 1
    [[ "$out" != *"not found"* ]]
}

state_of() {
    local name="$1" bin stamp have_src have_bin want
    entry_of "$name" >/dev/null || return 1
    bin="$(bin_of "$name")"
    stamp="$(stamp_of "$name")"
    [[ -f "$stamp" ]] || {
        [[ -x "$bin" ]] && printf 'prebuilt' || printf 'missing'
        return 0
    }
    read -r have_src _ have_bin <"$stamp" || true
    [[ "$have_src" == fallback ]] && {
        printf 'fallback'
        return 0
    }
    [[ -x "$bin" ]] || {
        printf 'replaced'
        return 0
    }
    [[ -n "${have_bin:-}" && "$(file_hash "$bin")" == "$have_bin" ]] || {
        printf 'replaced'
        return 0
    }
    want="$(src_hash "$name")" || {
        # Sources gone but a local binary present: nothing to compare against.
        printf 'ok'
        return 0
    }
    [[ "$have_src" == "$want" ]] || {
        printf 'stale'
        return 0
    }
    loads "$bin" || {
        printf 'broken'
        return 0
    }
    printf 'ok'
}

is_outdated() {
    case "$1" in
    stale | replaced | broken | fallback) return 0 ;;
    esac
    return 1
}

# Temporary files of the build in progress, removed however the script ends.
TEMPS=()
# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() { ((${#TEMPS[@]} == 0)) || rm -rf "${TEMPS[@]}"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# tracked_here <path> — the path is a file git tracks. Building into the fork's
# own checkout would overwrite the committed binaries with ones linked against
# this machine (on NixOS: a /nix/store loader no other system has), one
# `git commit -a` away from being shipped.
tracked_here() {
    command -v git >/dev/null 2>&1 || return 1
    git -C "$(dirname "$1")" ls-files --error-unmatch -- "$(basename "$1")" >/dev/null 2>&1
}

build_one() {
    local name="$1" src bin stamp tmp snap mods missing hash
    entry_of "$name" >/dev/null || return 1
    src="$(src_of "$name")"
    bin="$(bin_of "$name")"
    stamp="$(stamp_of "$name")"
    if [[ -z "$OUT_DIR" ]] && tracked_here "$bin"; then
        printf 'cpp-helpers: %s is a binary tracked by git; not building over it.\n' "${bin#"$II_DIR"/}" >&2
        printf 'cpp-helpers: build elsewhere with --out-dir DIR, or into the deployed copy.\n' >&2
        return 1
    fi
    missing="$(missing_for "$name")"
    [[ -z "$missing" ]] || {
        printf 'cpp-helpers: cannot build %s here, missing: %s\n' "$name" "$missing" >&2
        return 1
    }
    mods="$(modules_of "$name")"
    local -a libs=()
    if [[ -n "$mods" ]]; then
        # Without -r: pkg-config escapes a space inside a path with a backslash,
        # and read turns that back into one word.
        # shellcheck disable=SC2086,SC2162 # module names are a word list on purpose
        read -a libs <<<"$("$PKG_CONFIG_BIN" --cflags --libs $mods)" || return 1
    fi
    mkdir -p "$(dirname "$bin")" || return 1
    # The source is copied first, and the copy is both what gets compiled and
    # what gets hashed: an edit during the compile then shows up as `stale`
    # instead of being stamped onto a binary that does not contain it.
    snap="$(mktemp -d "${TMPDIR:-/tmp}/cpp-helpers.XXXXXX")" || return 1
    TEMPS+=("$snap")
    cp "$src" "$snap/$name.cpp" || return 1
    hash="$(src_hash_of "$name" "$snap/$name.cpp")" || return 1
    tmp="$bin.new.$$"
    TEMPS+=("$tmp" "$stamp.new.$$")
    # Into a temporary file and then renamed: the helper is usually running, and
    # writing over a running executable is ETXTBSY. A failed compile never
    # touches the binary in place.
    if ! "$CXX_BIN" "${CXXFLAGS_FIXED[@]}" -o "$tmp" "$snap/$name.cpp" "${libs[@]}"; then
        printf 'cpp-helpers: %s failed to compile\n' "$name" >&2
        return 1
    fi
    chmod 0755 "$tmp" || return 1
    # The stamp lands before the binary. Interrupted between the two renames,
    # the old binary sits under the new stamp: `replaced`, so it is rebuilt and
    # the choice to build here is never lost. The other order could leave a new
    # binary with no stamp at all, which reads as the committed one.
    printf '%s %s %s\n' "$hash" "$(date -Is)" "$(file_hash "$tmp")" >"$stamp.new.$$" || return 1
    mv -f "$stamp.new.$$" "$stamp" || return 1
    mv -f "$tmp" "$bin" || return 1
}

names_from_args() {
    if (($# > 0)); then
        printf '%s\n' "$@"
        return 0
    fi
    local entry
    for entry in "${HELPERS[@]}"; do printf '%s\n' "${entry%%:*}"; done
}

while (($# > 0)); do
    case "$1" in
    --out-dir) OUT_DIR="${2:?--out-dir needs a directory}"; shift 2 ;;
    --out-dir=*) OUT_DIR="${1#*=}"; shift ;;
    *) break ;;
    esac
done
# Made absolute but not created: asking about a tree that does not exist (a
# first install) must not leave an empty one behind. build and mark-fallback
# create what they write into.
if [[ -n "$OUT_DIR" ]]; then
    if [[ -d "$OUT_DIR" ]]; then
        OUT_DIR="$(cd -P "$OUT_DIR" && pwd)"
    elif [[ "$OUT_DIR" != /* ]]; then
        OUT_DIR="$PWD/$OUT_DIR"
    fi
fi

cmd="${1:-status}"
shift || true
rc=0

case "$cmd" in
list)
    names_from_args
    ;;
path)
    d="$(rel_dir "${1:?helper name required}")" || exit 1
    printf '%s/%s\n' "$d" "$1"
    ;;
dir)
    d="$(rel_dir "${1:?helper name required}")" || exit 1
    printf '%s/%s\n' "$(out_root)" "$d"
    ;;
status)
    while IFS= read -r name; do
        s="$(state_of "$name")" || {
            rc=1
            continue
        }
        printf '%s %s\n' "$name" "$s"
    done < <(names_from_args "$@")
    ;;
outdated)
    while IFS= read -r name; do
        is_outdated "$(state_of "$name")" && printf '%s\n' "$name"
    done < <(names_from_args "$@")
    ;;
check)
    find_tools
    while IFS= read -r name; do
        entry_of "$name" >/dev/null || {
            rc=1
            continue
        }
        m="$(missing_for "$name")"
        if [[ -z "$m" ]]; then
            printf '%s ok\n' "$name"
        else
            printf '%s missing: %s\n' "$name" "$m"
            rc=1
        fi
    done < <(names_from_args "$@")
    ;;
hash)
    src_hash "${1:?helper name required}" || exit 1
    ;;
build)
    find_tools
    while IFS= read -r name; do
        build_one "$name" || rc=1
    done < <(names_from_args "$@")
    ;;
build-outdated)
    find_tools
    while IFS= read -r name; do
        is_outdated "$(state_of "$name")" || continue
        build_one "$name" || rc=1
    done < <(names_from_args "$@")
    ;;
prebuilt)
    while IFS= read -r name; do
        entry_of "$name" >/dev/null || {
            rc=1
            continue
        }
        rm -f "$(stamp_of "$name")"
    done < <(names_from_args "$@")
    printf 'The repository'"'"'s binaries come back with the next update; now: ii-p3drovfx update --force --prebuilt-helpers\n'
    ;;
mark-fallback)
    name="${1:?helper name required}"
    entry_of "$name" >/dev/null || exit 1
    mkdir -p "$(dirname "$(stamp_of "$name")")" || exit 1
    stamp="$(stamp_of "$name")"
    TEMPS+=("$stamp.new.$$")
    printf 'fallback %s\n' "$(date -Is)" >"$stamp.new.$$" || exit 1
    mv -f "$stamp.new.$$" "$stamp" || exit 1
    ;;
*)
    awk '/^# Usage:/{u=1} u&&/^#/{sub(/^# ?/, ""); print; next} u{exit}' "${BASH_SOURCE[0]}"
    exit 2
    ;;
esac

exit "$rc"
