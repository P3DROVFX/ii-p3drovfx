#!/usr/bin/env bash
# Enforces the panel-family layering rules. Run from anywhere; resolves its own root.
#
# The tablet family grew on top of the ii family, and every borrowed component was a place
# where a change to the desktop shell could silently break the tablet, or where a tablet
# requirement pushed a parameter into ii that only the tablet ever set. These rules stop
# that from happening again:
#
#   1. qs.services and qs.modules.common must not import ANY panel family. They are shared
#      by all of them; a service that knows about one family cannot be reasoned about
#      without it, and that family can never be deleted. Invert the dependency instead —
#      modules/common/TouchGestureDragRegistry.qml is the worked example.
#
#   2. modules/tablet/ must not import qs.modules.ii.*. Borrowing a desktop component is
#      allowed, but only from panelFamilies/TabletFamily.qml, so the debt is countable in
#      one file. To share a component properly, promote it to modules/common/ first.
#
#   3. modules/ii/ must not import qs.modules.tablet.* or qs.modules.waffle.*, for the same
#      reason as (1) in the other direction.
#
# Known violations are listed in the baseline next to this script, one "file:import" per
# line. They are debt, not permission: the burn-down is tracked in the tablet family plan.
# A violation not in the baseline fails the check; a baseline entry that no longer occurs
# is reported so it gets deleted.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

baseline_file="scripts/dev/panel-family-layering-baseline.txt"

# Collect "path:module" pairs for every rule.
collect() {
    local pattern="$1"; shift
    local dir
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        grep -rn --include='*.qml' -E "$pattern" "$dir" 2>/dev/null | while IFS= read -r line; do
            local path="${line%%:*}"
            local module
            module=$(printf '%s' "$line" | grep -oE 'qs\.modules\.[a-zA-Z0-9_.]+' | head -1)
            [ -n "$module" ] && printf '%s:%s\n' "$path" "$module"
        done
    done
}

current=$(
    {
        collect '^[[:space:]]*import[[:space:]]+qs\.modules\.(ii|tablet|waffle)\b' services modules/common
        collect '^[[:space:]]*import[[:space:]]+qs\.modules\.ii\b' modules/tablet
        collect '^[[:space:]]*import[[:space:]]+qs\.modules\.(tablet|waffle)\b' modules/ii
    } | sort -u
)

baseline=$(grep -vE '^\s*(#|$)' "$baseline_file" 2>/dev/null | sort -u)

new_violations=$(comm -23 <(printf '%s\n' "$current") <(printf '%s\n' "$baseline") | grep -v '^$')
stale_baseline=$(comm -13 <(printf '%s\n' "$current") <(printf '%s\n' "$baseline") | grep -v '^$')

status=0

if [ -n "$new_violations" ]; then
    status=1
    printf '\033[31mNEW LAYERING VIOLATION\033[0m — a family boundary was crossed:\n'
    printf '  %s\n' $new_violations
    printf '\nFix it, or if it is deliberate debt, add the line to %s with a reason.\n' "$baseline_file"
fi

if [ -n "$stale_baseline" ]; then
    printf '\n\033[33mBASELINE IS STALE\033[0m — these no longer occur, delete them from %s:\n' "$baseline_file"
    printf '  %s\n' $stale_baseline
fi

if [ "$status" -eq 0 ] && [ -z "$stale_baseline" ]; then
    remaining=$(printf '%s\n' "$baseline" | grep -c . || true)
    printf '\033[32mOK\033[0m: no new layering violations (%s known, tracked in the baseline).\n' "$remaining"
fi

exit "$status"
