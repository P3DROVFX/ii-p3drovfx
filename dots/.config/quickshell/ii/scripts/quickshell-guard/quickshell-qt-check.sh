#!/usr/bin/env bash
# quickshell-qt-check.sh — run by the pacman hook ii-quickshell-qt.hook, as root,
# after Qt or Quickshell was installed or upgraded.
#
# Installed as /usr/local/lib/ii/quickshell-qt-check by install-hook.sh. When the
# installed Quickshell was built against another Qt it says so in pacman's output,
# and on every running Hyprland session: the running shell keeps the old Qt loaded
# and works until it is restarted, so the moment to rebuild is now, before a
# logout or a reboot leaves a shell that may not start.

set -u

command -v quickshell >/dev/null 2>&1 || exit 0
out="$(quickshell --private-check-compat 2>&1)" && exit 0
out="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$out")"

built="" installed=""
[[ "$out" =~ built\ against\ Qt\ ([0-9.]+) ]] && built="${BASH_REMATCH[1]}"
[[ "$out" =~ updated\ to\ Qt\ ([0-9.]+) ]] && installed="${BASH_REMATCH[1]}"
what="Quickshell does not match the installed Qt."
[[ -n "$built" && -n "$installed" ]] && what="Quickshell was built for Qt $built, but Qt $installed is now installed."
# Shown to the user, who reads ~ as their own home; root's $HOME would be wrong.
# shellcheck disable=SC2088
rebuild="~/.config/quickshell/ii/scripts/quickshell-guard/qs-rebuild.sh"

printf '\n'
printf '  ==> WARNING: Quickshell needs a rebuild\n'
printf '      %s\n' "$what"
printf '      Rebuild it before you log out or reboot, or the shell may not start:\n'
printf '        %s\n\n' "$rebuild"

# Hyprland draws these itself; no notification daemon is involved. A socket left
# behind by an old session just refuses the connection.
for sock in /run/user/*/hypr/*/.socket.sock; do
    [[ -S "$sock" ]] || continue
    sig="$(basename "$(dirname "$sock")")"
    uid="$(stat -c %u "$sock")"
    user="$(id -nu "$uid" 2>/dev/null)" || continue
    runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
        hyprctl notify 0 600000 0 "fontsize:15 $what Rebuild it before you log out or reboot: $rebuild" \
        >/dev/null 2>&1 || true
done
exit 0
