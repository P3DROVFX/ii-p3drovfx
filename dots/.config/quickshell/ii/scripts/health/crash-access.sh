#!/usr/bin/env bash
# crash-access.sh — let one user read the core dumps of system programs.
#
# systemd-coredump keeps dumps of programs that ran as root readable by root
# only. System Health shows those crashes from the journal either way; this
# grants one account read access to the dumps themselves, so they can be
# debugged with `coredumpctl gdb` without sudo.
#
# A core dump is a full copy of a program's memory at the moment it crashed.
# A root program's dump can hold passwords, keys or fingerprint templates. The
# grant is per user, never for a group, and `revoke` takes it back completely.
#
# Usage (grant and revoke run as root, through pkexec or sudo):
#   crash-access.sh grant <user>    write the tmpfiles rule and apply it
#   crash-access.sh revoke <user>   delete the rule and strip the ACL entries
#   crash-access.sh status <user>   print "granted" or "denied" (any user may run it)
set -euo pipefail

DIR=/var/lib/systemd/coredump
CONF=/etc/tmpfiles.d/ii-system-health.conf

die() {
    printf 'crash-access: %s\n' "$1" >&2
    exit "${2:-1}"
}

valid_user() {
    local user="$1"
    [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
    getent passwd "$user" >/dev/null 2>&1
}

status() {
    local user="$1" acl
    acl="$(getfacl -p --omit-header "$DIR" 2>/dev/null || true)"
    if grep -q "^user:${user}:r" <<<"$acl" && grep -q "^default:user:${user}:r" <<<"$acl"; then
        echo granted
    else
        echo denied
    fi
}

need_root() {
    [[ "$(id -u)" -eq 0 ]] || die "must run as root (pkexec or sudo)" 3
}

grant() {
    local user="$1"
    need_root
    command -v setfacl >/dev/null || die "setfacl not found (install the acl package)" 4
    [[ -d "$DIR" ]] || mkdir -p "$DIR"
    local tmp
    tmp="$(mktemp "${CONF}.XXXXXX")"
    {
        echo "# Written by System Health (ii shell): lets ${user} read core dumps of system programs."
        echo "# Remove with: crash-access.sh revoke ${user}"
        echo "A+ ${DIR} - - - - u:${user}:rX,d:u:${user}:r"
    } >"$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "$CONF"
    systemd-tmpfiles --create "$CONF"
    status "$user"
}

revoke() {
    local user="$1"
    need_root
    rm -f "$CONF"
    if command -v setfacl >/dev/null && [[ -d "$DIR" ]]; then
        setfacl -R -x "u:${user}" "$DIR" 2>/dev/null || true
        setfacl -d -x "u:${user}" "$DIR" 2>/dev/null || true
    fi
    status "$user"
}

[[ $# -eq 2 ]] || die "usage: crash-access.sh grant|revoke|status <user>" 2
action="$1"
user="$2"
valid_user "$user" || die "not a valid local user: ${user}" 2

case "$action" in
grant) grant "$user" ;;
revoke) revoke "$user" ;;
status) status "$user" ;;
*) die "unknown action: ${action}" 2 ;;
esac
