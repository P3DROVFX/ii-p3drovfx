#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import threading
import time
import argparse
import re
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "illogical-impulse" / "phone" / "apps"

class ScrcpySessionManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.processes = {}  # session_id -> subprocess.Popen
        self.session_info = {} # session_id -> dict
        self.running = True

    def emit(self, event_data):
        try:
            print(json.dumps(event_data), flush=True)
        except Exception as e:
            sys.stderr.write(f"Error emitting event: {e}\n")

    def resolve_adb_target(self, target_args=None):
        try:
            res = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=4)
            usb_devices = []
            ip_devices = []
            for line in res.stdout.splitlines():
                line = line.strip()
                if not line or line.startswith("List of"):
                    continue
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "device":
                    serial = parts[0]
                    if ":" in serial:
                        ip_devices.append(serial)
                    else:
                        usb_devices.append(serial)

            if usb_devices:
                return ["-s", usb_devices[0]]
            if ip_devices:
                return ["-s", ip_devices[0]]
        except Exception:
            pass

        return target_args or []

    def list_apps(self, target_args=None, device_id="default"):
        target_args = self.resolve_adb_target(target_args)
        cmd = ["scrcpy"] + target_args + ["--list-apps"]

        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            stdout_lines = res.stdout.splitlines()
            stderr_lines = res.stderr.splitlines()
            all_lines = stdout_lines + stderr_lines

            apps = []
            pattern = re.compile(r"^\s*([\*\-])\s+(.+?)\s+([a-zA-Z0-9_]+\.[a-zA-Z0-9_\.]+)\s*$")
            for line in all_lines:
                match = pattern.match(line)
                if match:
                    symbol, name, pkg = match.groups()
                    apps.append({
                        "package": pkg.strip(),
                        "name": name.strip(),
                        "system": (symbol == "*")
                    })

            # If scrcpy --list-apps yielded no apps, try fallback adb pm list packages
            device_ok = True
            if not apps:
                adb_cmd = ["adb"] + target_args + ["shell", "pm", "list", "packages", "-3"]
                res_adb = subprocess.run(adb_cmd, capture_output=True, text=True, timeout=8)
                device_ok = res_adb.returncode == 0
                if device_ok:
                    for line in res_adb.stdout.splitlines():
                        line = line.strip()
                        if line.startswith("package:"):
                            pkg = line[8:].strip()
                            name = pkg.split(".")[-1].capitalize()
                            apps.append({
                                "package": pkg,
                                "name": name,
                                "system": False
                            })

            # A phone that dropped off ADB is an error, not an empty catalog.
            # Reporting it as an empty list would wipe the app list already on
            # screen and leave the user with a bare "no apps found".
            if not apps and not device_ok:
                self.emit({
                    "event": "apps_error",
                    "message": "Phone not reachable over ADB"
                })
                return

            # Deduplicate by package
            seen_pkgs = set()
            unique_apps = []
            for a in apps:
                if a["package"] not in seen_pkgs:
                    seen_pkgs.add(a["package"])
                    unique_apps.append(a)

            unique_apps.sort(key=lambda x: x["name"].lower())

            # Save cache
            try:
                CACHE_DIR.mkdir(parents=True, exist_ok=True)
                cache_file = CACHE_DIR / f"{device_id}.json"
                cache_data = {
                    "deviceId": device_id,
                    "generatedAt": int(time.time()),
                    "apps": unique_apps
                }
                cache_file.write_text(json.dumps(cache_data), encoding='utf-8')
            except Exception as e:
                sys.stderr.write(f"Cache write error: {e}\n")

            self.emit({
                "event": "apps_list",
                "deviceId": device_id,
                "apps": unique_apps
            })

        except Exception as e:
            self.emit({
                "event": "apps_error",
                "message": f"Failed to list apps: {e}"
            })

    def launch_session(self, session_id, type_str, target_args, extra_args):
        with self.lock:
            if session_id in self.processes:
                proc = self.processes[session_id]
                if proc.poll() is None:
                    # Already running, focus window
                    self.focus_session(session_id)
                    self.emit({
                        "event": "started",
                        "id": session_id,
                        "pid": proc.pid,
                        "alreadyRunning": True
                    })
                    return

        title = f"ii-phone-{type_str}-{session_id.replace(':', '_')}"
        resolved_target = self.resolve_adb_target(target_args)
        cmd = ["scrcpy"] + resolved_target + ["--window-title=" + title] + (extra_args or [])

        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            with self.lock:
                self.processes[session_id] = proc
                self.session_info[session_id] = {
                    "id": session_id,
                    "type": type_str,
                    "title": title,
                    "pid": proc.pid,
                    "startedAt": int(time.time())
                }

            self.emit({
                "event": "started",
                "id": session_id,
                "pid": proc.pid,
                "title": title
            })

            # Monitor process exit in a thread
            t = threading.Thread(target=self._wait_process, args=(session_id, proc), daemon=True)
            t.start()

        except Exception as e:
            self.emit({
                "event": "error",
                "id": session_id,
                "message": f"Failed to launch scrcpy: {e}"
            })

    def _wait_process(self, session_id, proc):
        code = proc.wait()
        err_msg = ""
        try:
            stderr_output = proc.stderr.read()
            if stderr_output:
                err_msg = stderr_output.strip().splitlines()[-1] if stderr_output.strip() else ""
        except Exception:
            pass

        with self.lock:
            if session_id in self.processes:
                del self.processes[session_id]
            if session_id in self.session_info:
                del self.session_info[session_id]

        self.emit({
            "event": "exited",
            "id": session_id,
            "code": code,
            "error": err_msg
        })

    def stop_session(self, session_id):
        with self.lock:
            proc = self.processes.get(session_id)
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                time.sleep(0.1)
                if proc.poll() is None:
                    proc.kill()
            except Exception:
                pass

    def stop_all(self):
        with self.lock:
            pids = list(self.processes.keys())
        for session_id in pids:
            self.stop_session(session_id)

    def focus_session(self, session_id):
        with self.lock:
            info = self.session_info.get(session_id)
        if not info or not info.get("title"):
            return

        selector = "title:^{}$".format(info["title"])
        # Hyprland evaluates `hyprctl dispatch` as Lua when the config is a
        # Lua file, and there the classic `focuswindow <selector>` form is a
        # syntax error. hyprctl still exits 0 in that case, so the reply body
        # is what says whether the dispatch took.
        #
        # Output is captured rather than inherited: this process' stdout is
        # the JSON event stream, and a stray hyprctl line corrupts it.
        for cmd in (
            ["hyprctl", "dispatch", "focuswindow", selector],
            ["hyprctl", "dispatch", 'hl.dsp.focus{window="' + selector + '"}'],
        ):
            try:
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            except Exception:
                continue
            if res.returncode == 0 and res.stdout.strip().lower().startswith("ok"):
                return

    def handle_line(self, line):
        line = line.strip()
        if not line:
            return
        try:
            msg = json.loads(line)
            cmd = msg.get("cmd")

            if cmd == "list_apps":
                self.list_apps(target_args=msg.get("target_args"), device_id=msg.get("deviceId", "default"))
            elif cmd == "launch":
                self.launch_session(
                    session_id=msg.get("id"),
                    type_str=msg.get("type", "app"),
                    target_args=msg.get("target_args"),
                    extra_args=msg.get("extra_args")
                )
            elif cmd == "stop":
                self.stop_session(msg.get("id"))
            elif cmd == "stop_all":
                self.stop_all()
            elif cmd == "focus":
                self.focus_session(msg.get("id"))

        except Exception as e:
            sys.stderr.write(f"Command parse error: {e}\n")

    def run(self):
        for line in sys.stdin:
            self.handle_line(line)
            if not self.running:
                break

def main():
    parser = argparse.ArgumentParser(description="scrcpy Session Manager for II")
    parser.add_argument("--list-apps", action="store_true", help="List apps and exit")
    parser.add_argument("--device-id", default="default", help="Device ID for cache")
    args = parser.parse_args()

    manager = ScrcpySessionManager()

    if args.list_apps:
        manager.list_apps(device_id=args.device_id)
        sys.exit(0)

    manager.run()

if __name__ == "__main__":
    main()
