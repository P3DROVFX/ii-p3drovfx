#!/usr/bin/env python3
"""Source provenance and freshness contracts for the web integration."""

import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "scripts" / "ai" / "ai_web.py").read_text(encoding="utf-8")
class AiWebSourceTests(unittest.TestCase):
    def test_qml_tracks_source_freshness_and_keeps_a_short_cache(self):
        ai = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
        self.assertIn("property var webCache", ai)
        self.assertIn("webCacheTtlMs", ai)
        self.assertIn("function decorateWebPayload", ai)
        self.assertIn("fetchedAt", ai)
        self.assertIn("freshness", ai)
        self.assertIn("cacheHit: true", ai)

    def test_qml_respects_web_mode_off_before_running_a_process(self):
        ai = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
        self.assertIn('root.webMode === "off"', ai)

    def test_lite_duckduckgo_fallback_is_registered(self):
        self.assertIn("def duckduckgo_lite", SOURCE)
        self.assertIn("duckduckgo_lite", SOURCE)

    def test_lite_duckduckgo_parser_unwraps_results(self):
        import scripts.ai.ai_web as web

        fixture = """
        <a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fquickshell.org%2F" class='result-link'>Quickshell</a>
        <td class='result-snippet'>Install <b>Documentation</b> See your changes in real time.</td>
        """
        with patch.object(web, "get", return_value=fixture):
            results = web.duckduckgo_lite("Quickshell documentation", 3)

        self.assertEqual(results[0]["url"], "https://quickshell.org/")
        self.assertEqual(results[0]["title"], "Quickshell")
        self.assertIn("Documentation", results[0]["snippet"])


if __name__ == "__main__":
    unittest.main()
