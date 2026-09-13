#!/usr/bin/env python3
"""A task title is data, all the way to the API.

The service used to compose `curl ... -d '<json>'` as one string and hand it
to `bash -c`. A title with an apostrophe broke the request; a title with
`'; ...; '` in it ran a command. That title can come from the user, and — once
the assistant can create tasks — from an email or a web page it read. These
tests pin the shape that makes the class of bug impossible: JSON in, JSON out,
no shell anywhere, and the token off the command line.
"""

import importlib.util
import io
import json
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
API_PATH = ROOT / "scripts" / "ticktick" / "api.py"
SPEC = importlib.util.spec_from_file_location("ticktick_api", API_PATH)
API = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(API)
API_SOURCE = API_PATH.read_text(encoding="utf-8")
SERVICE_QML = (ROOT / "services" / "TickTickService.qml").read_text(encoding="utf-8")

HOSTILE_TITLES = (
    "comprar pão'; id > /tmp/pwn; echo '",
    'reunião com "aspas" e $(whoami)',
    "rm -rf ~ && echo done",
    "back\\slash and `backtick`",
    "linha um\nlinha dois",
)


class RequestBuildingTests(unittest.TestCase):
    def captured_request(self, payload):
        """Runs one operation and returns the urllib Request it built."""
        seen = {}

        class Response:
            status = 200

            def read(self):
                return b'{"id": "abc123", "title": "ok"}'

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        def fake_urlopen(request, timeout=None):
            seen["request"] = request
            return Response()

        with mock.patch.object(API.urllib.request, "urlopen", fake_urlopen):
            result = API.run(payload)
        return seen.get("request"), result

    def test_a_hostile_title_stays_a_title(self):
        for title in HOSTILE_TITLES:
            with self.subTest(title=title):
                request, result = self.captured_request(
                    {"token": "t", "op": "create", "title": title})
                self.assertTrue(result["ok"])
                body = json.loads(request.data.decode("utf-8"))
                # Byte for byte what was asked for, escaped only as JSON.
                self.assertEqual(body["title"], title)

    def test_the_token_travels_in_a_header_not_an_argument(self):
        request, _ = self.captured_request({"token": "secret-token", "op": "create", "title": "x"})
        self.assertEqual(request.headers["Authorization"], "Bearer secret-token")

    def test_a_task_id_is_quoted_into_the_path(self):
        request, _ = self.captured_request(
            {"token": "t", "op": "delete", "taskId": "../../project/other", "projectId": "inbox"})
        self.assertNotIn("../", request.full_url)

    def test_optional_fields_pass_through(self):
        request, _ = self.captured_request({
            "token": "t", "op": "create", "title": "pagar conta",
            "dueDate": "2026-08-22T09:00:00+0000", "priority": 3,
        })
        body = json.loads(request.data.decode("utf-8"))
        self.assertEqual(body["dueDate"], "2026-08-22T09:00:00+0000")
        self.assertEqual(body["priority"], 3)

    def test_update_uses_the_real_task_id_and_only_sends_changes(self):
        request, result = self.captured_request({
            "token": "t", "op": "update", "taskId": "task/with spaces",
            "projectId": "project", "content": "notes", "dueDate": "2026-08-22T09:00:00+0000",
        })
        self.assertTrue(result["ok"])
        self.assertIn("/task/task%2Fwith%20spaces", request.full_url)
        body = json.loads(request.data.decode("utf-8"))
        self.assertEqual(body, {"projectId": "project", "content": "notes", "dueDate": "2026-08-22T09:00:00+0000"})

    def test_update_without_changes_is_refused_before_the_network(self):
        with mock.patch.object(API.urllib.request, "urlopen", mock.Mock(side_effect=AssertionError("should not be called"))):
            result = API.run({"token": "t", "op": "update", "taskId": "task-1"})
        self.assertFalse(result["ok"])

    def test_an_empty_title_is_refused_before_the_network(self):
        with mock.patch.object(API.urllib.request, "urlopen",
                               mock.Mock(side_effect=AssertionError("should not be called"))):
            result = API.run({"token": "t", "op": "create", "title": "   "})
        self.assertFalse(result["ok"])

    def test_a_missing_token_is_refused_before_the_network(self):
        with mock.patch.object(API.urllib.request, "urlopen",
                               mock.Mock(side_effect=AssertionError("should not be called"))):
            result = API.run({"op": "list"})
        self.assertFalse(result["ok"])

    def test_an_unknown_operation_is_refused(self):
        result = API.run({"token": "t", "op": "send_all_my_data"})
        self.assertFalse(result["ok"])


class ResultTests(unittest.TestCase):
    def test_a_real_status_comes_back(self):
        def failing(request, timeout=None):
            raise urllib.error.HTTPError(request.full_url, 401, "Unauthorized", {}, io.BytesIO(b""))

        with mock.patch.object(API.urllib.request, "urlopen", failing):
            result = API.run({"token": "stale", "op": "list"})
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 401)
        self.assertIn("Reconnect", result["error"])

    def test_an_unreachable_api_is_an_error_not_a_crash(self):
        def offline(request, timeout=None):
            raise urllib.error.URLError("no route to host")

        with mock.patch.object(API.urllib.request, "urlopen", offline):
            result = API.run({"token": "t", "op": "list"})
        self.assertFalse(result["ok"])
        self.assertEqual(result["status"], 0)

    def test_the_reply_says_which_operation_it_answers(self):
        with mock.patch.object(API, "run", return_value={"ok": True, "status": 200}):
            with mock.patch("sys.stdin.readline", return_value='{"op": "create", "callId": "c1"}\n'):
                with mock.patch("builtins.print") as printed:
                    API.main()
        payload = json.loads(printed.call_args[0][0])
        self.assertEqual(payload["op"], "create")
        self.assertEqual(payload["callId"], "c1")

    def test_a_broken_request_line_does_not_raise(self):
        with mock.patch("sys.stdin.readline", return_value="not json\n"):
            with mock.patch("builtins.print") as printed:
                self.assertEqual(API.main(), 0)
        self.assertFalse(json.loads(printed.call_args[0][0])["ok"])


class NoShellTests(unittest.TestCase):
    def test_the_helper_never_reaches_a_shell(self):
        # The module docstring recounts the bug being fixed, so it is the code
        # below the docstring that has to be clean.
        code = API_SOURCE.split('"""', 2)[2]
        for forbidden in ("subprocess", "os.system", "os.popen", "shell=True", "bash", "popen"):
            with self.subTest(token=forbidden):
                self.assertNotIn(forbidden, code)

    def test_the_service_no_longer_builds_command_lines(self):
        self.assertNotIn("bash", SERVICE_QML)
        self.assertNotIn("curl", SERVICE_QML)
        # Assigning into command[2] was how the shell string got in.
        self.assertNotIn("command[2]", SERVICE_QML)

    def test_the_service_sends_json_on_stdin(self):
        send = SERVICE_QML.split("function send(process, payload)", 1)[1].split("function refresh()", 1)[0]
        self.assertIn("stdinEnabled", SERVICE_QML)
        self.assertIn("process.write(JSON.stringify", send)
        self.assertIn("token: root.accessToken", send)

    def test_the_service_reads_the_reply_instead_of_assuming_success(self):
        create = SERVICE_QML.split("// Create task", 1)[1].split("// Complete task", 1)[0]
        self.assertIn("root.readReply(text", create)
        self.assertIn("taskCreated(", create)


if __name__ == "__main__":
    unittest.main()
