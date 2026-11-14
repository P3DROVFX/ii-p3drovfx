#!/bin/sh
# Runs a native helper, or its Python twin (<helper>.py) when the binary
# cannot load on this system.
#
#   native_or_python.sh [--probe] [--py-flag FLAG]... <helper> [args...]
#
# The helpers are prebuilt on a recent glibc/libstdc++. On an older distro,
# a musl system or NixOS (no /lib64 loader) they fail before main(), which
# would silently kill the feature. The loader is asked to resolve the binary
# (LD_TRACE_LOADED_OBJECTS: it maps the libraries and checks symbol versions
# without running main) and anything "not found" means it cannot run.
#
# The verdict is cached per binary (path + mtime + size) under
# $XDG_RUNTIME_DIR, so polled helpers pay the probe once per boot/update.
# Both branches exec, so no shell stays between Quickshell and the helper and
# a parent-death signal set by the caller still applies.
#
# --probe: exit 0 if the native binary is usable, 1 otherwise; runs nothing.

probe_only=0
py_flags=""
while [ $# -gt 0 ]; do
    case "$1" in
        --probe) probe_only=1; shift ;;
        --py-flag) py_flags="$py_flags $2"; shift 2 ;;
        *) break ;;
    esac
done

bin="$1"
[ -n "$bin" ] || { echo "native_or_python.sh: no helper given" >&2; exit 2; }
shift

native_ok() {
    [ -f "$bin" ] && [ -x "$bin" ] || return 1
    cache_dir="${XDG_RUNTIME_DIR:-/tmp}/ii-native-probe"
    stamp="$(stat -c '%Y-%s' "$bin" 2>/dev/null)" || return 1
    key="$(printf '%s' "$bin" | tr '/' '_')-$stamp"
    [ -e "$cache_dir/$key.ok" ] && return 0
    [ -e "$cache_dir/$key.bad" ] && return 1
    mkdir -p "$cache_dir" 2>/dev/null
    out="$(LD_TRACE_LOADED_OBJECTS=1 "$bin" 2>&1 </dev/null)"
    if [ $? -eq 0 ] && ! printf '%s' "$out" | grep -q 'not found'; then
        : >"$cache_dir/$key.ok" 2>/dev/null
        return 0
    fi
    : >"$cache_dir/$key.bad" 2>/dev/null
    # Once per binary version: say why the Python fallback is in use.
    msg="native helper ${bin##*/} cannot load, using ${bin##*/}.py: $(printf '%s' "$out" | grep -m1 -E 'not found|No such')"
    if command -v logger >/dev/null 2>&1; then
        logger -t quickshell-ii "$msg"
    else
        echo "quickshell-ii: $msg" >&2
    fi
    return 1
}

if native_ok; then
    [ "$probe_only" -eq 1 ] && exit 0
    exec "$bin" "$@"
fi
[ "$probe_only" -eq 1 ] && exit 1

if [ -f "$bin.py" ] && command -v python3 >/dev/null 2>&1; then
    # shellcheck disable=SC2086 # py_flags is a list of single-word flags
    exec python3 $py_flags "$bin.py" "$@"
fi
# No fallback available: run the binary anyway so its own error is reported.
exec "$bin" "$@"
