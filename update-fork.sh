#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
UPDATER="$SCRIPT_DIR/update-with-customs.sh"

echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
echo '  Your fork: Checking for conflicts (dry-run)...'
echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
echo ''

if bash "$UPDATER" --dry-run -v; then
  echo ''
  echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  echo '  No conflicts! Applying update...'
  echo '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
  echo ''
  bash "$UPDATER" -v
else
  echo ''
  echo '⚠ Conflicts or errors detected.'
  echo '  Update NOT applied.'
fi

echo ''
echo 'Press Enter to close...'
read
