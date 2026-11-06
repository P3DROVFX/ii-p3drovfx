"""End-to-end tests for scripts/password_manager.py against a fake `bw`.

The fake CLI keeps its vault state in a temp dir and checks the session key it
gets through BW_SESSION, so these cover the real contract: secrets never come
out on stdout, the session never travels in argv, copies go to wl-copy.
"""

import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "password_manager.py"

FAKE_BW = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import json, os, sys
    state_dir = os.environ["FAKE_STATE"]
    log = open(os.path.join(state_dir, "argv.log"), "a")
    log.write(json.dumps(sys.argv[1:]) + "\n")
    unlocked_file = os.path.join(state_dir, "unlocked")
    SESSION = "fake-session-key"
    def unlocked():
        return os.path.exists(unlocked_file) and os.environ.get("BW_SESSION") == SESSION
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    items = [
        {"id": "a1", "type": 1, "name": "GitHub", "favorite": True, "folderId": "f1",
         "login": {"username": "octo", "password": "hunter2", "totp": "JBSWY3DP",
                   "uris": [{"uri": "https://www.github.com/login"}]}},
        {"id": "b2", "type": 1, "name": "Mail", "folderId": None,
         "login": {"username": "me@mail.test", "password": "s3cret", "uris": []}},
        {"id": "n3", "type": 2, "name": "A note", "notes": "private"},
    ]
    if cmd == "status":
        print(json.dumps({"status": "unlocked" if unlocked() else "locked",
                          "userEmail": "me@mail.test", "serverUrl": None}))
    elif cmd == "unlock":
        if os.environ.get("BW_PASSWORD") == "correct horse":
            open(unlocked_file, "w").close(); print(SESSION)
        else:
            print("Invalid master password.", file=sys.stderr); sys.exit(1)
    elif cmd == "lock":
        if os.path.exists(unlocked_file): os.remove(unlocked_file)
        print("Your vault is locked.")
    elif not unlocked():
        print("Vault is locked.", file=sys.stderr); sys.exit(1)
    elif cmd == "list" and sys.argv[2] == "items":
        print(json.dumps(items))
    elif cmd == "list" and sys.argv[2] == "folders":
        print(json.dumps([{"id": "f1", "name": "Dev"}]))
    elif cmd == "get":
        field, item_id = sys.argv[2], sys.argv[3]
        item = next(i for i in items if i["id"] == item_id)
        value = {"password": item["login"]["password"], "username": item["login"]["username"],
                 "totp": "123456"}[field]
        sys.stdout.write(value)
    elif cmd == "sync":
        print("Syncing complete.")
''').lstrip()

FAKE_WL_COPY = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import json, os, sys
    data = sys.stdin.read()
    with open(os.path.join(os.environ["FAKE_STATE"], "clipboard.json"), "w") as f:
        json.dump({"argv": sys.argv[1:], "data": data}, f)
''').lstrip()


