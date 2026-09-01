#!/usr/bin/env python3
"""Bridge between Quickshell/II and the official LocalSend CLI.

The official `localsend-cli` (published as part of the localsend/localsend
monorepo, `cli/`, matching the LocalSend app since 1.18.0, protocol v2.2) is
a fully interactive terminal application built on crossterm/ratatui. It has
no scriptable/JSON mode: receiving requires pressing Y/N/P, and sending opens
a full-screen device list that is navigated with arrow keys.

This bridge drives the real binary inside a pseudo-terminal and:
  - translates its screen output into the line-oriented JSON event stream
    that services/LocalSend.qml already expects (ready/device/incoming/
    text/saved/cancelled/done/error), and
  - translates simple commands (a single "y"/"n"/"p" line on our stdin, or a
    --target IP for the "send" subcommand) into the keystrokes the official
    CLI expects.

The previous backend (pip package `localsend-cli` 0.1.1) reimplemented the
LocalSend v2 HTTP/TLS transfer from scratch in Python and corrupted files on
receive once the protocol moved to v2.2 (checksum verification, chunked
bodies). This bridge never touches file bytes itself: every transfer is
performed by the official, protocol-correct Rust binary. The bridge only
reads its terminal screen and writes keystrokes.

Usage:
  localsend_bridge.py receive --output DIR [--port PORT]
  localsend_bridge.py send --target IP FILE [FILE ...]
"""
import argparse
import fcntl
import json
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import termios
import time

try:
    import pyte
except ImportError:
    pyte = None

PTY_COLS = 300
PTY_ROWS = 60

ENTER_ALT = b"\x1b[?1049h"
LEAVE_ALT = b"\x1b[?1049l"

# Tokenizes a raw terminal byte stream into CSI/OSC/other-escape sequences,
# CRLF/CR/LF, or runs of plain text. Anchored matching (see _feed_normal)
# guarantees an incomplete trailing escape sequence is never split apart.
TOKEN_RE = re.compile(
    rb"\x1b\[[0-9;?]*[a-zA-Z]"          # CSI ... final-letter
    rb"|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC ... BEL / ST
    rb"|\x1b."                          # any other two-byte escape
    rb"|\r\n|\r|\n"
    rb"|[^\x1b\r\n]+"
)
ERASE_LINE_RE = re.compile(rb"^\x1b\[[0-9]*K$")

DEVICE_ROW_RE = re.compile(r"^\s*\[(\d+|-)\]\s+(.*?)\s+\(([^()]+)\)\s*$")
DISCOVERY_RE = re.compile(r"^D \[(\d+|-)\]\s+(.+?)\s+\(([^()]+)\)$")
FILES_HEADER_RE = re.compile(r"^ {2}Files \((\d+), ([^)]+)\):$")
FILE_ITEM_RE = re.compile(r"^ {4}(.+) \(([^()]+)\)$")
FILE_MORE_RE = re.compile(r"^ {4}\.\.\. and (\d+) more$")
ACCEPT_PROMPT_RE = re.compile(r"^ {2}Accept\? Y/N")
MESSAGE_START_RE = re.compile(r"^R (.+): Message received$")
RECEIVED_SUMMARY_RE = re.compile(
    r"^R (.+): Received (\d+) files?\s*\(([^,]+), took ([^)]+)\)(?:, (\d+) failed)?$"
)
ABORTED_RE = re.compile(r"^R (.+): Aborted by sender$")
CANCELLED_MIDWAY_RE = re.compile(
    r"^R (.+): Cancelled by sender \((\d+) of (\d+) files? received\)$"
)
CANCELLED_LOCAL_RE = re.compile(
    r"^R (.+): cancelled \((\d+) of (\d+) files? received\)$"
)
SEND_DONE_RE = re.compile(r"^S (.+): Sent (\d+) files?\s*\(([^,]+), took ([^)]+)\)$")
SEND_ERROR_RE = re.compile(
    r"^S (.+): (No dialable address|Cancelled.*|Declined|"
    r"PIN required.*|Blocked by another session|Too many requests|"
    r"Request failed.*|Failed to upload.*|receiver accepted \d+ of \d+ files|"
    r"all files were declined)$"
)
SEND_GENERIC_ERROR_RE = re.compile(
    r"^S (No device on \[\d\]|A send is already in progress|No files selected|"
    r"Skipping unreadable file:.*)$"
)


