#!/usr/bin/env python3
"""Contract tests for the isolated composer draft store."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "ai_drafts.py"


def call(*args: str, stdin: str | None = None) -> dict:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=stdin,
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(result.stdout)


class AiDraftContractTests(unittest.TestCase):
    def test_new_draft_round_trips_and_delete_is_independent(self):
        with tempfile.TemporaryDirectory() as directory:
            saved = call("save", directory, "__new__", stdin="unfinished prompt")
            self.assertTrue(saved["saved"])
            loaded = call("load", directory)
            self.assertEqual(loaded["drafts"]["__new__"]["text"], "unfinished prompt")
            call("delete", directory, "__new__")
            self.assertNotIn("__new__", call("load", directory)["drafts"])

    def test_truncated_store_is_preserved_and_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "drafts.json"
            path.write_text('{"schema":1,"drafts":', encoding="utf-8")
            result = call("load", directory)
            self.assertEqual(result["recovery"], "preserved")
            self.assertEqual(path.read_text(encoding="utf-8"), '{"schema":1,"drafts":')


if __name__ == "__main__":
    unittest.main()
