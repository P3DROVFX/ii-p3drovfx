#!/usr/bin/env python3
"""
widget_extensions.py — helper script for WidgetExtensionManager.qml

Commands:
  install <url_or_path> <dest_dir>   → git clone or symlink-style local install
  list    <widgets_dir>              → list installed widgets (for migration)

Output is always a single JSON line to stdout.
"""
import os
import sys
import json
import subprocess
import re


def eprint(*args):
    print(*args, file=sys.stderr)


def ext_id_from_url(url: str) -> str:
    """Derive widget ID from a GitHub URL or local path."""
    clean = url.rstrip("/").replace(".git", "")
    return clean.split("/")[-1]


def is_local_path(s: str) -> bool:
    return s.startswith("/") or s.startswith("~/") or s.startswith("file://")


def resolve_local(s: str) -> str:
    if s.startswith("file://"):
        s = s[7:]
    return os.path.expanduser(s)


def get_component(wj: dict) -> str:
    """Get the component file path from widget.json, handling both flat and nested schemas."""
    # Flat schema: { "component": "Widget.qml" }
    if "component" in wj:
        return wj["component"]
    # Nested schema: { "widget": { "component": "Widget.qml" } }
    if "widget" in wj and isinstance(wj["widget"], dict):
        return wj["widget"].get("component", "main.qml")
    return "main.qml"


def validate_widget_json(path: str) -> dict:
    """Read and minimally validate widget.json. Returns normalized dict or raises."""
    with open(path, "r", encoding="utf-8") as f:
        wj = json.load(f)
    if "name" not in wj:
        raise ValueError("widget.json missing required field: name")
    # Accept either flat 'component' or nested 'widget.component'
    component = get_component(wj)
    if not component:
        raise ValueError("widget.json missing required field: component (or widget.component)")
    # Normalize to flat schema for internal use
    wj["_component"] = component
    return wj


