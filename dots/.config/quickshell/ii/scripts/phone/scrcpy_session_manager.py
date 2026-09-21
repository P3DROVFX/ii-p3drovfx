#!/usr/bin/env python3
import os
import sys
import json
import signal
import subprocess
import threading
import time
import argparse
import re
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "illogical-impulse" / "phone" / "apps"

# Its own title so the shell never mistakes the throwaway unlock mirror for a
# real session, and so it can be matched separately.
UNLOCK_WINDOW_TITLE = "ii-phone-unlock"

class ScrcpySessionManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.processes = {}  # session_id -> subprocess.Popen
        self.session_info = {} # session_id -> dict
        self.starting = set()  # session_ids whose launch thread is still running
        self.end_actions = {}  # session_id -> what to do to the phone afterwards
        self.deliberate = set()  # session_ids the user asked to stop
        self.listing = False  # an app listing is already under way
        self.keepalives = {}  # session_id -> when the shell last said it still wants it
        self.emit_lock = threading.Lock()
        self.running = True

    def emit(self, event_data):
        # Every session has its own thread and they all share this stream; one
        # write per event, under a lock, so two events can never interleave
        # into a line the shell cannot parse.
        try:
            line = json.dumps(event_data) + "\n"
            with self.emit_lock:
                sys.stdout.write(line)
                sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"Error emitting event: {e}\n")

    def resolve_adb_target(self, target_args=None):
        """Pick the serial to hand scrcpy.

        The caller already resolved one against live mDNS, so it wins as long
        as the phone still answers on it. Only when it has gone stale does
        this fall back to whatever `adb devices` reports, and there a pinned
        `:5555` beats a wireless-debugging port that Android re-rolls
        whenever adbd restarts.
        """
        wanted = ""
        if target_args and len(target_args) >= 2 and target_args[0] in ("-s", "--serial"):
            wanted = str(target_args[1])

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

            if wanted and (wanted in usb_devices or wanted in ip_devices):
                return ["-s", wanted]
            if usb_devices:
                return ["-s", usb_devices[0]]
            # The port is what goes stale, not the address: with two phones
            # on the network, falling back must not land on the other one.
            if ":" in wanted:
                host = wanted.rsplit(":", 1)[0] + ":"
                same_host = [s for s in ip_devices if s.startswith(host)]
                if same_host:
                    ip_devices = same_host
            pinned = [s for s in ip_devices if s.endswith(":5555")]
            if pinned:
                return ["-s", pinned[0]]
            if ip_devices:
                return ["-s", ip_devices[0]]
        except Exception:
            pass

        return target_args or []

    def list_apps_async(self, target_args=None, device_id="default"):
        """Listing takes seconds (scrcpy pushes its server first) and is asked
        for on every reconnect. Run inline it held up whatever launch or stop
        was typed right behind it."""
        with self.lock:
            if self.listing:
                return
            self.listing = True

        def work():
            try:
                self.list_apps(target_args=target_args, device_id=device_id)
            finally:
                with self.lock:
                    self.listing = False

        threading.Thread(target=work, daemon=True).start()

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

    # Two independent flags, because neither alone covers every state. The
    # display policy's `isKeyguardShowing` misses a trusted lockscreen (Smart
    # Lock / "extended unlock": the device counts as unlocked, but the swipe
    # screen is still up and a virtual display still comes out locked-down),
    # and KeyguardStateMonitor's `mIsShowing` is the one that tracks whether
    # the lockscreen is actually on screen. `mTrusted` is deliberately not
    # consulted — it is true even when fully unlocked.
    # `secure` comes along for the ride: a secure keyguard means the PIN
    # bouncer is a FLAG_SECURE surface, so scrcpy can only ever show black
    # there and the user has to be told rather than left staring at it.
    KEYGUARD_QUERY = (
        "dumpsys window 2>/dev/null | awk '"
        "/isKeyguardShowing=/ {print \"showing=\" ($0 ~ /=true/ ? \"true\" : \"false\")} "
        "/KeyguardStateMonitor/ {k=1} "
        "k && /mIsShowing=/ {print \"showing=\" ($0 ~ /=true/ ? \"true\" : \"false\"); k=0} "
        "/KeyguardServiceDelegate/ {d=1} "
        "d && /secure=/ {print \"secure=\" ($0 ~ /=true/ ? \"true\" : \"false\"); d=0}'"
    )

    def keyguard_state(self, target_args):
        """(showing, secure). `showing` is None when the phone can't be asked."""
        cmd = ["adb"] + list(target_args) + ["shell", self.KEYGUARD_QUERY]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=6)
        except Exception:
            return (None, False)
        if res.returncode != 0:
            return (None, False)
        lines = [ln.strip() for ln in res.stdout.splitlines() if "=" in ln]
        shown = [ln for ln in lines if ln.startswith("showing=")]
        if not shown:
            # The phone answered but its dump has neither flag (another
            # Android version, another vendor). Not knowing must not read as
            # "unreachable": that would hold every launch back until it
            # times out. Launch as if unlocked, which is what used to happen.
            return (False, False)
        # Any flag still set means the lockscreen is up.
        return (any(ln == "showing=true" for ln in shown),
                any(ln == "secure=true" for ln in lines))

    def keyguard_showing(self, target_args):
        return self.keyguard_state(target_args)[0]

    def needs_credential(self, target_args):
        """True only when the phone says outright that it wants its PIN.

        `deviceLocked` is "secure and not currently trusted". When it is set,
        dismissing the keyguard can only ever bring up the PIN pad, so waking
        the phone to try is a few seconds of lit lockscreen for nothing.
        Anything unreadable counts as "worth a try".
        """
        try:
            res = subprocess.run(
                ["adb"] + list(target_args) + ["shell", "dumpsys trust 2>/dev/null"],
                capture_output=True, text=True, timeout=6)
        except Exception:
            return False
        users = [ln for ln in res.stdout.splitlines() if "deviceLocked=" in ln]
        current = [ln for ln in users if "(current)" in ln] or users[:1]
        return bool(current) and "deviceLocked=1" in current[0]

    def _display_size(self, target_args):
        try:
            res = subprocess.run(["adb"] + list(target_args) + ["shell", "wm size"],
                                 capture_output=True, text=True, timeout=6)
        except Exception:
            return None
        # "Physical size: 1080x2340" plus an "Override size:" line when one is
        # set; the override is what is actually on screen, so take the last.
        found = re.findall(r"(\d+)x(\d+)", res.stdout)
        if not found:
            return None
        return int(found[-1][0]), int(found[-1][1])

    # Runs on the phone as one shell invocation: a round trip per step would
    # cost more than the steps themselves.
    #
    # Waking is unavoidable — the keyguard ignores everything while the phone
    # dozes — but the panel does not have to follow. A power-off request is
    # only honoured once the display has actually been told to turn on, and
    # the phone re-asserts "on" once more ~0.4 s after waking, while its
    # brightness ramps; so the request is repeated until that has passed,
    # which leaves the panel powered for a few milliseconds in total. Touches
    # are ignored while it is off.
    #
    # The dismissal goes last on purpose. Unlocking restarts adbd, which
    # kills this shell with it (detaching does not help), and a loop cut
    # short would leave the panel lit until the connection is back.
    # Timed against /proc/uptime in centiseconds: the phone's shell only has
    # 32-bit arithmetic, which rules out epoch milliseconds.
    DARK_UNLOCK = (
        "input keyevent 224; "
        "read u _ < /proc/uptime; e=$(( ${u%.*}${u#*.} + 90 )); "
        "while :; do cmd display power-off 0; read u _ < /proc/uptime; "
        "[ ${u%.*}${u#*.} -ge $e ] && break; sleep 0.04; done; "
        "wm dismiss-keyguard"
    )
    LIT_UNLOCK = "input keyevent 224; sleep 0.3; wm dismiss-keyguard"

    def _adb_shell(self, target_args, script, timeout=6):
        try:
            subprocess.run(["adb"] + list(target_args) + ["shell", script],
                           capture_output=True, text=True, timeout=timeout)
            return True
        except Exception:
            return False

    def _try_trusted_unlock(self, target_args, dark=False, legacy=False):
        """Wake the phone and dismiss its lockscreen.

        Under extended unlock / Smart Lock the keyguard is already trusted and
        only needs dismissing, so this clears it without the phone being
        touched. On a genuinely secured phone it only reveals the PIN pad,
        which the unlock mirror then shows.

        `dark` keeps the panel off throughout, for sessions that are going to
        turn the screen off anyway. `legacy` swipes instead of asking the
        window manager, for phones where the dismissal is refused.
        """
        if dark:
            self._adb_shell(target_args, self.DARK_UNLOCK)
            return
        if not legacy:
            self._adb_shell(target_args, self.LIT_UNLOCK)
            return

        size = self._display_size(target_args)
        if size is None:
            return
        width, height = size
        column = str(width // 2)
        # WAKEUP, not POWER: it never puts a woken phone back to sleep. The
        # pause matters: a swipe sent in the same breath as the wake is
        # swallowed and the keyguard just stays there.
        self._adb_shell(
            target_args,
            "input keyevent 224; sleep 1; input swipe %s %d %s %d 200"
            % (column, int(height * 0.8), column, int(height * 0.25)))

    def _hold_panel_off(self, target_args):
        self._adb_shell(target_args, "cmd display power-off 0")

    def _restore_panel(self, target_args=None):
        """Hand the panel back to the phone after a dark unlock."""
        if target_args is None:
            target_args = self.resolve_adb_target(None)
        self._adb_shell(target_args, "cmd display power-reset 0")

    def _run_end_action(self, session_id, action):
        if action != "lock":
            return
        target = self.resolve_adb_target(None)
        try:
            # SLEEP rather than POWER: POWER toggles, and would wake a phone
            # whose screen scrcpy had already turned off.
            subprocess.run(["adb"] + list(target) + ["shell", "input", "keyevent", "223"],
                           capture_output=True, text=True, timeout=6)
        except Exception:
            pass

    def _spawn_unlock_helper(self, resolved_target):
        """A plain mirror of the phone screen, purely so the keyguard can be
        dismissed from the desktop.

        A virtual display never shows the lockscreen, and "turn screen off"
        means the phone's own panel is dark — so without this there is no way
        to unlock except picking the phone up. Deliberately built without
        --turn-screen-off, and without --new-display, so it shows display 0
        and powers the screen on.
        """
        cmd = ["scrcpy"] + list(resolved_target) + [
            "--window-title=" + UNLOCK_WINDOW_TITLE,
            "--no-audio",
            "--stay-awake",
            "--window-width=400",
        ]
        try:
            return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            return None

    def wait_for_device(self, target_args, session_id, need_unlocked,
                        auto_unlock=True, dark=False,
                        timeout=25.0, locked_timeout=90.0):
        """Hold the launch until the phone can actually serve it.

        Two things make a launch land badly. An unreachable phone (adbd
        restarts on every unlock and takes a few seconds to come back) just
        fails. A phone whose keyguard is still up is worse for a virtual
        display: DeX comes up locked-down on it, with no wallpaper and no
        navigation bar, and stays that way after the phone is unlocked.

        `dark` is for sessions that turn the phone's screen off: the unlock
        then never lights the panel. scrcpy gives it back when the session
        ends, exactly as if it had turned it off itself; only a launch that
        never gets that far has to be undone here.

        Returns the resolved target to launch with, or None on timeout.
        """
        deadline = time.time() + timeout
        unlock_proc = None
        notified = False
        tried_trusted = 0
        panel_held = False
        delivered = False
        try:
            while True:
                resolved = self.resolve_adb_target(target_args)
                locked, secure = self.keyguard_state(resolved)
                if locked is False or (locked is True and not need_unlocked):
                    # Dismissing the keyguard is not instant on the phone's
                    # side; creating the display in the tail of that
                    # transition lands in the same locked-down DeX.
                    if need_unlocked and unlock_proc is not None:
                        time.sleep(1.5)
                    delivered = True
                    return resolved

                # Cheap and invisible, so it gets the first go; only when it
                # fails is a window put on the user's screen.
                if (locked is True and need_unlocked and auto_unlock
                        and tried_trusted == 0 and secure
                        and self.needs_credential(resolved)):
                    tried_trusted = 2

                if (locked is True and need_unlocked and auto_unlock
                        and tried_trusted < 2):
                    tried_trusted += 1
                    panel_held = panel_held or dark
                    # Second go: the polite dismissal did nothing, swipe.
                    self._try_trusted_unlock(resolved, dark=dark,
                                             legacy=tried_trusted > 1 and not dark)
                    # The unlock drops the connection for a moment, so a read
                    # that fails here means "ask again", not "unreachable".
                    # Paced for a machine, unlike the loop around it.
                    for _ in range(6):
                        time.sleep(0.2)
                        resolved = self.resolve_adb_target(target_args)
                        if self.keyguard_state(resolved)[0] is False:
                            break
                    else:
                        continue
                    if dark:
                        # Anything that re-lit the panel while the connection
                        # was down gets undone before the session starts.
                        self._hold_panel_off(resolved)
                    delivered = True
                    return resolved

                if locked is True and unlock_proc is None:
                    if panel_held:
                        # The mirror below is useless on a dark, touch-dead
                        # panel; from here on a human is doing the unlocking.
                        self._restore_panel(resolved)
                        panel_held = False
                    unlock_proc = self._spawn_unlock_helper(resolved)
                    if unlock_proc is not None:
                        # Unlocking is a human action — give it human time.
                        deadline = time.time() + locked_timeout
                    self.emit({
                        "event": "waiting",
                        "id": session_id,
                        "reason": "locked",
                        "unlockWindow": unlock_proc is not None,
                        # The PIN pad will be black in that window. Input still
                        # reaches the phone, so it can be typed blind — but
                        # only if the user knows that is what is happening.
                        "secure": bool(secure)
                    })
                    notified = True
                elif not notified:
                    notified = True
                    self.emit({
                        "event": "waiting",
                        "id": session_id,
                        "reason": "locked" if locked else "unreachable"
                    })

                # Closing the unlock window is how the user says "not now".
                if unlock_proc is not None and unlock_proc.poll() is not None:
                    return None
                if time.time() >= deadline:
                    return None
                time.sleep(1.0)
        finally:
            if unlock_proc is not None and unlock_proc.poll() is None:
                try:
                    unlock_proc.terminate()
                except Exception:
                    pass
            if panel_held and not delivered:
                self._restore_panel()

    def launch_session(self, session_id, type_str, target_args, extra_args,
                       end_action="", auto_unlock=True):
        with self.lock:
            if session_id in self.starting:
                return
            proc = self.processes.get(session_id)
            running = proc is not None and proc.poll() is None
            if not running:
                self.starting.add(session_id)
                self.end_actions[session_id] = end_action
                self.deliberate.discard(session_id)
                self.keepalives[session_id] = time.time()

        if running:
            # Outside the lock: focus_session takes it too, and it is not
            # re-entrant — doing this inside hung the command loop for good.
            self.focus_session(session_id)
            self.emit({
                "event": "started",
                "id": session_id,
                "pid": proc.pid,
                "alreadyRunning": True
            })
            return

        # The wait below can take seconds; keep stdin responsive meanwhile.
        t = threading.Thread(
            target=self._start_session,
            args=(session_id, type_str, target_args, extra_args, auto_unlock),
            daemon=True)
        t.start()

    def _start_session(self, session_id, type_str, target_args, extra_args,
                       auto_unlock=True):
        args = list(extra_args or [])
        needs_display = any(str(a).startswith("--new-display") for a in args)
        # A session that blanks the phone should not light it up to get going.
        dark = needs_display and any(str(a) in ("--turn-screen-off", "-S") for a in args)
        try:
            resolved_target = self.wait_for_device(
                target_args, session_id, needs_display,
                auto_unlock=auto_unlock, dark=dark)
            if resolved_target is None:
                self.emit({
                    "event": "error",
                    "id": session_id,
                    "message": "Phone is locked or unreachable"
                })
                return

            title = f"ii-phone-{type_str}-{session_id.replace(':', '_')}"
            cmd = ["scrcpy"] + resolved_target + ["--window-title=" + title] + args

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
        except Exception as e:
            if dark:
                self._restore_panel()
            self.emit({
                "event": "error",
                "id": session_id,
                "message": f"Failed to launch scrcpy: {e}"
            })
            return
        finally:
            with self.lock:
                self.starting.discard(session_id)

        self._wait_process(session_id, proc)

    def _wait_process(self, session_id, proc):
        # Drained as it comes, not read at the end: a pipe nobody reads fills
        # up after 64 KB of warnings, and scrcpy then blocks mid-session on
        # its next log line.
        err_msg = ""
        try:
            for line in proc.stderr:
                if line.strip():
                    err_msg = line.strip()
        except Exception:
            pass
        code = proc.wait()

        with self.lock:
            if session_id in self.processes:
                del self.processes[session_id]
            if session_id in self.session_info:
                del self.session_info[session_id]
            action = self.end_actions.pop(session_id, "")
            deliberate = session_id in self.deliberate
            self.deliberate.discard(session_id)

        # Only for a session that actually finished. A connection drop is not
        # the user putting the phone down, and the shell is about to reopen it.
        if action and (deliberate or code == 0):
            self._run_end_action(session_id, action)

        self.emit({
            "event": "exited",
            "id": session_id,
            "code": code,
            "error": err_msg
        })

    def stop_session(self, session_id):
        with self.lock:
            self.deliberate.add(session_id)
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
                self.list_apps_async(target_args=msg.get("target_args"), device_id=msg.get("deviceId", "default"))
            elif cmd == "launch":
                self.launch_session(
                    session_id=msg.get("id"),
                    type_str=msg.get("type", "app"),
                    target_args=msg.get("target_args"),
                    extra_args=msg.get("extra_args"),
                    end_action=msg.get("end_action", ""),
                    auto_unlock=bool(msg.get("auto_unlock", True))
                )
            elif cmd == "stop":
                self.stop_session(msg.get("id"))
            elif cmd == "stop_all":
                self.stop_all()
            elif cmd == "keepalive":
                self.note_keepalive(msg.get("id"))
            elif cmd == "focus":
                self.focus_session(msg.get("id"))

        except Exception as e:
            sys.stderr.write(f"Command parse error: {e}\n")

    # The embedded mirror is the one session the user cannot see or close for
    # themselves: it lives on a hidden workspace, under the panel that paints
    # its picture. Orphaning it would leave the phone encoding video for a
    # window nobody will ever look at again, so it goes down with the shell.
    # The windowed sessions are deliberately left alone — those are the user's,
    # and a shell reload is no reason to close them.
    SHELL_OWNED = ("embed",)

    # This process outlives a config reload with its children still running,
    # and the fresh shell has no memory of having asked for them. So a session
    # with no window of its own is held open by the shell repeating that it
    # still wants it, and ends when that stops — whether the page closed, the
    # config reloaded or the shell died.
    KEEPALIVE_TIMEOUT = 15.0

    def note_keepalive(self, session_id):
        with self.lock:
            self.keepalives[session_id] = time.time()

    def _keepalive_watchdog(self):
        while self.running:
            time.sleep(5)
            now = time.time()
            with self.lock:
                stale = [sid for sid in self.SHELL_OWNED
                         if sid in self.processes
                         and self.processes[sid].poll() is None
                         and now - self.keepalives.get(sid, now) > self.KEEPALIVE_TIMEOUT]
            for sid in stale:
                self.deliberate.add(sid)
                self.stop_session(sid)

    def shutdown(self):
        with self.lock:
            owned = [proc for sid, proc in self.processes.items()
                     if sid in self.SHELL_OWNED and proc.poll() is None]
        for proc in owned:
            try:
                proc.terminate()
            except Exception:
                pass
        for proc in owned:
            try:
                proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

    def run(self):
        threading.Thread(target=self._keepalive_watchdog, daemon=True).start()
        try:
            for line in sys.stdin:
                self.handle_line(line)
                if not self.running:
                    break
        finally:
            self.shutdown()

def main():
    parser = argparse.ArgumentParser(description="scrcpy Session Manager for II")
    parser.add_argument("--list-apps", action="store_true", help="List apps and exit")
    parser.add_argument("--device-id", default="default", help="Device ID for cache")
    args = parser.parse_args()

    manager = ScrcpySessionManager()

    # setpriv --pdeathsig TERM is what brings this process down with the
    # shell, and the default handler would exit before `finally` ran.
    def _terminate(_signum, _frame):
        manager.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _terminate)
    signal.signal(signal.SIGHUP, _terminate)

    if args.list_apps:
        manager.list_apps(device_id=args.device_id)
        sys.exit(0)

    manager.run()

if __name__ == "__main__":
    main()
