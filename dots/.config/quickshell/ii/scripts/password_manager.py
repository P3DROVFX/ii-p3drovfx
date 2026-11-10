#!/usr/bin/env python3
"""Password manager bridge for the bar's Passwords widget.

One small adapter per password manager CLI, one JSON line out per call. The
shell only ever sees names, usernames and hosts: passwords and TOTP codes go
from the CLI straight to `wl-copy` or `wtype` from here and never come back
on stdout, so they never land in QML memory or in a Process buffer.

Commands (all print one JSON object):
    detect                         which CLIs exist, plus wtype for auto-type
    status  --provider P           missing | unauthenticated | locked | unlocked
    unlock  --provider P           master password on stdin (bitwarden only)
    lock    --provider P
    list    --provider P           items without secrets
    sync    --provider P
    copy    --provider P --id ID --field password|username|totp --clear SECONDS
    type    --provider P --id ID --mode password|username|login

Bitwarden's session key lives in $XDG_RUNTIME_DIR/ii-passwords (0700/0600):
a tmpfs that dies with the login session, so a reboot always comes back
locked. It reaches `bw` through BW_SESSION, never through argv, and the master
password goes through BW_PASSWORD for the same reason (/proc/PID/cmdline is
world-readable, /proc/PID/environ is not).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

def _extend_path() -> None:
    """Find CLIs installed per user, outside the session PATH.

    The shell is started by the compositor, so it never sees what a login
    shell adds: `npm i -g @bitwarden/cli` under nvm/volta/fnm, `cargo install
    rbw`, snaps. bw is a node script (`#!/usr/bin/env node`), so its directory
    must be on PATH for the child too, not just found by which().
    """
    home = Path.home()
    candidates: list[Path] = []
    nvm = Path(os.environ.get("NVM_DIR") or home / ".nvm") / "versions" / "node"
    if nvm.is_dir():
        def version_key(p: Path):
            parts = p.name.lstrip("v").split(".")
            return tuple(int(x) if x.isdigit() else 0 for x in parts)
        candidates += [p / "bin" for p in sorted(nvm.iterdir(), key=version_key, reverse=True)]
    fnm = home / ".local" / "share" / "fnm" / "node-versions"
    if fnm.is_dir():
        candidates += sorted(fnm.glob("*/installation/bin"), reverse=True)
    candidates += [home / ".volta" / "bin", home / ".npm-global" / "bin",
                   home / ".local" / "share" / "npm" / "bin", home / ".bun" / "bin",
                   home / ".cargo" / "bin", home / ".local" / "bin", Path("/snap/bin")]
    current = os.environ.get("PATH", "").split(os.pathsep)
    extra = [str(p) for p in candidates if p.is_dir() and str(p) not in current]
    if extra:
        os.environ["PATH"] = os.pathsep.join(current + extra)


_extend_path()

PROVIDERS = ("bitwarden", "rbw", "pass")
BINARIES = {"bitwarden": "bw", "rbw": "rbw", "pass": "pass"}
CLI_TIMEOUT = 60


class BridgeError(Exception):
    def __init__(self, message: str, code: str = "error"):
        super().__init__(message)
        self.code = code


# ── Helpers ─────────────────────────────────────────────────────────────────

def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def runtime_dir() -> Path:
    # Test harnesses point this elsewhere so they never touch the real session.
    override = os.environ.get("II_PASSWORDS_RUNTIME_DIR")
    if override:
        path = Path(override)
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(path, 0o700)
        return path
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not base:
        # No fallback on purpose: anywhere else could be readable by others.
        raise BridgeError("XDG_RUNTIME_DIR is not set", "runtime")
    path = Path(base) / "ii-passwords"
    path.mkdir(mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)
    return path


def run(cmd: list[str], env: dict | None = None, stdin: str | None = None,
        timeout: int = CLI_TIMEOUT) -> subprocess.CompletedProcess:
    full_env = os.environ.copy()
    full_env.update(env or {})
    # Keep CLIs from prompting on a terminal we do not have.
    full_env.setdefault("BW_NOINTERACTION", "true")
    try:
        return subprocess.run(cmd, input=stdin, capture_output=True, text=True,
                              env=full_env, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise BridgeError(f"{cmd[0]} timed out", "timeout") from exc
    except FileNotFoundError as exc:
        raise BridgeError(f"{cmd[0]} is not installed", "missing") from exc


def last_line(text: str) -> str:
    lines = [line.strip() for line in (text or "").splitlines() if line.strip()]
    return lines[-1] if lines else ""


def host_of(uri: str) -> str:
    if not uri:
        return ""
    candidate = uri if "://" in uri else "https://" + uri
    try:
        host = urlparse(candidate).hostname or ""
    except ValueError:
        return ""
    return host[4:] if host.startswith("www.") else host


def has_control_chars(text: str) -> bool:
    return any(ord(ch) < 32 or ord(ch) == 127 for ch in text)


def copy_to_clipboard(secret: str, clear_after: int) -> None:
    """Serve `secret` from a detached wl-copy.

    `--foreground` under `timeout` is the auto-clear: when the deadline kills
    wl-copy its offer goes away and the clipboard empties. A newer copy from
    anyone makes wl-copy exit early, so the deadline never touches it.
    `--sensitive` lets clipboard history (cliphist) skip the entry.
    """
    if not secret:
        raise BridgeError("Nothing to copy", "empty")
    if not shutil.which("wl-copy"):
        raise BridgeError("wl-copy is not installed", "missing")
    base = ["wl-copy", "--foreground", "--sensitive", "--type", "text/plain"]
    cmd = (["timeout", str(int(clear_after))] + base) if clear_after > 0 else base
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True,
                            text=True)
    assert proc.stdin is not None
    proc.stdin.write(secret)
    proc.stdin.close()


def type_text(parts: list[tuple[str, str]]) -> None:
    """Type into the focused window. parts: ("text", s) or ("key", name)."""
    if not shutil.which("wtype"):
        raise BridgeError("wtype is not installed", "missing")
    for kind, value in parts:
        if kind == "text" and has_control_chars(value):
            # wtype would press these as keys (Return, Tab, Backspace…).
            raise BridgeError("Refusing to type a value with control characters", "unsafe")
    # Let the popup unmap and the previous window take the keyboard back.
    time.sleep(0.25)
    for kind, value in parts:
        if kind == "key":
            subprocess.run(["wtype", "-k", value], check=False, timeout=10)
        elif value:
            subprocess.run(["wtype", "-d", "12", "-"], input=value, text=True,
                           check=False, timeout=60)


# ── Bitwarden (official `bw` CLI) ────────────────────────────────────────────

class Bitwarden:
    name = "bitwarden"

    def __init__(self):
        self.session_file = None

    def _session_path(self) -> Path:
        if self.session_file is None:
            self.session_file = runtime_dir() / "bw-session"
        return self.session_file

    def _session(self) -> str:
        path = self._session_path()
        try:
            st = path.stat()
        except FileNotFoundError:
            return ""
        # Only trust a file we own that nobody else can read.
        if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o077:
            path.unlink(missing_ok=True)
            return ""
        return path.read_text().strip()

    def _store_session(self, key: str) -> None:
        path = self._session_path()
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as handle:
            handle.write(key)

    def _env(self) -> dict:
        key = self._session()
        return {"BW_SESSION": key} if key else {}

    def _bw(self, *args: str, stdin: str | None = None,
            extra_env: dict | None = None) -> subprocess.CompletedProcess:
        env = self._env()
        env.update(extra_env or {})
        return run(["bw", *args], env=env, stdin=stdin)

    def status(self) -> dict:
        result = self._bw("status")
        try:
            data = json.loads(last_line(result.stdout) or "{}")
        except json.JSONDecodeError:
            data = {}
        state = data.get("status") or "locked"
        if state not in ("unauthenticated", "locked", "unlocked"):
            state = "locked"
        if state != "unlocked" and self._session():
            # A stale key (bw lock from a terminal, server logout).
            self._session_path().unlink(missing_ok=True)
        return {"state": state, "account": data.get("userEmail") or "",
                "server": data.get("serverUrl") or ""}

    def unlock(self, password: str) -> dict:
        if not password:
            raise BridgeError("Enter your master password", "empty")
        result = run(["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"],
                     env={"BW_PASSWORD": password})
        key = last_line(result.stdout)
        if result.returncode != 0 or not key:
            message = last_line(result.stderr) or "Unlock failed"
            code = "auth" if "invalid master password" in message.lower() else "error"
            if "not logged in" in message.lower():
                code = "unauthenticated"
            raise BridgeError(message, code)
        self._store_session(key)
        return {"state": "unlocked"}

    def lock(self) -> dict:
        self._bw("lock")
        self._session_path().unlink(missing_ok=True)
        return {"state": "locked"}

    def sync(self) -> dict:
        result = self._bw("sync")
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or "Sync failed")
        return {}

    def list(self) -> dict:
        result = self._bw("list", "items")
        if result.returncode != 0:
            message = last_line(result.stderr) or "Could not read the vault"
            code = "locked" if "locked" in message.lower() else "error"
            raise BridgeError(message, code)
        try:
            raw = json.loads(result.stdout or "[]")
        except json.JSONDecodeError as exc:
            raise BridgeError("Unexpected output from bw") from exc
        folders = {}
        folder_result = self._bw("list", "folders")
        if folder_result.returncode == 0:
            try:
                folders = {f.get("id"): f.get("name", "") for f in json.loads(folder_result.stdout or "[]")}
            except json.JSONDecodeError:
                folders = {}
        items = []
        for entry in raw:
            if entry.get("type") != 1:  # logins only
                continue
            login = entry.get("login") or {}
            uris = [u.get("uri", "") for u in (login.get("uris") or []) if u.get("uri")]
            items.append({
                "id": entry.get("id", ""),
                "name": entry.get("name", ""),
                "user": login.get("username") or "",
                "host": host_of(uris[0]) if uris else "",
                "hosts": [h for h in (host_of(u) for u in uris) if h][:4],
                "folder": folders.get(entry.get("folderId"), "") or "",
                "totp": bool(login.get("totp")),
                "favorite": bool(entry.get("favorite")),
            })
            # The raw entry carried the password: drop our only reference.
            entry.clear()
        return {"items": items}

    def secret(self, item_id: str, field: str) -> str:
        what = {"password": "password", "username": "username", "totp": "totp"}[field]
        result = self._bw("get", what, item_id)
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or f"No {field} on this item")
        return result.stdout.rstrip("\n")


# ── rbw (unofficial Bitwarden client with its own agent) ─────────────────────

class Rbw:
    name = "rbw"

    def status(self) -> dict:
        if run(["rbw", "unlocked"]).returncode == 0:
            return {"state": "unlocked", "account": self._email()}
        config = run(["rbw", "config", "show"])
        try:
            email = json.loads(config.stdout or "{}").get("email") or ""
        except json.JSONDecodeError:
            email = ""
        return {"state": "locked" if email else "unauthenticated", "account": email}

    def _email(self) -> str:
        config = run(["rbw", "config", "show"])
        try:
            return json.loads(config.stdout or "{}").get("email") or ""
        except json.JSONDecodeError:
            return ""

    def unlock(self, _password: str) -> dict:
        # rbw asks through its own pinentry; the master password never passes here.
        result = run(["rbw", "unlock"], timeout=300)
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or "Unlock cancelled", "auth")
        return {"state": "unlocked"}

    def lock(self) -> dict:
        run(["rbw", "lock"])
        return {"state": "locked"}

    def sync(self) -> dict:
        result = run(["rbw", "sync"])
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or "Sync failed")
        return {}

    def list(self) -> dict:
        result = run(["rbw", "list", "--fields", "id,name,user,folder"])
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or "Could not read the vault", "locked")
        items = []
        for line in result.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            parts += [""] * (4 - len(parts))
            item_id, name, user, folder = parts[:4]
            items.append({"id": item_id, "name": name, "user": user,
                          "host": host_of(name) if "." in name else "", "hosts": [],
                          "folder": folder, "totp": None, "favorite": False})
        return {"items": items}

    def secret(self, item_id: str, field: str) -> str:
        if field == "totp":
            result = run(["rbw", "code", item_id])
            if result.returncode != 0:
                raise BridgeError(last_line(result.stderr) or "No TOTP on this item")
            return result.stdout.strip()
        result = run(["rbw", "get", "--raw", item_id])
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or "Item not found")
        try:
            data = (json.loads(result.stdout) or {}).get("data") or {}
        except json.JSONDecodeError as exc:
            raise BridgeError("Unexpected output from rbw") from exc
        value = data.get("password" if field == "password" else "username") or ""
        if not value:
            raise BridgeError(f"No {field} on this item", "empty")
        return value


# ── pass (the standard unix password manager) ────────────────────────────────

class Pass:
    name = "pass"

    def _store(self) -> Path:
        return Path(os.environ.get("PASSWORD_STORE_DIR") or Path.home() / ".password-store")

    def status(self) -> dict:
        store = self._store()
        if not (store / ".gpg-id").exists():
            return {"state": "unauthenticated", "account": ""}
        # gpg-agent asks for the passphrase on first use; the store is "open".
        return {"state": "unlocked", "account": str(store)}

    def unlock(self, _password: str) -> dict:
        return {"state": "unlocked"}

    def lock(self) -> dict:
        run(["gpgconf", "--reload", "gpg-agent"])
        return {"state": "unlocked"}

    def sync(self) -> dict:
        if (self._store() / ".git").exists():
            result = run(["pass", "git", "pull", "--rebase"])
            if result.returncode != 0:
                raise BridgeError(last_line(result.stderr) or "git pull failed")
        return {}

    def list(self) -> dict:
        store = self._store()
        items = []
        for path in sorted(store.rglob("*.gpg")):
            rel = path.relative_to(store).with_suffix("")
            if any(part.startswith(".") for part in rel.parts):
                continue
            entry = str(rel)
            parts = rel.parts
            host = next((p for p in reversed(parts) if "." in p), "")
            items.append({"id": entry, "name": parts[-1], "user": "",
                          "host": host_of(host), "hosts": [],
                          "folder": "/".join(parts[:-1]), "totp": None, "favorite": False})
        return {"items": items}

    def _decrypt(self, item_id: str) -> list[str]:
        result = run(["pass", "show", item_id], timeout=300)
        if result.returncode != 0:
            raise BridgeError(last_line(result.stderr) or "Could not decrypt", "auth")
        return result.stdout.splitlines()

    def secret(self, item_id: str, field: str) -> str:
        if field == "totp":
            result = run(["pass", "otp", item_id], timeout=300)
            if result.returncode != 0:
                raise BridgeError(last_line(result.stderr) or "No TOTP on this entry")
            return result.stdout.strip()
        lines = self._decrypt(item_id)
        if field == "password":
            return lines[0] if lines else ""
        for line in lines[1:]:
            key, _, value = line.partition(":")
            if key.strip().lower() in ("user", "username", "login", "email") and value.strip():
                return value.strip()
        # The common layout names the file after the login.
        return Path(item_id).name


ADAPTERS = {"bitwarden": Bitwarden, "rbw": Rbw, "pass": Pass}


BITWARDEN_SERVERS = {
    "1": ("bitwarden.com (US)", "https://vault.bitwarden.com"),
    "2": ("bitwarden.eu (EU)", "https://vault.bitwarden.eu"),
}


def server_label(url: str) -> str:
    host = host_of(url)
    if host.endswith("bitwarden.eu"):
        return "bitwarden.eu (EU)"
    if host.endswith("bitwarden.com") or not host:
        return "bitwarden.com (US)"
    return url


def choose_bitwarden_server() -> bool:
    """Ask which server to sign in to; Enter keeps the current one.

    `bw config server` only works while signed out, which is exactly when
    this runs. Returns False if the user cancels or the URL is refused.
    """
    current = last_line(run(["bw", "config", "server"]).stdout) or "https://bitwarden.com"
    print(f"Bitwarden server — now: {server_label(current)}\n")
    for key, (label, _url) in BITWARDEN_SERVERS.items():
        print(f"  {key}) {label}")
    print("  3) Self-hosted (enter its URL)\n")
    choice = input("Choose [Enter = keep]: ").strip()
    if not choice:
        return True
    if choice in BITWARDEN_SERVERS:
        url = BITWARDEN_SERVERS[choice][1]
    elif choice == "3":
        url = input("Server URL (https://…): ").strip()
        if not url:
            return False
        if "://" not in url:
            url = "https://" + url
    else:
        print("Unknown choice.")
        return False
    if host_of(url) == host_of(current):
        return True
    result = run(["bw", "config", "server", url])
    if result.returncode != 0:
        print(last_line(result.stderr) or "Could not change the server.")
        return False
    print(f"Server set to {server_label(url)}.\n")
    return True


def _bw_tty(args: list[str], extra_env: dict | None = None) -> subprocess.CompletedProcess:
    """bw with prompts on the terminal and only stdout (the session key) captured.

    NODE_NO_WARNINGS hides node's punycode deprecation noise between prompts.
    """
    env = os.environ.copy()
    env.pop("BW_NOINTERACTION", None)
    env["NODE_NO_WARNINGS"] = "1"
    env.update(extra_env or {})
    return subprocess.run(["bw", *args], stdout=subprocess.PIPE, text=True, env=env)


def _finish_with_session(adapter, result: subprocess.CompletedProcess) -> bool:
    key = last_line(result.stdout)
    if result.returncode == 0 and key and " " not in key:
        adapter._store_session(key)
        print("\nSigned in. The vault is unlocked in the shell.")
        return True
    return False


def _login_with_api_key(adapter) -> bool:
    """Personal API key login, then unlock with the master password.

    Bitwarden refuses some CLI password logins (new-device protection,
    captcha, 503s) that the API key gets through. The key comes from the web
    vault: Settings → Security → Keys → View API key. It reaches bw through
    BW_CLIENTID / BW_CLIENTSECRET, never argv.
    """
    import getpass
    print("\nWeb vault → Settings → Security → Keys → View API key.")
    client_id = input("client_id: ").strip()
    client_secret = getpass.getpass("client_secret (hidden): ").strip()
    if not client_id or not client_secret:
        return False
    result = _bw_tty(["login", "--apikey"],
                     {"BW_CLIENTID": client_id, "BW_CLIENTSECRET": client_secret})
    client_secret = ""
    if result.returncode != 0:
        print("\nAPI key login failed.")
        return False
    print("\nSigned in. Now unlock with your master password:")
    return _finish_with_session(adapter, _bw_tty(["unlock", "--raw"]))


def bitwarden_terminal_login(adapter) -> None:
    if not choose_bitwarden_server():
        raise KeyboardInterrupt
    print("\nSign in with:\n  1) E-mail and master password\n  2) Personal API key (when 1 is refused)\n")
    method = input("Choose [1]: ").strip() or "1"
    if method == "2":
        if not _login_with_api_key(adapter):
            print("\nSign-in did not finish.")
        return
    debug = {"BITWARDENCLI_DEBUG": "true"} if os.environ.get("II_PASSWORDS_DEBUG") else {}
    result = _bw_tty(["login", "--raw"], debug)
    if _finish_with_session(adapter, result):
        return
    if "already logged in" in (result.stdout or "").lower():
        print("\nAlready signed in: unlock from the bar.")
        return
    print("\nBitwarden refused the e-mail login (a 503 here is usually its new-device")
    print("protection for the CLI, not an outage).")
    if input("Try the personal API key instead? [Y/n] ").strip().lower() in ("", "y", "s", "yes", "sim"):
        if not _login_with_api_key(adapter):
            print("\nSign-in did not finish.")


def interactive_login(adapter) -> int:
    """Run in a terminal: the CLI's own prompts (e-mail, password, 2FA).

    For bw, `--raw` prints only the session key on stdout while every prompt
    stays on the terminal, so the key goes straight to the session file and
    the vault comes back unlocked — no second password just to get in.
    """
    try:
        if adapter.name == "bitwarden":
            bitwarden_terminal_login(adapter)
        elif adapter.name == "rbw":
            subprocess.run(["rbw", "register"])
            subprocess.run(["rbw", "login"])
        else:
            print("pass needs no sign-in: run `pass init <gpg-id>` once.")
    except KeyboardInterrupt:
        print("\nCancelled.")
    try:
        input("\nPress Enter to close")
    except (EOFError, KeyboardInterrupt):
        pass
    return 0


def available() -> dict:
    return {name: bool(shutil.which(BINARIES[name])) for name in PROVIDERS}


def resolve(provider: str) -> str:
    found = available()
    if provider in PROVIDERS:
        if not found[provider]:
            raise BridgeError(f"{BINARIES[provider]} is not installed", "missing")
        return provider
    for name in PROVIDERS:
        if found[name]:
            return name
    raise BridgeError("No password manager CLI found", "missing")


# ── Entry point ─────────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["detect", "status", "unlock", "lock", "list",
                                            "sync", "copy", "type", "login"])
    parser.add_argument("--provider", default="auto")
    parser.add_argument("--id", default="")
    parser.add_argument("--field", default="password", choices=["password", "username", "totp"])
    parser.add_argument("--mode", default="password", choices=["password", "username", "login"])
    parser.add_argument("--clear", type=int, default=30)
    args = parser.parse_args(argv)

    if args.command == "detect":
        emit({"ok": True, "providers": available(), "wtype": bool(shutil.which("wtype"))})
        return 0

    try:
        name = resolve(args.provider)
    except BridgeError as err:
        if args.command == "status":
            emit({"ok": True, "provider": "", "state": "missing", "account": ""})
            return 0
        emit({"ok": False, "error": str(err), "code": err.code})
        return 0

    adapter = ADAPTERS[name]()
    if args.command == "login":
        return interactive_login(adapter)
    try:
        if args.command == "status":
            out = adapter.status()
        elif args.command == "unlock":
            password = sys.stdin.readline().rstrip("\n") if name == "bitwarden" else ""
            out = adapter.unlock(password)
            password = ""
        elif args.command == "lock":
            out = adapter.lock()
        elif args.command == "sync":
            out = adapter.sync()
        elif args.command == "list":
            out = adapter.list()
        elif args.command == "copy":
            if not args.id:
                raise BridgeError("No item", "empty")
            secret = adapter.secret(args.id, args.field)
            copy_to_clipboard(secret, max(0, args.clear))
            secret = ""
            out = {"field": args.field, "clear": max(0, args.clear)}
        else:  # type
            if not args.id:
                raise BridgeError("No item", "empty")
            parts: list[tuple[str, str]] = []
            if args.mode in ("username", "login"):
                parts.append(("text", adapter.secret(args.id, "username")))
            if args.mode == "login":
                parts.append(("key", "Tab"))
            if args.mode in ("password", "login"):
                parts.append(("text", adapter.secret(args.id, "password")))
            type_text(parts)
            parts.clear()
            out = {"mode": args.mode}
    except BridgeError as err:
        emit({"ok": False, "provider": name, "error": str(err), "code": err.code})
        return 0

    out.update({"ok": True, "provider": name})
    emit(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