def log(message):
    sys.stderr.write(f"[localsend_bridge] {message}\n")
    sys.stderr.flush()


def emit(event, **fields):
    payload = {"event": event}
    payload.update({k: v for k, v in fields.items() if v is not None})
    sys.stdout.write(json.dumps(payload) + "\n")
    sys.stdout.flush()


def find_binary():
    env = os.environ.get("LOCALSEND_CLI_BIN")
    if env and os.path.isfile(env) and os.access(env, os.X_OK):
        return env
    which = shutil.which("localsend-cli")
    if which:
        return which
    home = os.path.expanduser("~/.local/bin/localsend-cli")
    if os.path.isfile(home) and os.access(home, os.X_OK):
        return home
    return None


def approx_bytes(display):
    """Reverses the CLI's `format_bytes`: "1.2 MB" -> ~1200000. The exact
    byte count is never shown by the interactive UI; this is a display-only
    approximation and never influences the actual transfer."""
    m = re.match(r"^([\d.]+)\s*([A-Za-z]+)$", (display or "").strip())
    if not m:
        return 0
    value = float(m.group(1))
    unit = m.group(2).upper()
    mult = {"B": 1, "KB": 1000, "MB": 1000**2, "GB": 1000**3, "TB": 1000**4}
    return int(value * mult.get(unit, 1))


