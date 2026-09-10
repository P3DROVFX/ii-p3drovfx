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

    def test_recent_mode_lists_the_branch_newest_first(self):
        seen = []

        def fetch(slug, branch, count):
            seen.append((slug, branch, count))
            return [fake_item(i) for i in (9, 8, 7)]

        out = self.mod.collect_recent("o/r", "dev", 3, fetch=fetch)
        self.assertEqual(seen, [("o/r", "dev", 3)])
        self.assertEqual(out["ahead"], 0)
        self.assertFalse(out["truncated"])
        self.assertEqual([c["sha"] for c in out["commits"]], [f"{i:040x}" for i in (9, 8, 7)])

    def test_recent_mode_rejects_a_non_list(self):
        self.assertIsNone(self.mod.collect_recent("o/r", "dev", 3, fetch=lambda *a: {"message": "rate limited"}))

    def test_recent_flag_needs_only_the_slug(self):
        # Both forms are parsed by main(); a wrong arity prints the usage.
        self.assertEqual(self.mod.main([]), 2)
        self.assertEqual(self.mod.main(["o/r", "--recent=5", "a", "b"]), 2)


class ChangelogConsumersContractTests(unittest.TestCase):
    def test_update_service_runs_the_script_and_exposes_commits(self):
        text = (ROOT / "services/ShellUpdates.qml").read_text(encoding="utf-8")
        self.assertIn("updates/fetch_commits.py", text)
        for token in ("property var commits", "property bool commitsTruncated", "signal checkFinished", "function parseSubject", "compareUrl",
                      "property var recentCommits", "function loadRecent", "--recent="):
            self.assertIn(token, text)

    def test_every_checkout_change_runs_in_a_terminal(self):
        # The setup script restarts the shell partway through; a run owned by
        # this process would die with it. Nothing but the terminal launcher may
        # start the script, and the pages must go through the service.
        text = (ROOT / "services/ShellUpdates.qml").read_text(encoding="utf-8")
        for token in ("function launchInTerminal", "function launchUpdate", "function launchBranchSwitch", "function launchForkSwitch", "Press Enter to close"):
            self.assertIn(token, text)
        self.assertIn('"update", "--keep-config"', text)
        self.assertIn('"switch", "--branch"', text)
        self.assertIn('"switch", "--fork"', text)
        indicator = (ROOT / "modules/ii/bar/widgets/indicators/ShellUpdateIndicator.qml").read_text(encoding="utf-8")
        self.assertIn("ShellUpdates.launchUpdate()", indicator)
        self.assertNotIn("execDetached", indicator)
        about = (ROOT / "modules/settings/configs/AboutConfig.qml").read_text(encoding="utf-8")
        self.assertIn("ShellUpdates.launchUpdate()", about)
        self.assertIn("GlobalStates.settingsOpen = false", about)
        for token in ("systemd-run", "Process {", "ansiToRich"):
            self.assertNotIn(token, about)
        # Fork and branch switching is inline on the page, behind one dialog.
        for token in ("WindowDialog", "ShellUpdates.launchBranchSwitch", "ShellUpdates.launchForkSwitch"):
            self.assertIn(token, about)

    def test_about_page_folds_the_list_only_with_ai_summaries(self):
        about = (ROOT / "modules/settings/configs/AboutConfig.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property bool listsFold: Config.options.update.aiSummary", about)
        self.assertIn("collapsible: root.listsFold", about)
        self.assertIn("ShellUpdates.recentCommits", about)
        # Review asked for no sub-pages: the lineage grid and the credited
        # contributors sit on the page itself.
        self.assertFalse((ROOT / "modules/settings/configs/widgets/ForkBranchConfig.qml").exists())
        self.assertFalse((ROOT / "modules/settings/configs/widgets/ShellLineageConfig.qml").exists())
        self.assertNotIn("ForkBranchConfig", (ROOT / "modules/common/SettingsPageRegistry.qml").read_text(encoding="utf-8"))
        self.assertIn('Quickshell.shellPath("CONTRIBUTORS.json")', about)
        self.assertIn("avatars.githubusercontent.com", about)

    def test_contributors_file_is_well_formed(self):
        # The credited people are data at the top of the tree, not code, so
        # the fork's author can edit them without touching QML.
        import json
        with (ROOT / "CONTRIBUTORS.json").open(encoding="utf-8") as handle:
            data = json.load(handle)
        people = data["contributors"]
        self.assertGreaterEqual(len(people), 1)
        for person in people:
            self.assertTrue(person.get("login"))
            self.assertTrue(person.get("name"))
            self.assertTrue(person.get("role"))
        self.assertFalse((ROOT / "services/ChangelogService.qml").exists())
        widget = (ROOT / "modules/common/widgets/ShellUpdateChangelog.qml").read_text(encoding="utf-8")
        self.assertIn("property var commits: ShellUpdates.commits", widget)

    def test_dead_updater_options_are_gone_and_migrated(self):
        text = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        self.assertNotIn("property string scriptFlags", text)
        self.assertNotIn("property string scriptPath: \"\"", text[text.index("property JsonObject update:"):text.index("property JsonObject update:") + 400])
        self.assertIn("delete raw.update.scriptFlags", text)
        self.assertIn("currentConfigVersion: 20", text)
        helper = (ROOT / "scripts/presets_helper.py").read_text(encoding="utf-8")
        self.assertNotIn("update.scriptPath", helper)
        self.assertNotIn("update.scriptFlags", helper)

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
