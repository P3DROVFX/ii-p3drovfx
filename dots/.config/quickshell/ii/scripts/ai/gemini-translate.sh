#!/usr/bin/env bash
# Usage: gemini-translate.sh <target_locale> [model]
# The model picks the provider: gemini-* uses the Gemini API key, claude-* the
# signed-in `claude` CLI (Claude plan). Progress lines are documented in
# gemini-translate-batch.py.

if [[ -z "$1" ]]; then
    echo "Usage: $0 <target_locale> [model]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
TRANSLATIONS_DIR="${SCRIPT_DIR}/../../translations"
SOURCE_LOCALE="en_US"
NOTIFICATION_APP_NAME="Shell"
TARGET_LOCALE="$1"
MODEL="${2:-${GEMINI_MODEL:-gemini-3.8-flash}}"

# Refresh the source keys first; its chatter goes to stderr so stdout stays parseable.
"${TRANSLATIONS_DIR}/tools/manage-translations.sh" update -l "$SOURCE_LOCALE" --yes >&2

python3 "${SCRIPT_DIR}/gemini-translate-batch.py" \
    "${TRANSLATIONS_DIR}/${SOURCE_LOCALE}.json" \
    "${TRANSLATIONS_DIR}/${TARGET_LOCALE}.json" \
    "$TARGET_LOCALE" \
    --model "$MODEL" \
    --batch-size 300 &
child=$!
# Cancel from Settings: stop the translator (it kills its own request) and exit quietly.
trap 'kill -TERM "$child" 2>/dev/null; wait "$child"; exit 130' TERM INT
wait "$child"
status=$?

if [[ $status -eq 0 ]]; then
    jq --arg locale "$TARGET_LOCALE" '.language.ui = $locale' "$SHELL_CONFIG_FILE" > "${SHELL_CONFIG_FILE}.tmp" \
        && cat "${SHELL_CONFIG_FILE}.tmp" > "$SHELL_CONFIG_FILE" && rm -f "${SHELL_CONFIG_FILE}.tmp"
    notify-send "Translation complete" "The file is in translations/${TARGET_LOCALE}.json if you want to refine it." -a "$NOTIFICATION_APP_NAME"
elif [[ $status -eq 2 ]]; then
    notify-send "Translation incomplete" "Some strings failed. Run it again to retry only the missing ones." -a "$NOTIFICATION_APP_NAME"
else
    notify-send "Translation failed" "Open Settings → Language & Time for details." -a "$NOTIFICATION_APP_NAME"
fi
exit $status
