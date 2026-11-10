#!/usr/bin/env bash
# install-net-helper.sh — build and install app_stats_net, the eBPF helper that gives
# the App usage app exact per-app network data.
#
#   install-net-helper.sh            build, then install with sudo
#   install-net-helper.sh status     installed? capabilities set? same build as the sources?
#   install-net-helper.sh uninstall  remove it (the sampler falls back on its own)
#
# Why sudo, once: the kernel only lets a process load eBPF programs and attach them to
# the root cgroup with CAP_BPF, CAP_PERFMON and CAP_NET_ADMIN. Those are granted as
# file capabilities on a root-owned copy, so the helper never runs as root and nothing
# runs at all unless the sampler starts it. Only the wheel group may execute it, since
# it can see every user's per-process traffic.
#
# It is not one of rust-helpers.sh's helpers on purpose: those are rebuilt by the
# updater without asking, and this one cannot be reinstalled without a password.
# Replacing the file drops its capabilities, so every rebuild goes through here.
set -euo pipefail

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SRC="$DIR/app_stats_net_src"
DEST="/usr/local/lib/ii/app_stats_net"
CAPS="cap_bpf,cap_perfmon,cap_net_admin=ep"
# The askpass prompt when one is configured, so this also runs without a terminal.
SUDO=(sudo)
[[ -n "${SUDO_ASKPASS:-}" ]] && SUDO=(sudo -A)

status() {
    if [[ ! -e "$DEST" ]]; then
        echo "not installed"
        return 1
    fi
    local caps
    caps="$(getcap "$DEST" 2>/dev/null || true)"
    echo "installed: $DEST"
    echo "capabilities: ${caps#"$DEST "}"
    if [[ -x "$SRC/target/release/app_stats_net" ]] && cmp -s "$SRC/target/release/app_stats_net" "$DEST"; then
        echo "build: matches $SRC"
    else
        echo "build: differs from the local build (or none) — rerun this script after changing the sources"
    fi
}

case "${1:-install}" in
status)
    status
    ;;
uninstall)
    "${SUDO[@]}" rm -f "$DEST"
    "${SUDO[@]}" rmdir --ignore-fail-on-non-empty "$(dirname "$DEST")" 2>/dev/null || true
    echo "removed $DEST"
    ;;
install)
    command -v cargo >/dev/null || { echo "cargo is not installed" >&2; exit 1; }
    command -v clang >/dev/null || { echo "clang is not installed (needed to compile the eBPF program)" >&2; exit 1; }
    [[ -f /usr/include/bpf/libbpf.h ]] || { echo "libbpf headers are missing (install libbpf)" >&2; exit 1; }
    getent group wheel >/dev/null || { echo "there is no wheel group to restrict the helper to" >&2; exit 1; }
    (cd "$SRC" && cargo build --release)
    "${SUDO[@]}" sh -c "install -d -o root -g root -m 0755 '$(dirname "$DEST")' \
        && install -o root -g wheel -m 0750 '$SRC/target/release/app_stats_net' '$DEST' \
        && setcap '$CAPS' '$DEST'"
    status
    echo "The sampler picks it up the next time it starts (reopen App usage, or toggle network data)."
    ;;
*)
    sed -n '2,8p' "$0"
    exit 2
    ;;
esac
