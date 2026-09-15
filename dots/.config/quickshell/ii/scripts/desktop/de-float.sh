#!/usr/bin/env bash
# Float every window on screen in place, keeping its size intact.

set -uo pipefail

hyprctl -j clients 2>/dev/null | jq -r '
    .[]
    | select((.floating // false) == false)
    | select((.workspace.id // 0) > 0)
    | .address
' | while IFS= read -r addr; do
    [ -n "$addr" ] || continue
    hyprctl dispatch float "address:$addr" >/dev/null 2>&1
done

exit 0