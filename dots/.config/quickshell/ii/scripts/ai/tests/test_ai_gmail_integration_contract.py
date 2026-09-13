#!/usr/bin/env python3
"""Contracts for the read-only Gmail AI boundary."""

import base64
import re
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts" / "ai" / "ai_gmail.py"
SOURCE = SCRIPT.read_text(encoding="utf-8")
ADAPTER = (ROOT / "services" / "ai" / "integrations" / "AiGmailIntegration.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")


class AiGmailContractTests(unittest.TestCase):
    def test_exactly_four_gmail_tools_are_declared(self):
        ids = re.findall(r'id: "(gmail_[a-z_]+)",', REGISTRY)
        self.assertEqual(
            ids,
            [
                "gmail_search_messages",
                "gmail_get_message",
                "gmail_get_thread",
                "gmail_open_in_client",
            ],
        )
        for tool_id in ids:
            block = REGISTRY.split(f'id: "{tool_id}"', 1)[1].split("\n        },", 1)[0]
            self.assertIn('requiredServices: ["gmail"]', block)
            self.assertIn('formats: ["gemini", "openai", "anthropic"]', block)
            self.assertIn("parameters:", block)

    def test_bridge_contains_no_mutating_email_operation(self):
        combined = (SOURCE + "\n" + ADAPTER).lower()
        for forbidden in ("send", "modify", "delete", "trash", "markasread", "mark_read", "download"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, combined)
        self.assertIn("format=metadata", SOURCE)
        self.assertIn("bodyMode", SOURCE)
        self.assertIn("metadata_dto", SOURCE)

    def test_message_body_is_second_and_explicit_request(self):
        import scripts.ai.ai_gmail as gmail

        plain_data = base64.urlsafe_b64encode(b"hello from the message").decode().rstrip("=")
        calls = []

        def fake_get(path, token):
            calls.append(path)
            if "format=metadata" in path:
                return {
                    "id": "m1",
                    "threadId": "t1",
                    "internalDate": "1700000000000",
                    "payload": {"headers": [{"name": "Subject", "value": "Subject"}, {"name": "From", "value": "a@example.com"}]},
                    "snippet": "snippet",
                }
            return {
                "id": "m1",
                "threadId": "t1",
                "payload": {"mimeType": "text/plain", "body": {"data": plain_data}},
            }

        with patch.object(gmail, "api_get", side_effect=fake_get):
            metadata = gmail.get_message("token", {"messageId": "m1"})
            self.assertEqual(metadata["bodyMode"], "metadata")
            self.assertEqual(len(calls), 1)
            calls.clear()
            full = gmail.get_message("token", {"messageId": "m1", "bodyMode": "plainText"})

        self.assertEqual(full["body"], "hello from the message")
        self.assertIn("format=metadata", calls[0])
        self.assertIn("format=full", calls[1])

    def test_search_is_bounded_metadata_only_and_keeps_pagination(self):
        import scripts.ai.ai_gmail as gmail

        calls = []

        def fake_get(path, token):
            calls.append(path)
            if path.startswith("/messages?"):
                return {"messages": [{"id": "m1"}, {"id": "m2"}], "nextPageToken": "next"}
            message_id = path.split("/messages/", 1)[1].split("?", 1)[0]
            return {"id": message_id, "threadId": "t1", "payload": {"headers": []}}

        with patch.object(gmail, "api_get", side_effect=fake_get):
            result = gmail.search_messages("token", {"query": "from:alice", "limit": 99, "pageToken": "p1"})

        self.assertEqual(result["limit"], 10)
        self.assertEqual(result["nextPageToken"], "next")
        self.assertEqual(len(result["messages"]), 2)
        self.assertTrue(all("format=full" not in path for path in calls))

    def test_ai_purchase_query_does_not_turn_recency_into_an_and_term(self):
        import scripts.ai.ai_gmail as gmail

        query = gmail.normalize_ai_search_query("(compras OR pedido OR recibo) (recente OR último OR novo)")
        self.assertEqual(query, "{compra compras pedido recibo}")

    def test_search_response_keeps_original_and_effective_query(self):
        import scripts.ai.ai_gmail as gmail

        with patch.object(gmail, "api_get", return_value={"messages": [], "nextPageToken": ""}):
            result = gmail.search_messages("token", {"query": "compra recente", "limit": 5})

        self.assertEqual(result["query"], "compra recente")
        self.assertIn("queryUsed", result)
        self.assertEqual(result["queryUsed"], "{compra compras pedido recibo}")

    def test_thread_metadata_precedes_explicit_bodies(self):
        import scripts.ai.ai_gmail as gmail

        calls = []
        plain_data = base64.urlsafe_b64encode(b"thread body").decode().rstrip("=")

        def fake_get(path, token):
            calls.append(path)
            if path.startswith("/threads/"):
                return {"messages": [{"id": "m1", "threadId": "t1", "payload": {"headers": []}}]}
            return {"id": "m1", "threadId": "t1", "payload": {"mimeType": "text/plain", "body": {"data": plain_data}}}

        with patch.object(gmail, "api_get", side_effect=fake_get):
            result = gmail.get_thread("token", {"threadId": "t1", "bodyMode": "plainText"})

        self.assertEqual(result["messages"][0]["body"], "thread body")
        self.assertIn("format=metadata", calls[0])
        self.assertIn("format=full", calls[1])


class QmlLoadabilityTests(unittest.TestCase):
    """Two structural bugs that text-only assertions above never touched.

    Both left the adapter file present and syntactically fine to `qmllint`,
    but broken the moment Quickshell actually tried to instantiate the type —
    which cascades: `Ai.qml` holds a `readonly property AiGmailIntegration
    gmailIntegration: AiGmailIntegration {}`, so a broken Gmail adapter took
    the whole `Ai` singleton down, and with it every other tool. Nothing
    running through `Ai` — Settings, files, OCR, none of it — worked while
    this was broken, and no earlier test in this file caught it because none
    of them load the file as QML.
    """

    def test_globalstates_and_persistent_are_actually_importable(self):
        # GlobalStates and Persistent live in the root `qs` module; the file
        # used `qs.modules.common` and `qs.services` only, so both types were
        # unresolved the moment `openInClient()` touched them. The failure
        # mode was not a lint warning: it was "Type AiGmailIntegration
        # unavailable" at runtime.
        self.assertIn("import qs\n", ADAPTER)
        self.assertIn("GlobalStates.cheatsheetOpen", ADAPTER)
        self.assertIn("Persistent.states.cheatsheet.tabIndex", ADAPTER)

    def test_the_request_component_is_a_named_property(self):
        # QtObject has no default property. A bare `Component { id:
        # requestComponent ... }` inside one has nowhere to attach, and fails
        # with "Cannot assign to non-existent default property" — this is
        # the same class of bug AiVoiceService hit for the same reason.
        self.assertIn("property Component requestComponent: Component {", ADAPTER)
        self.assertNotIn("\n    Component {\n        id: requestComponent", ADAPTER)


if __name__ == "__main__":
    unittest.main()
