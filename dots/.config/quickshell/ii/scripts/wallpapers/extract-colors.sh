#!/bin/bash

TARGET_DIR="${1:-$HOME/Pictures/Wallpapers}"

[ ! -d "$TARGET_DIR" ] && exit 1

OUTPUT_DIR="$HOME/.cache/quickshell/wallpapers"
OUTPUT_FILE="$OUTPUT_DIR/colors.json"
mkdir -p "$OUTPUT_DIR"

source "$(dirname "${BASH_SOURCE[0]}")/../colors/matugen.sh"
# Resolve once here so the background jobs below don't each probe the binaries
matugen_resolve
# Builds without --source-color-index only ever return the first colour
color_indices=(0)
[[ "$MATUGEN_HAS_SOURCE_INDEX" == 1 ]] && color_indices=(0 1 2)

PGID=$(ps -o pgid= $$ | tr -d ' ')
trap 'kill -- -$PGID 2>/dev/null' INT TERM
trap 'rm -f "$temp_results"' EXIT

if ! EXISTING_JSON=$(cat "$OUTPUT_FILE" 2>/dev/null); then
    EXISTING_JSON="{}"
fi

echo "$EXISTING_JSON" | jq . >/dev/null 2>&1 || EXISTING_JSON="{}"

declare -A CACHED_KEYS
while IFS= read -r key; do
    CACHED_KEYS["$key"]=1
done < <(echo "$EXISTING_JSON" | jq -r 'keys[]')

TOTAL=$(find "$TARGET_DIR" -maxdepth 2 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" \) | wc -l)

temp_results=$(mktemp)
processed=${#CACHED_KEYS[@]}

is_cached() {
    [[ -v CACHED_KEYS["$1"] ]]
}

flush_results() {
    [ -s "$temp_results" ] || return
    local merged
    merged=$(jq -s 'add' <(echo "$EXISTING_JSON") "$temp_results") || return
    echo "$merged" > "$OUTPUT_FILE"
    EXISTING_JSON="$merged"
    > "$temp_results"
    echo "$processed/$TOTAL"
}

process_img() {
    img=$1
    tmp=$2

    is_cached "$img" && return

    colors=()

    for i in "${color_indices[@]}"; do
        c=$(matugen image "$img" \
            --json hex \
            --source-color-index "$i" \
            --dry-run --quiet 2>/dev/null \
            | jq -r '.colors.source_color.default.color')

        [ -n "$c" ] && colors+=("$c")
    done

    [ ${#colors[@]} -eq 0 ] && return

    jq -n --arg key "$img" \
          --argjson val "$(printf '%s\n' "${colors[@]}" | jq -R . | jq -s .)" \
          '{($key): $val}' >> "$tmp"
}

count=0

while IFS= read -r -d '' img; do
    process_img "$img" "$temp_results" &

    count=$((count + 1))
    processed=$((processed + 1))

    if [ $((count % 15)) -eq 0 ]; then
        wait
        flush_results
        count=0
    fi
done < <(find "$TARGET_DIR" -maxdepth 2 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.webp" \) -print0)

wait
flush_results

echo "done: $processed/$TOTAL"