def cmd_install(url_or_path: str, dest_dir: str):
    os.makedirs(dest_dir, exist_ok=True)

    if is_local_path(url_or_path):
        # Local install — just register the path, no copying
        local_path = resolve_local(url_or_path)
        if not os.path.isdir(local_path):
            print(json.dumps({"status": "error", "error": f"Path not found: {local_path}"}))
            return
        widget_json_path = os.path.join(local_path, "widget.json")
        if not os.path.exists(widget_json_path):
            print(json.dumps({"status": "error", "error": "widget.json not found in directory"}))
            return
        try:
            validate_widget_json(widget_json_path)
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return

        ext_id = ext_id_from_url(local_path)
        print(json.dumps({
            "status": "ok",
            "extId": ext_id,
            "installedPath": local_path,
            "isLocal": True
        }))
        return

    # GitHub / git URL install
    ext_id = ext_id_from_url(url_or_path)
    # Sanitize: only allow safe characters in the ext_id / directory name
    if not re.match(r'^[a-zA-Z0-9_\-]+$', ext_id):
        print(json.dumps({"status": "error", "error": f"Invalid repository name: {ext_id}"}))
        return

    installed_path = os.path.join(dest_dir, ext_id)

    if os.path.isdir(installed_path):
        # Already cloned — re-register (idempotent)
        widget_json_path = os.path.join(installed_path, "widget.json")
        if not os.path.exists(widget_json_path):
            print(json.dumps({"status": "error", "error": "widget.json not found after clone"}))
            return
        try:
            validate_widget_json(widget_json_path)
        except Exception as e:
            print(json.dumps({"status": "error", "error": str(e)}))
            return
        print(json.dumps({
            "status": "ok",
            "extId": ext_id,
            "installedPath": installed_path,
            "isLocal": False
        }))
        return

    # Support shorthand "user/repo" format — expand to full GitHub URL
    if re.match(r'^[a-zA-Z0-9_\-]+/[a-zA-Z0-9_\-]+$', url_or_path):
        url_or_path = f"https://github.com/{url_or_path}"

    # Ensure URL is a valid https://, git@, or git:// URL (basic safety check)
    if not (url_or_path.startswith("https://") or url_or_path.startswith("git@") or url_or_path.startswith("git://")):
        print(json.dumps({"status": "error", "error": "URL must start with https://, git@, or git://"}))
        return

    def _https_to_ssh(url):
        """Convert HTTPS GitHub URL to SSH format."""
        # https://github.com/user/repo -> git@github.com:user/repo
        m = re.match(r'^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$', url)
        if m:
            return f"git@github.com:{m.group(1)}/{m.group(2)}.git"
        return None

    def _ssh_to_https(url):
        """Convert SSH GitHub URL to HTTPS format."""
        # git@github.com:user/repo.git -> https://github.com/user/repo
        m = re.match(r'^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$', url)
        if m:
            return f"https://github.com/{m.group(1)}/{m.group(2)}"
        return None

    def _try_clone(clone_url, target):
        """Attempt a shallow clone. Returns (success, error_msg)."""
        try:
            result = subprocess.run(
                ["git", "clone", "--depth", "1", clone_url, target],
                capture_output=True, text=True, timeout=120
            )
            if result.returncode != 0:
                return False, result.stderr.strip() or "git clone failed"
            return True, ""
        except subprocess.TimeoutExpired:
            return False, "git clone timed out"
        except Exception as e:
            return False, str(e)

    # Try primary URL, then fallback to alternate protocol (SSH <-> HTTPS)
    urls_to_try = [url_or_path]
    if url_or_path.startswith("https://"):
        alt = _https_to_ssh(url_or_path)
        if alt:
            urls_to_try.append(alt)
    elif url_or_path.startswith("git@"):
        alt = _ssh_to_https(url_or_path)
        if alt:
            urls_to_try.append(alt)

    clone_ok = False
    clone_err = ""
    for attempt_url in urls_to_try:
        clone_ok, clone_err = _try_clone(attempt_url, installed_path)
        if clone_ok:
            break
        # Clean up failed attempt before trying next
        if os.path.isdir(installed_path):
            subprocess.run(["rm", "-rf", installed_path])

    if not clone_ok:
        print(json.dumps({"status": "error", "error": clone_err}))
        return

    widget_json_path = os.path.join(installed_path, "widget.json")
    if not os.path.exists(widget_json_path):
        # Clean up the clone if widget.json missing
        subprocess.run(["rm", "-rf", installed_path])
        print(json.dumps({"status": "error", "error": "widget.json not found at repository root"}))
        return

    try:
        validate_widget_json(widget_json_path)
    except Exception as e:
        subprocess.run(["rm", "-rf", installed_path])
        print(json.dumps({"status": "error", "error": str(e)}))
        return

    print(json.dumps({
        "status": "ok",
        "extId": ext_id,
        "installedPath": installed_path,
        "isLocal": False
    }))


def cmd_list(widgets_dir: str):
    """Legacy list command (used by old list_user_widgets.py callers)."""
    if not os.path.isdir(widgets_dir):
        print(json.dumps([]))
        return

    results = []
    for item in os.listdir(widgets_dir):
        item_path = os.path.join(widgets_dir, item)
        if not os.path.isdir(item_path):
            continue
        wj_path = os.path.join(item_path, "widget.json")
        if not os.path.exists(wj_path):
            # Legacy support: try metadata.json
            meta_path = os.path.join(item_path, "metadata.json")
            if os.path.exists(meta_path):
                try:
                    with open(meta_path, "r", encoding="utf-8") as f:
                        meta = json.load(f)
                    widget_id = meta.get("widgetId", item)
                    qml_entry = meta.get("qmlEntry", "main.qml")
                    qml_path = os.path.join(item_path, qml_entry)
                    if os.path.exists(qml_path):
                        results.append({
                            "widgetId":    "ext:" + widget_id,
                            "name":        meta.get("name", item.replace("_", " ").title()),
                            "category":    meta.get("category", "Utility"),
                            "qmlPath":     "file://" + qml_path,
                            "icon":        meta.get("icon", "extension"),
                            "description": meta.get("description", ""),
                            "isExtension": True,
                            "extId":       widget_id
                        })
                except Exception as e:
                    eprint(f"Error reading metadata.json for {item}: {e}")
            continue

        try:
            wj = validate_widget_json(wj_path)
        except Exception as e:
            eprint(f"Error validating widget.json for {item}: {e}")
            continue

        qml_entry = wj.get("component", "main.qml")
        qml_path = os.path.join(item_path, qml_entry)
        if not os.path.exists(qml_path):
            eprint(f"QML file not found for {item}: {qml_path}")
            continue

        results.append({
            "widgetId":    "ext:" + item,
            "name":        wj.get("name", item.replace("-", " ").title()),
            "category":    wj.get("category", "Utility"),
            "qmlPath":     "file://" + qml_path,
            "icon":        wj.get("icon", "extension"),
            "description": wj.get("description", ""),
            "isExtension": True,
            "extId":       item
        })

    print(json.dumps(results))


