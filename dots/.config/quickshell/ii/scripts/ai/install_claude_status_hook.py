#!/usr/bin/env python3
"""Install (or remove) the island's Claude Code status hooks.

Writes into `~/.claude/settings.json`, which is the user's own file and usually already
has hooks in it, so every entry is merged rather than replaced and the file is backed up
first. Running it twice changes nothing.

    python3 install_claude_status_hook.py           # install
    python3 install_claude_status_hook.py --remove  # take them out again
    python3 install_claude_status_hook.py --check   # say what is installed, change nothing
"""
import json
import os
import shutil
import sys
import time

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude_status_hook.py")
SETTINGS = os.path.expanduser("~/.claude/settings.json")

# Every event the island needs to tell working from waiting from asking. The tool events
# carry a matcher because Claude Code groups them by tool; "*" is every tool.
EVENTS = {
    "SessionStart": None,
    "UserPromptSubmit": None,
    "PreToolUse": "*",
    "PostToolUse": "*",
    "Notification": None,
    "Stop": None,
    # A turn that ends badly (an error, a cancelled request) reports through this one;
    # an Escape reports through neither, which is why the monitor also reads the
    # transcript for the interruption the CLI records there.
    "StopFailure": None,
    "SubagentStop": None,
    "PreCompact": None,
    "SessionEnd": None,
}


def command():
    return "python3 %s" % HOOK


def is_ours(entry):
    for hook in entry.get("hooks", []) or []:
        if "claude_status_hook.py" in str(hook.get("command", "")):
            return True
    return False


def load():
    if not os.path.isfile(SETTINGS):
        return {}
    with open(SETTINGS, "r") as handle:
        return json.load(handle)


def save(settings):
    backup = SETTINGS + ".bak-" + time.strftime("%Y%m%d-%H%M%S")
    if os.path.isfile(SETTINGS):
        shutil.copy2(SETTINGS, backup)
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(settings, handle, indent=2)
        handle.write("\n")
    os.replace(tmp, SETTINGS)
    return backup if os.path.isfile(SETTINGS) else ""


def install(settings):
    hooks = settings.setdefault("hooks", {})
    added = []
    for event, matcher in EVENTS.items():
        entries = hooks.setdefault(event, [])
        if any(is_ours(entry) for entry in entries):
            continue
        entry = {
            "hooks": [{
                "type": "command",
                "command": command(),
                # Nothing waits on a status light: the hook runs beside the turn rather
                # than in front of it, so a tool call is never slowed by it.
                "async": True,
                "timeout": 5,
            }]
        }
        if matcher:
            entry["matcher"] = matcher
        entries.append(entry)
        added.append(event)
    return added


def remove(settings):
    hooks = settings.get("hooks", {})
    dropped = []
    for event in list(hooks.keys()):
        kept = [entry for entry in hooks[event] if not is_ours(entry)]
        if len(kept) != len(hooks[event]):
            dropped.append(event)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    return dropped


def check(settings):
    hooks = settings.get("hooks", {})
    return sorted(event for event, entries in hooks.items()
                  if any(is_ours(entry) for entry in entries))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--install"
    try:
        settings = load()
    except ValueError as error:
        print("~/.claude/settings.json is not valid JSON (%s); not touching it." % error)
        return 1

    if mode == "--check":
        installed = check(settings)
        print("installed for: " + (", ".join(installed) if installed else "(nothing)"))
        return 0

    if mode == "--remove":
        dropped = remove(settings)
        if not dropped:
            print("nothing to remove")
            return 0
        save(settings)
        print("removed from: " + ", ".join(dropped))
        return 0

    if not os.path.isfile(HOOK):
        print("hook script missing: " + HOOK)
        return 1
    added = install(settings)
    if not added:
        print("already installed")
        return 0
    backup = save(settings)
    print("installed for: " + ", ".join(added))
    if backup:
        print("backup: " + backup)
    print("Open /hooks once (or restart the CLI) so Claude Code re-reads its settings.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
