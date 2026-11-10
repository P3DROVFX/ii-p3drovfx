#!/usr/bin/env bash
# Opened in a terminal by the AI plan usage popup when Claude's sign-in has expired.
#
# Claude Code is the only thing allowed to refresh its token (refresh tokens rotate,
# so a second refresher could sign the CLI out). This script only starts Claude Code
# and lets it rewrite its own credentials file; the shell watches that file's mtime.

credentials="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
claude_bin="$(command -v claude || echo "$HOME/.local/bin/claude")"

# Reads expiresAt only; the token itself never leaves the file.
token_valid() {
    python3 - "$credentials" <<'EOF'
import json, sys, time
try:
    oauth = json.load(open(sys.argv[1], encoding="utf-8")).get("claudeAiOauth") or {}
    expires_at = int(oauth.get("expiresAt") or 0)
    ok = bool(oauth.get("accessToken")) and (not expires_at or expires_at > time.time() * 1000 + 60_000)
except Exception:
    ok = False
sys.exit(0 if ok else 1)
EOF
}

if [ ! -x "$claude_bin" ]; then
    echo "Claude Code is not installed."
    read -rp "Press Enter to close." _
    exit 1
fi

# The cheap path: a non-interactive command that may refresh the token on its own.
"$claude_bin" auth status --text >/dev/null 2>&1
if token_valid; then
    echo "Claude sign-in is fresh. The bar updates in a moment."
    sleep 1.5
    exit 0
fi

echo "Starting Claude Code so it can refresh its sign-in."
echo "Once the bar shows fresh numbers, quit with /exit."
echo
cd "$HOME" && exec "$claude_bin"