def cmd_backup(ext_id: str, source_path: str, backups_dir: str):
    """Create a timestamped backup of a widget before update."""
    import shutil
    import time
    os.makedirs(backups_dir, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    backup_name = f"{ext_id}-{timestamp}"
    backup_path = os.path.join(backups_dir, backup_name)
    try:
        shutil.copytree(source_path, backup_path)
        print(json.dumps({"status": "ok", "backupPath": backup_path}))
    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}))


def cmd_update(target_path: str):
    """Run git pull --ff-only in a widget directory."""
    try:
        result = subprocess.run(
            ["git", "-C", target_path, "pull", "--ff-only"],
            capture_output=True, text=True, timeout=120
        )
        if result.returncode != 0:
            print(json.dumps({"status": "error", "error": result.stderr.strip() or "git pull failed"}))
            return
        # Re-validate widget.json after pull
        wj_path = os.path.join(target_path, "widget.json")
        try:
            wj = validate_widget_json(wj_path)
        except Exception as e:
            print(json.dumps({"status": "error", "error": f"widget.json invalid after update: {e}"}))
            return
        print(json.dumps({"status": "ok", "version": wj.get("version", "")}))
    except subprocess.TimeoutExpired:
        print(json.dumps({"status": "error", "error": "git pull timed out"}))
    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}))


def cmd_discover(per_page: int = 30):
    """Search GitHub for repositories tagged with topic 'ii-desktop-widget'."""
    import urllib.request
    import urllib.error

    url = (
        f"https://api.github.com/search/repositories"
        f"?q=topic:ii-desktop-widget&sort=stars&order=desc&per_page={per_page}"
    )
    req = urllib.request.Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "ii-widget-discover/1.0",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw = resp.read().decode("utf-8")
        data = json.loads(raw)
        items = data.get("items", [])
        results = []
        for repo in items:
            results.append({
                "name":        repo.get("name", ""),
                "fullName":    repo.get("full_name", ""),
                "description": repo.get("description") or "",
                "stars":       repo.get("stargazers_count", 0),
                "author":      repo.get("owner", {}).get("login", ""),
                "avatarUrl":   repo.get("owner", {}).get("avatar_url", ""),
                "repoUrl":     repo.get("html_url", ""),
                "cloneUrl":    repo.get("clone_url", ""),
                "updatedAt":   repo.get("updated_at", ""),
            })
        print(json.dumps({"status": "ok", "results": results}))
    except urllib.error.URLError as e:
        print(json.dumps({"status": "error", "error": f"Network error: {e.reason}"}))
    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "error": "No command given"}))
        sys.exit(1)

    command = sys.argv[1]

    if command == "install":
        if len(sys.argv) < 4:
            print(json.dumps({"status": "error", "error": "Usage: install <url_or_path> <dest_dir>"}))
            sys.exit(1)
        cmd_install(sys.argv[2], sys.argv[3])

    elif command == "list":
        if len(sys.argv) < 3:
            print(json.dumps([]))
        else:
            cmd_list(sys.argv[2])

    elif command == "backup":
        if len(sys.argv) < 5:
            print(json.dumps({"status": "error", "error": "Usage: backup <ext_id> <source_path> <backups_dir>"}))
            sys.exit(1)
        cmd_backup(sys.argv[2], sys.argv[3], sys.argv[4])

    elif command == "update":
        if len(sys.argv) < 3:
            print(json.dumps({"status": "error", "error": "Usage: update <target_path>"}))
            sys.exit(1)
        cmd_update(sys.argv[2])

    elif command == "discover":
        per_page = int(sys.argv[2]) if len(sys.argv) > 2 else 30
        cmd_discover(per_page)

    else:
        print(json.dumps({"status": "error", "error": f"Unknown command: {command}"}))
        sys.exit(1)