class PtyChild:
    """Spawns the official localsend-cli attached to a pseudo-terminal."""

    def __init__(self, argv):
        self.pid, self.master_fd = pty.fork()
        if self.pid == 0:
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            try:
                os.execvpe(argv[0], argv, env)
            except OSError as exc:
                sys.stderr.write(f"exec failed: {exc}\n")
            os._exit(127)
        self._set_size()

    def _set_size(self):
        winsize = struct.pack("HHHH", PTY_ROWS, PTY_COLS, 0, 0)
        try:
            fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)
        except OSError:
            pass

    def write(self, data: bytes):
        try:
            os.write(self.master_fd, data)
        except OSError:
            pass

    def read(self, n=65536):
        try:
            return os.read(self.master_fd, n)
        except OSError:
            return b""

    def poll(self):
        """Returns the exit code once the child has exited, else None."""
        try:
            pid, status = os.waitpid(self.pid, os.WNOHANG)
        except ChildProcessError:
            return 0
        if pid == 0:
            return None
        if os.WIFEXITED(status):
            return os.WIFEXITED(status) and os.WEXITSTATUS(status)
        return 1

    def terminate(self):
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    def kill(self):
        try:
            os.kill(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class AltScreen:
    """Renders the ratatui full-screen device list (the only alt-screen
    widget reachable without the CLI's own file picker, which this bridge
    never triggers) via a headless terminal emulator."""

    def __init__(self):
        if pyte is None:
            raise RuntimeError("pyte is required (pip install --user pyte)")
        self.screen = pyte.Screen(PTY_COLS, PTY_ROWS)
        self.stream = pyte.ByteStream(self.screen)

    def feed(self, data: bytes):
        self.stream.feed(data)

    def device_rows(self):
        """Ordered (top to bottom) list of selectable device rows, matching
        the CLI's own `device_rows()` iteration order (Paired, then
        Discovered)."""
        rows = []
        for raw in self.screen.display:
            line = raw.strip(" │")
            m = DEVICE_ROW_RE.match(line)
            if not m:
                continue
            slot, alias, hosts = m.groups()
            if hosts.strip().lower() == "offline":
                continue
            rows.append({"slot": slot, "alias": alias.strip(), "hosts": [h.strip() for h in hosts.split(",")]})
        return rows


class ReceiveEventParser:
    """Stateful line classifier for the CLI's normal (non-alt-screen) log
    view, turning it back into the JSON event contract the shell expects."""

    def __init__(self):
        self._mode = "idle"
        self._incoming = None
        self._message = None
        self._seen_ready = False

    def feed_line(self, line):
        if self._mode == "incoming_files":
            self._feed_incoming(line)
            return
        if self._mode == "message":
            self._feed_message(line)
            return
        self._feed_idle(line)

    def flush(self):
        """Call once at EOF: finalizes any in-flight multi-line block."""
        if self._mode == "message" and self._message is not None:
            emit("text", sender=self._message["sender"], text="\n".join(self._message["lines"]))
        self._mode = "idle"
        self._message = None
        self._incoming = None

    def _feed_idle(self, line):
        if not self._seen_ready and line == "Ready to accept requests.":
            self._seen_ready = True
            emit("ready")
            return

        m = DISCOVERY_RE.match(line)
        if m:
            slot, alias, host = m.groups()
            emit("device", alias=alias, ip=host, port=53317, slot=slot)
            return

        m = MESSAGE_START_RE.match(line)
        if m:
            self._mode = "message"
            self._message = {"sender": m.group(1), "lines": []}
            return

        # The alias line of an incoming-transfer prompt is un-prefixed
        # content wrapped by print_block's own "R " tag — indistinguishable
        # from other single-line "R ..." log entries until the next line
        # (the "Files (...)" header) confirms it.
        if line.startswith("R ") and ":" not in line.split(" ", 2)[1:2] and self._looks_like_alias_line(line):
            self._incoming = {"sender": line[2:], "files": [], "stage": "files_header"}
            self._mode = "incoming_files"
            return

        self._feed_known_single_line(line)

    @staticmethod
    def _looks_like_alias_line(line):
        # Every other single-line "R ..." message embeds ": " right after
        # the alias (e.g. "R Pedro's Phone: You accepted"). A bare alias
        # line never does, so this alone disambiguates the prompt's first
        # line without look-ahead.
        return ": " not in line[2:]

    def _feed_incoming(self, line):
        inc = self._incoming
        if inc["stage"] == "files_header":
            if line.strip() == "":
                return
            m = FILES_HEADER_RE.match(line)
            if m:
                inc["count"] = int(m.group(1))
                inc["total_display"] = m.group(2)
                inc["stage"] = "file_items"
                return
            # Not actually a transfer prompt: replay the buffered alias line
            # as a normal single-line log entry, then reprocess this line.
            self._mode = "idle"
            self._incoming = None
            self._feed_known_single_line(f"R {inc['sender']}")
            self._feed_idle(line)
            return
        if inc["stage"] == "file_items":
            m = FILE_ITEM_RE.match(line)
            if m:
                name, size_display = m.groups()
                inc["files"].append({
                    "name": name,
                    "size": approx_bytes(size_display),
                    "sizeDisplay": size_display,
                })
                return
            if FILE_MORE_RE.match(line):
                return
            if line.strip() == "":
                inc["stage"] = "accept_prompt"
                return
            # Unexpected shape: bail out gracefully.
            self._mode = "idle"
            self._incoming = None
            self._feed_idle(line)
            return
        if inc["stage"] == "accept_prompt":
            if ACCEPT_PROMPT_RE.match(line):
                emit(
                    "incoming",
                    sender=inc["sender"],
                    files=inc["files"],
                    fileCount=inc["count"],
                    totalSizeDisplay=inc.get("total_display"),
                )
                self._mode = "idle"
                self._incoming = None
                return
            self._mode = "idle"
            self._incoming = None
            self._feed_idle(line)

    def _feed_message(self, line):
        if line.startswith("  "):
            self._message["lines"].append(line[2:])
            return
        msg = self._message
        self._mode = "idle"
        self._message = None
        emit("text", sender=msg["sender"], text="\n".join(msg["lines"]) if msg["lines"] else "")
        self._feed_idle(line)

    @staticmethod
    def _feed_known_single_line(line):
        m = RECEIVED_SUMMARY_RE.match(line)
        if m:
            sender, count, size_display, duration, failed = m.groups()
            emit(
                "saved",
                sender=sender,
                fileCount=int(count),
                failedCount=int(failed) if failed else 0,
                sizeDisplay=size_display,
                duration=duration,
                summary=line[2:],
            )
            return
        m = ABORTED_RE.match(line)
        if m:
            emit("cancelled", sender=m.group(1), reason="aborted_by_sender")
            return
        m = CANCELLED_MIDWAY_RE.match(line) or CANCELLED_LOCAL_RE.match(line)
        if m:
            sender, received, total = m.groups()
            emit("cancelled", sender=sender, receivedCount=int(received), totalCount=int(total))
            return
        # Everything else (accept/decline confirmations, per-file failures,
        # discovery notes) is forwarded for visibility but needs no action.
        if line.strip():
            emit("log", message=line)


class SendEventParser:
    def feed_line(self, line):
        m = SEND_DONE_RE.match(line)
        if m:
            sender, count, size_display, duration = m.groups()
            emit("done", sender=sender, fileCount=int(count), sizeDisplay=size_display, duration=duration)
            return True
        m = SEND_ERROR_RE.match(line) or SEND_GENERIC_ERROR_RE.match(line)
        if m:
            emit("error", message=line[2:] if line.startswith("S ") else line)
            return True
        if line.strip():
            emit("log", message=line)
        return False


class NormalModeFeeder:
    """Byte-level tokenizer for the plain (non-alt-screen) log view; hands
    completed lines to `on_line`."""

    def __init__(self, on_line):
        self._on_line = on_line
        self._buf = ""
        self._leftover = b""

    def feed(self, data: bytes) -> bytes:
        """Feeds `data`; returns any unconsumed tail (only non-empty when
        an ENTER_ALT marker or an incomplete escape sits at the boundary)."""
        chunk = self._leftover + data
        self._leftover = b""
        pos, n = 0, len(chunk)
        while pos < n:
            m = TOKEN_RE.match(chunk, pos)
            if not m:
                break
            tok = m.group(0)
            pos = m.end()
            self._handle_token(tok)
        self._leftover = chunk[pos:]
        return self._leftover

    def _handle_token(self, tok: bytes):
        if tok in (b"\r\n", b"\n"):
            self._commit()
        elif tok == b"\r":
            self._buf = ""
        elif tok.startswith(b"\x1b"):
            if ERASE_LINE_RE.match(tok):
                self._buf = ""
        else:
            self._buf += tok.decode("utf-8", "replace")

    def _commit(self):
        self._on_line(self._buf)
        self._buf = ""


class Bridge:
    def __init__(self, argv, on_line):
        self.child = PtyChild(argv)
        self._mode = "normal"
        self._alt = None
        self._normal = NormalModeFeeder(on_line)
        self._raw_tail = b""

    def pump(self, timeout=0.5):
        r, _, _ = select.select([self.child.master_fd], [], [], timeout)
        if not r:
            return True
        data = self.child.read()
        if not data:
            return False
        self._feed(data)
        return True

    def _feed(self, data: bytes):
        buf = self._raw_tail + data
        self._raw_tail = b""
        while buf:
            if self._mode == "normal":
                idx = buf.find(ENTER_ALT)
                if idx == -1:
                    self._raw_tail = self._normal.feed(buf)
                    buf = b""
                else:
                    self._normal.feed(buf[:idx])
                    self._alt = AltScreen()
                    self._mode = "alt"
                    buf = buf[idx + len(ENTER_ALT):]
            else:
                idx = buf.find(LEAVE_ALT)
                if idx == -1:
                    self._alt.feed(buf)
                    buf = b""
                else:
                    self._alt.feed(buf[:idx])
                    self._mode = "normal"
                    buf = buf[idx + len(LEAVE_ALT):]

    def key(self, data: bytes):
        self.child.write(data)


def run_receive(args):
    binary = find_binary()
    if not binary:
        emit("error", message="localsend-cli binary not found (expected ~/.local/bin/localsend-cli)")
        return 1

    parser = ReceiveEventParser()
    bridge = Bridge([binary, "--destination", args.output] + (["--port", str(args.port)] if args.port else []),
                     on_line=parser.feed_line)

    def handle_signal(signum, _frame):
        bridge.child.terminate()
        parser.flush()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    stdin_fd = sys.stdin.fileno()
    os.set_blocking(stdin_fd, False)
    stdin_buf = b""
    while True:
        exit_code = bridge.child.poll()
        if exit_code is not None:
            # Drain whatever is still buffered in the pty before reporting.
            while bridge.pump(timeout=0.05):
                pass
            parser.flush()
            if exit_code != 0:
                emit("error", message=f"localsend-cli exited with code {exit_code}")
            return exit_code
        rlist, _, _ = select.select([bridge.child.master_fd, stdin_fd], [], [], 0.3)
        if bridge.child.master_fd in rlist:
            data = bridge.child.read()
            if data:
                bridge._feed(data)
        if stdin_fd in rlist:
            chunk = os.read(stdin_fd, 4096)
            if not chunk:
                continue
            stdin_buf += chunk
            while b"\n" in stdin_buf:
                line, stdin_buf = stdin_buf.split(b"\n", 1)
                cmd = line.strip().lower()
                if cmd in (b"y", b"n", b"p", b"accept", b"deny", b"pair"):
                    key = {b"y": b"y", b"accept": b"y", b"n": b"n", b"deny": b"n", b"p": b"p", b"pair": b"p"}[cmd]
                    bridge.key(key)


def run_send(args):
    binary = find_binary()
    if not binary:
        emit("error", message="localsend-cli binary not found (expected ~/.local/bin/localsend-cli)")
        return 1
    for f in args.files:
        if not os.path.isfile(f):
            emit("error", message=f"Not a file: {f}")
            return 1

    emit("preparing", ip=args.target)

    argv = [binary]
    for f in args.files:
        argv += ["--file", f]

    send_parser = SendEventParser()
    finished = {"value": False}

    def on_line(line):
        if send_parser.feed_line(line):
            finished["value"] = True

    bridge = Bridge(argv, on_line=on_line)

    def handle_signal(signum, _frame):
        bridge.child.terminate()
        sys.exit(1)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    deadline = time.time() + 25
    navigated = False
    while True:
        exit_code = bridge.child.poll()
        if exit_code is not None:
            while bridge.pump(timeout=0.05):
                pass
            if not finished["value"]:
                emit("error", message=f"localsend-cli exited with code {exit_code} before completing")
            return 0 if finished["value"] else 1

        if not navigated and bridge._mode == "alt" and bridge._alt is not None:
            rows = bridge._alt.device_rows()
            target_index = None
            for i, row in enumerate(rows):
                if args.target in row["hosts"]:
                    target_index = i
                    break
            if target_index is not None:
                for _ in range(target_index):
                    bridge.key(b"\x1b[B")
                    time.sleep(0.02)
                time.sleep(0.05)
                bridge.key(b"\r")
                navigated = True
            elif time.time() > deadline:
                emit("error", message=f"Device not found or offline: {args.target}")
                bridge.key(b"\x1b")  # Esc: closes the device list, quits (--file was given)
                navigated = True
        elif not navigated and bridge._mode == "normal" and time.time() > deadline:
            emit("error", message=f"Device not found or offline: {args.target}")
            bridge.child.terminate()
            return 1

        bridge.pump(timeout=0.15)


def main():
    parser = argparse.ArgumentParser(description="Quickshell/II bridge for the official localsend-cli")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_recv = sub.add_parser("receive")
    p_recv.add_argument("--output", required=True)
    p_recv.add_argument("--port", type=int, default=None)

    p_send = sub.add_parser("send")
    p_send.add_argument("--target", required=True)
    p_send.add_argument("files", nargs="+")

    args = parser.parse_args()
    if args.cmd == "receive":
        os.makedirs(os.path.expanduser(args.output), exist_ok=True)
        sys.exit(run_receive(args))
    else:
        sys.exit(run_send(args))


if __name__ == "__main__":
    main()
