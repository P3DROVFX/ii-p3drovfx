#!/usr/bin/env python3
"""Contract and unit tests for link_preview.py."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import sys

# `scripts/notes` on the path, then a plain module import — the convention the other
# script tests here follow (see test_preset_store.py). `from scripts.notes...` only works
# if the repository root happens to be the working directory, which is why these three
# tests failed the moment they were run from anywhere else.
NOTES_DIR = str(Path(__file__).resolve().parents[1] / "notes")
if NOTES_DIR not in sys.path:
    sys.path.insert(0, NOTES_DIR)


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/notes/link_preview.py"

HTML_FIXTURE = """<!DOCTYPE html>
<html>
<head>
    <title>Original Page Title</title>
    <meta name="description" content="Standard description">
    <meta property="og:title" content="OpenGraph Title">
    <meta property="og:description" content="OpenGraph description about the page">
    <meta property="og:site_name" content="MySite">
    <meta property="og:image" content="/assets/cover.jpg">
    <link rel="icon" href="/favicon.png">
</head>
<body>
    <h1>Hello World</h1>
</body>
</html>
"""


class LinkPreviewTests(unittest.TestCase):
    def test_script_exists_and_is_executable(self):
        self.assertTrue(SCRIPT.exists())
        self.assertTrue(os.access(SCRIPT, os.X_OK))

    def test_invalid_scheme_rejected(self):
        for bad_url in ("file:///etc/passwd", "javascript:alert(1)", "ftp://example.com/file", ""):
            res = subprocess.run(
                [sys.executable, str(SCRIPT), bad_url],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res.returncode, 0)
            data = json.loads(res.stdout.strip())
            self.assertFalse(data["ok"])

    def test_no_network_mode(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            res = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "https://github.com/torvalds/linux",
                    "--cache-dir",
                    tmpdir,
                    "--no-network",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res.returncode, 0)
            data = json.loads(res.stdout.strip())
            self.assertTrue(data["ok"])
            self.assertEqual(data["domain"], "github.com")
            self.assertEqual(data["title"], "github.com")
            self.assertTrue(data.get("offline"))

    def test_metadata_parsing(self):
        from link_preview import parse_metadata

        meta = parse_metadata(HTML_FIXTURE, "https://example.com/article/1")
        self.assertEqual(meta["title"], "OpenGraph Title")
        self.assertEqual(meta["description"], "OpenGraph description about the page")
        self.assertEqual(meta["site_name"], "MySite")
        self.assertEqual(meta["image"], "https://example.com/assets/cover.jpg")
    def test_youtube_oembed_parser(self):
        from link_preview import fetch_youtube_oembed

        # Test with a real or mock-safe URL
        res = fetch_youtube_oembed("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        if res:  # If internet is accessible
            self.assertIn("Never Gonna Give You Up", res["title"])
            self.assertEqual(res["site_name"], "YouTube")
            self.assertTrue(res["image"].startswith("https://"))


if __name__ == "__main__":
    import os
    unittest.main()
