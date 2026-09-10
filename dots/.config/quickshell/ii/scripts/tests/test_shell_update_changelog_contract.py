#!/usr/bin/env python3
"""Contract tests for the fork-update changelog: commit fetching and its consumers."""

import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/updates/fetch_commits.py"


def load_script():
    spec = importlib.util.spec_from_file_location("fetch_commits", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fake_item(index, body=""):
    message = f"feat(scope): change {index}" + (f"\n\n{body}" if body else "")
    return {
        "sha": f"{index:040x}",
        "commit": {"message": message, "author": {"name": "dev", "date": "2026-09-10T00:00:00Z"}},
    }


class FetchCommitsTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_script()

    def make_fetch(self, total, pages_seen):
        def fetch(slug, base, head, page):
            pages_seen.append(page)
            start = (page - 1) * self.mod.PER_PAGE
            batch = [fake_item(i) for i in range(start, min(total, start + self.mod.PER_PAGE))]
            return {"total_commits": total, "ahead_by": total, "commits": batch}
        return fetch

    def test_single_page_is_one_request_newest_first(self):
        pages = []
        out = self.mod.collect("o/r", "a", "b", fetch=self.make_fetch(40, pages))
        self.assertEqual(pages, [1])
        self.assertEqual(out["ahead"], 40)
        self.assertFalse(out["truncated"])
        self.assertEqual(len(out["commits"]), 40)
        self.assertEqual(out["commits"][0]["sha"], f"{39:040x}")

    def test_thousand_commits_page_until_complete(self):
        pages = []
        out = self.mod.collect("o/r", "a", "b", fetch=self.make_fetch(1000, pages))
        self.assertEqual(pages, [1, 2, 3, 4])
        self.assertEqual(len(out["commits"]), 1000)
        self.assertFalse(out["truncated"])

    def test_page_cap_marks_truncated(self):
        pages = []
        out = self.mod.collect("o/r", "a", "b", max_pages=2, fetch=self.make_fetch(1000, pages))
        self.assertEqual(pages, [1, 2])
        self.assertEqual(len(out["commits"]), 500)
        self.assertEqual(out["ahead"], 1000)
        self.assertTrue(out["truncated"])

    def test_exact_page_boundary_does_not_fetch_an_empty_page(self):
        pages = []
        self.mod.collect("o/r", "a", "b", fetch=self.make_fetch(250, pages))
        self.assertEqual(pages, [1])

    def test_body_is_split_and_capped(self):
        item = fake_item(1, body="x" * 500)
        reduced = self.mod.reduce_commit(item, 100)
        self.assertEqual(reduced["subject"], "feat(scope): change 1")
        self.assertTrue(reduced["body"].endswith("…"))
        self.assertEqual(len(reduced["body"]), 101)

    def test_non_object_response_is_failure(self):
        self.assertIsNone(self.mod.collect("o/r", "a", "b", fetch=lambda *a: []))


class ChangelogConsumersContractTests(unittest.TestCase):
    def test_update_service_runs_the_script_and_exposes_commits(self):
        text = (ROOT / "services/ShellUpdates.qml").read_text(encoding="utf-8")
        self.assertIn("updates/fetch_commits.py", text)
        for token in ("property var commits", "property bool commitsTruncated", "signal checkFinished", "function parseSubject", "compareUrl"):
            self.assertIn(token, text)

    def test_summary_service_is_gated_and_cached(self):
        text = (ROOT / "services/ShellUpdateSummary.qml").read_text(encoding="utf-8")
        for token in ("Ai.canSubmit", "aiSummaryMinCommits", "aiSummary", "shellUpdateSummaryPath", "AiTextTask", "attemptedTo", "tearingDown"):
            self.assertIn(token, text)

    def test_text_task_rejects_a_cut_stream(self):
        text = (ROOT / "services/ai/AiTextTask.qml").read_text(encoding="utf-8")
        self.assertIn('finishReason !== ""', text)
        self.assertIn("thinkingOverride = root.thinkingLevel", text)

    def test_gemini_flash_37_38_declare_a_thinking_floor_the_strategy_honours(self):
        catalog = (ROOT / "services/ai/ModelCatalog.qml").read_text(encoding="utf-8")
        strategy = (ROOT / "services/ai/GeminiApiStrategy.qml").read_text(encoding="utf-8")
        for version in ("3.7", "3.8"):
            start = catalog.index(f'value: "gemini-{version}-flash"')
            block = catalog[start:catalog.index("}", catalog.index("quirks", start))]
            self.assertIn('thinkingFloor: "low"', block)
        self.assertIn("quirks?.thinkingFloor", strategy)

    def test_config_declares_summary_options(self):
        text = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        self.assertIn("property bool aiSummary: false", text)
        self.assertIn("property int aiSummaryMinCommits: 10", text)


if __name__ == "__main__":
    unittest.main()
