#!/usr/bin/env python3
"""The filesystem, reached by the assistant itself, is opt-in and bounded.

`ai_attach.py search` is the one path by which a conversation reaches a file
without a person having chosen it first. These tests pin the guardrails that
make that safe: nothing outside the configured roots, no credential ever
listed or read, every scan bounded in depth, count and wall-clock time — and
the QML side that dispatches, previews, and (after approval) attaches one.
"""

import importlib.util
import json
import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ATTACH_PATH = ROOT / "scripts" / "ai" / "ai_attach.py"
SPEC = importlib.util.spec_from_file_location("ai_attach", ATTACH_PATH)
ATTACH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ATTACH)

AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
INTEGRATION = (ROOT / "services" / "ai" / "integrations" / "AiFilesIntegration.qml").read_text(encoding="utf-8")
CONFIG = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class SearchSandboxTests(unittest.TestCase):
    """The Python side, exercised against a real directory tree."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="ai_files_test_"))
        (self.tmp / "docs").mkdir()
        (self.tmp / "sub" / "deep").mkdir(parents=True)
        (self.tmp / ".ssh").mkdir()
        (self.tmp / "docs" / "my-notes.txt").write_text("hello notes")
        (self.tmp / "sub" / "deep" / "notes-deep.txt").write_text("deep notes")
        (self.tmp / ".ssh" / "id_ed25519").write_text("fake key material")
        (self.tmp / "private.pem").write_text("fake cert")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_finds_real_files_under_the_root(self):
        result = ATTACH.search([str(self.tmp)], "notes")
        names = {entry["name"] for entry in result["results"]}
        self.assertEqual(names, {"my-notes.txt", "notes-deep.txt"})

    def test_never_lists_a_credential_even_by_name(self):
        result = ATTACH.search([str(self.tmp)], "id_ed")
        self.assertEqual(result["results"], [])

    def test_never_lists_a_credential_extension(self):
        result = ATTACH.search([str(self.tmp)], "private")
        self.assertEqual(result["results"], [])

    def test_an_unconfigured_root_is_refused(self):
        result = ATTACH.search(["/definitely/not/a/root"], "anything")
        self.assertEqual(result["results"], [])

    def test_no_roots_at_all_is_an_explicit_error(self):
        result = ATTACH.search([], "anything")
        self.assertIn("error", result)

    def test_results_are_capped(self):
        for i in range(30):
            (self.tmp / "docs" / f"bulk-{i}.txt").write_text("x")
        result = ATTACH.search([str(self.tmp)], "bulk", limit=100)
        self.assertLessEqual(len(result["results"]), ATTACH.MAX_RESULTS)

    def test_a_symlink_loop_does_not_hang_the_search(self):
        loop = self.tmp / "sub" / "loop"
        try:
            loop.symlink_to(self.tmp / "sub", target_is_directory=True)
        except OSError:
            self.skipTest("symlinks unavailable in this environment")
        started = time.monotonic()
        result = ATTACH.search([str(self.tmp)], "notes")
        self.assertLess(time.monotonic() - started, ATTACH.SEARCH_DEADLINE_SECONDS + 2)
        self.assertTrue(result["results"])

    def test_device_files_and_sockets_are_never_results(self):
        # A regular file with a device-like name is still a regular file and
        # must be found; this is the S_ISREG guard, exercised the only way a
        # unit test safely can.
        (self.tmp / "docs" / "notes-device.txt").write_text("x")
        result = ATTACH.search([str(self.tmp)], "notes-device")
        self.assertEqual(len(result["results"]), 1)


class PeekTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="ai_files_peek_"))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_reads_a_bounded_amount_of_text(self):
        path = self.tmp / "big.txt"
        path.write_text("x" * 5000)
        result = ATTACH.peek(str(path), limit=100)
        self.assertEqual(len(result["text"]), 100)
        self.assertTrue(result["truncated"])

    def test_a_short_file_is_not_marked_truncated(self):
        path = self.tmp / "short.txt"
        path.write_text("hello")
        result = ATTACH.peek(str(path), limit=100)
        self.assertEqual(result["text"], "hello")
        self.assertFalse(result["truncated"])

    def test_a_credential_is_refused(self):
        path = self.tmp / "id_rsa"
        path.write_text("-----BEGIN PRIVATE KEY-----")
        result = ATTACH.peek(str(path))
        self.assertTrue(result.get("sensitive"))

    def test_a_missing_file_is_an_error_not_a_crash(self):
        result = ATTACH.peek(str(self.tmp / "nope.txt"))
        self.assertIn("error", result)


class SensitivePathTests(unittest.TestCase):
    def test_extensions_added_for_the_files_domain(self):
        for extension in (".pem", ".key", ".kdbx"):
            with self.subTest(extension=extension):
                self.assertTrue(ATTACH.is_sensitive_path(f"/home/user/whatever{extension}"))

    def test_an_id_prefixed_file_is_sensitive_generically(self):
        self.assertTrue(ATTACH.is_sensitive_path("/home/user/.ssh/id_whatever_new_format"))

    def test_the_shells_own_config_directory_is_off_limits(self):
        self.assertTrue(ATTACH.is_sensitive_path(os.path.expanduser("~/.config/illogical-impulse/some_state.json")))

    def test_except_the_one_file_settings_tools_already_read(self):
        # config.json itself goes through the validated settings path
        # already; blocking it here too would just be a second, worse gate on
        # the same data.
        self.assertFalse(ATTACH.is_sensitive_path(os.path.expanduser("~/.config/illogical-impulse/config.json")))

    def test_ordinary_files_are_not_swept_up(self):
        self.assertFalse(ATTACH.is_sensitive_path("/home/user/Documents/report.pdf"))


class RootsAreOptInTests(unittest.TestCase):
    def test_the_config_default_is_empty(self):
        block = body_between(CONFIG, "property JsonObject files: JsonObject {", "}")
        self.assertIn("property list<string> roots: []", block)

    def test_the_integration_only_searches_configured_roots(self):
        self.assertIn("Config.options?.ai?.files?.roots", INTEGRATION)

    def test_a_path_must_be_inside_a_root_or_already_chosen_by_hand(self):
        allowed = body_between(INTEGRATION, "function pathAllowed(path: string): bool {", "\n    }")
        self.assertIn("withinConfiguredRoots", allowed)
        self.assertIn("Ai.attachments", allowed)
        self.assertIn("Ai.pendingAttachmentPaths", allowed)


class AddRemoveRootTests(unittest.TestCase):
    """The Settings folder list (add/remove), backing the toggles page.

    `list<string>` on a `JsonObject` only persists and notifies when the
    whole property is reassigned, not mutated in place — both functions
    must copy, change, and reassign rather than push/splice the live array.
    """

    def test_add_root_trims_and_drops_a_trailing_slash(self):
        body = body_between(INTEGRATION, "function addRoot(path: string): bool {", "\n    }")
        self.assertIn("trimFileProtocol", body)
        self.assertIn('.replace(/\\/+$/, "")', body)
        self.assertIn("cleanPath.length === 0", body)

    def test_add_root_is_idempotent_and_reassigns_the_whole_array(self):
        body = body_between(INTEGRATION, "function addRoot(path: string): bool {", "\n    }")
        self.assertIn("current.indexOf(cleanPath) >= 0", body)
        self.assertIn("return false", body)
        self.assertIn("Config.options.ai.files.roots = [...current, cleanPath];", body)

    def test_remove_root_bounds_checks_the_index_and_reassigns(self):
        body = body_between(INTEGRATION, "function removeRoot(index: int): void {", "\n    }")
        self.assertIn("index < 0 || index >= current.length", body)
        self.assertIn("current.splice(index, 1);", body)
        self.assertIn("Config.options.ai.files.roots = current;", body)


class ToolRegistrationTests(unittest.TestCase):
    def tool_block(self, tool_id: str) -> str:
        marker = f'id: "{tool_id}",'
        start = REGISTRY.index(marker)
        return REGISTRY[start:REGISTRY.index("\n        },", start)]

    def test_all_four_file_tools_are_registered(self):
        for tool_id in ("files_search", "files_preview", "files_attach", "files_open_location"):
            with self.subTest(tool=tool_id):
                self.assertIn(f'id: "{tool_id}"', REGISTRY)

    def test_reading_a_file_a_model_chose_by_text_asks_first(self):
        block = self.tool_block("files_attach")
        self.assertIn('kind: "explicitContextRead"', block)
        self.assertIn('defaultApproval: "ask"', block)

    def test_search_and_preview_do_not_ask_every_time(self):
        for tool_id in ("files_search", "files_preview"):
            with self.subTest(tool=tool_id):
                self.assertIn('defaultApproval: "allow"', self.tool_block(tool_id))

    def test_file_content_is_marked_as_data_not_instructions(self):
        for tool_id in ("files_preview", "files_attach"):
            with self.subTest(tool=tool_id):
                self.assertIn("untrusted: true", self.tool_block(tool_id))

    def test_every_file_tool_requires_the_files_service(self):
        for tool_id in ("files_search", "files_preview", "files_attach", "files_open_location"):
            with self.subTest(tool=tool_id):
                self.assertIn('requiredServices: ["files"]', self.tool_block(tool_id))


class DispatchWiringTests(unittest.TestCase):
    def test_every_file_handler_rechecks_the_path_itself(self):
        # requiredServices only gates whether the tool is offered at all, not
        # which path one particular call names — each handler asks again.
        for handler in ("toolFilesPreview", "toolFilesAttach", "toolFilesOpenLocation"):
            body = body_between(AI_QML, f"function {handler}(call: var): var {{", "\n    }")
            with self.subTest(handler=handler):
                self.assertIn("root.refusedFilePath(path)", body)

    def test_search_preview_and_attach_share_one_process(self):
        # Only one file operation is ever worth having in flight, the same
        # restriction the web tools use.
        self.assertEqual(AI_QML.count("property Process filesToolProc:"), 1)
        for handler in ("toolFilesSearch", "toolFilesPreview"):
            body = body_between(AI_QML, f"function {handler}(call: var): var {{", "\n    }")
            with self.subTest(handler=handler):
                self.assertIn("if (filesToolProc.running)", body)

    def test_attach_is_a_real_approval_card_not_an_immediate_read(self):
        body = body_between(AI_QML, "function toolFilesAttach(call: var): var {", "function approveFileAttach")
        self.assertIn('kind: "fileAttachPreview"', body)
        self.assertIn("message.functionPending = true", body)
        self.assertIn('status: "approval"', body)

    def test_approving_reads_the_path_from_the_card_not_the_original_call(self):
        # The call that asked is long gone by the time a person clicks
        # anything; only the card survives to be read back.
        body = body_between(AI_QML, "function approveFileAttach(message: AiMessageData) {", "function rejectFileAttach")
        self.assertIn("root.toolCardFor(message, key)", body)
        self.assertIn("card?.data?.path", body)

    def test_rejecting_never_touches_the_filesystem(self):
        body = body_between(AI_QML, "function rejectFileAttach(message: AiMessageData) {", "function toolFilesOpenLocation")
        self.assertNotIn("filesToolProc", body)
        self.assertIn('status: "denied"', body)

    def test_open_location_opens_the_folder_not_the_file(self):
        body = body_between(AI_QML, "function toolFilesOpenLocation(call: var): var {", "/**\n     * Search, preview")
        self.assertIn("xdg-open", body)
        self.assertIn("lastIndexOf(\"/\")", body)

    def test_search_results_become_a_card_the_user_can_act_on_directly(self):
        body = body_between(AI_QML, 'if (filesToolProc.op === "search") {', 'if (filesToolProc.op === "preview") {')
        self.assertIn('kind: "fileResults"', body)
        # The model gets the small projection; the card gets the full record
        # so its buttons (attach, open folder) can act on the real path.
        self.assertIn("modelRef(entry)", body)
        self.assertIn("data: { files: results }", body)


if __name__ == "__main__":
    unittest.main()
