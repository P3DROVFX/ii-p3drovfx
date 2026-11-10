#!/usr/bin/env python3
"""Print "companion" when a Discord client actually loads the iiDiscordVoice plugin.

Checks what vencord-companion/install.sh writes, not what it builds: the plugin
enabled in the client's Vencord settings and, for Vesktop/Equibop, the client
pointed at the custom build that contains it. A build left in
~/.local/share/quickshell-ii by an install the client never picked up does not count.
"""

import json
import os

HOME = os.path.expanduser("~")

# (Vencord settings, client state file, key pointing the client at the build)
CLIENTS = [
    (".config/vesktop/settings/settings.json", ".config/vesktop/state.json", "vencordDir"),
    (".config/equibop/settings/settings.json", ".config/equibop/state.json", "equicordDir"),
    (".config/Vencord/settings/settings.json", None, None),
]


def load(path):
    try:
        with open(os.path.join(HOME, path)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


for settings, state, key in CLIENTS:
    plugin = (load(settings).get("plugins") or {}).get("iiDiscordVoice") or {}
    if plugin.get("enabled") is True and (state is None or load(state).get(key)):
        print("companion")
        break
