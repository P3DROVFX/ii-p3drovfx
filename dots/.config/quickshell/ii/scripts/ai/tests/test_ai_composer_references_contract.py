"""Contracts for shared @ references in sidebar and Search composers."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
AI = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
SIDEBAR = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")
SEARCH = (ROOT / "modules" / "ii" / "overview" / "SearchWidget.qml").read_text(encoding="utf-8")
SEARCH_COMPOSER = (ROOT / "modules" / "ii" / "overview" / "AiSearchComposer.qml").read_text(encoding="utf-8")


class AiComposerReferencesTests(unittest.TestCase):
    def test_service_offers_visible_or_explicit_context_only(self):
        for token in (
            "function composerReferenceSources(): var",
            'token: "window"',
            'token: "clipboard"',
            "token: `file:${index + 1}`",
            "token: `chat:${index + 1}`",
            "function expandComposerReferences(text: string): string",
        ):
            with self.subTest(token=token):
                self.assertIn(token, AI)

    def test_both_submission_paths_expand_the_same_markers(self):
        self.assertIn("Ai.composerReferenceSources()", SIDEBAR)
        self.assertIn("Ai.expandComposerReferences(parsed.text)", SIDEBAR)
        self.assertIn("Ai.expandComposerReferences(parsed.text)", SEARCH)
        self.assertIn("@window or @clipboard", SEARCH_COMPOSER)


if __name__ == "__main__":
    unittest.main()