def write_exec(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


class BitwardenBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.state = root / "state"
        self.state.mkdir()
        self.runtime = root / "run"
        self.runtime.mkdir(mode=0o700)
        write_exec(self.bin / "bw", FAKE_BW)
        write_exec(self.bin / "wl-copy", FAKE_WL_COPY)
        # timeout is a real coreutil; keep the system PATH after our fakes.
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin",
                        FAKE_STATE=str(self.state), XDG_RUNTIME_DIR=str(self.runtime))

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, *args, stdin=None):
        result = subprocess.run([sys.executable, str(SCRIPT), *args, "--provider", "bitwarden"],
                                input=stdin, capture_output=True, text=True, env=self.env,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout), result.stdout

    def unlock(self):
        out, _ = self.call("unlock", stdin="correct horse\n")
        self.assertTrue(out["ok"], out)

    def test_starts_locked(self):
        out, _ = self.call("status")
        self.assertEqual(out["state"], "locked")
        self.assertEqual(out["account"], "me@mail.test")

    def test_wrong_password_is_an_auth_error(self):
        out, _ = self.call("unlock", stdin="nope\n")
        self.assertFalse(out["ok"])
        self.assertEqual(out["code"], "auth")

    def test_unlock_stores_a_private_session(self):
        self.unlock()
        session = self.runtime / "ii-passwords" / "bw-session"
        self.assertEqual(stat.S_IMODE(session.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(session.parent.stat().st_mode), 0o700)
        out, _ = self.call("status")
        self.assertEqual(out["state"], "unlocked")

    def test_session_and_password_never_in_argv(self):
        self.unlock()
        self.call("list")
        log = (self.state / "argv.log").read_text()
        self.assertNotIn("fake-session-key", log)
        self.assertNotIn("correct horse", log)
        self.assertNotIn("--session", log)

    def test_list_has_no_secrets(self):
        self.unlock()
        out, raw = self.call("list")
        self.assertEqual([i["name"] for i in out["items"]], ["GitHub", "Mail"])
        github = out["items"][0]
        self.assertEqual(github["host"], "github.com")
        self.assertEqual(github["folder"], "Dev")
        self.assertTrue(github["totp"])
        self.assertFalse(out["items"][1]["totp"])
        for secret in ("hunter2", "s3cret", "JBSWY3DP", "private"):
            self.assertNotIn(secret, raw)

    def test_copy_goes_to_wl_copy_not_stdout(self):
        self.unlock()
        out, raw = self.call("copy", "--id", "a1", "--field", "password", "--clear", "30")
        self.assertTrue(out["ok"], out)
        self.assertNotIn("hunter2", raw)
        clip = self.wait_clipboard()
        self.assertEqual(clip["data"], "hunter2")
        self.assertIn("--sensitive", clip["argv"])
        self.assertIn("--foreground", clip["argv"])

    def test_copy_totp(self):
        self.unlock()
        self.call("copy", "--id", "a1", "--field", "totp")
        self.assertEqual(self.wait_clipboard()["data"], "123456")

    def test_stale_session_is_dropped(self):
        self.unlock()
        (self.state / "unlocked").unlink()  # locked behind our back
        out, _ = self.call("status")
        self.assertEqual(out["state"], "locked")
        self.assertFalse((self.runtime / "ii-passwords" / "bw-session").exists())

    def test_lock_removes_session(self):
        self.unlock()
        out, _ = self.call("lock")
        self.assertEqual(out["state"], "locked")
        self.assertFalse((self.runtime / "ii-passwords" / "bw-session").exists())
        out, _ = self.call("list")
        self.assertFalse(out["ok"])
        self.assertEqual(out["code"], "locked")

    def test_missing_cli_reports_missing_state(self):
        # A fake HOME too: the helper also looks in ~/.nvm, ~/.cargo/bin…
        env = dict(self.env, PATH="/nonexistent", HOME=self.tmp.name, NVM_DIR=self.tmp.name)
        result = subprocess.run([sys.executable, str(SCRIPT), "status"], capture_output=True,
                                text=True, env=env, timeout=30)
        self.assertEqual(json.loads(result.stdout)["state"], "missing")

    def wait_clipboard(self):
        path = self.state / "clipboard.json"
        for _ in range(100):
            if path.exists() and path.stat().st_size > 0:
                try:
                    return json.loads(path.read_text())
                except json.JSONDecodeError:
                    pass
            subprocess.run(["sleep", "0.05"])
        self.fail("wl-copy was never called")


class HelperTests(unittest.TestCase):
    def setUp(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("password_manager", SCRIPT)
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)

    def test_host_of(self):
        self.assertEqual(self.mod.host_of("https://www.example.com/a"), "example.com")
        self.assertEqual(self.mod.host_of("example.org"), "example.org")
        self.assertEqual(self.mod.host_of(""), "")

    def test_control_chars_are_refused(self):
        self.assertTrue(self.mod.has_control_chars("a\tb"))
        self.assertFalse(self.mod.has_control_chars("pässwörd!"))


if __name__ == "__main__":
    unittest.main()
