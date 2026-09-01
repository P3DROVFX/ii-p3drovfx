#!/usr/bin/env python3

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "file_browser_helper.py"


def run_helper(*arguments):
    result = subprocess.run(
        ["python3", str(HELPER), *map(str, arguments)],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.returncode, json.loads(result.stdout)


class FileBrowserHelperTests(unittest.TestCase):
    def test_listing_is_structured_safe_and_directories_first(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "folder with spaces").mkdir()
            (root / 'quote"file.txt').write_text("hello", encoding="utf-8")
            (root / ".hidden").write_text("secret", encoding="utf-8")

            code, reply = run_helper("list", root)
            self.assertEqual(code, 0)
            self.assertTrue(reply["ok"])
            self.assertEqual(reply["entries"][0]["name"], "folder with spaces")
            self.assertEqual({item["name"] for item in reply["entries"]}, {"folder with spaces", 'quote"file.txt'})
            self.assertIn("permissions", reply["entries"][0])

            _, hidden_reply = run_helper("list", root, "--hidden")
            self.assertIn(".hidden", {item["name"] for item in hidden_reply["entries"]})

    def test_inspection_returns_text_preview_and_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "sample.qml"
            target.write_text("Item { property string title: \"Preview\" }", encoding="utf-8")
            code, reply = run_helper("inspect", target, "--max-bytes", "16")
            self.assertEqual(code, 0)
            self.assertEqual(reply["entry"]["previewKind"], "text")
            self.assertTrue(reply["entry"]["previewTruncated"])
            self.assertEqual(reply["entry"]["owner"], reply["entry"]["owner"].strip())

    def test_create_rename_duplicate_and_copy_are_argv_driven(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "destination"
            destination.mkdir()

            code, created = run_helper("operate", "create-file", "--destination", root, "--name", "new file.txt")
            self.assertEqual(code, 0)
            source = Path(created["affected"][0])
            source.write_text("content", encoding="utf-8")

            code, renamed = run_helper("operate", "rename", "--path", source, "--name", "renamed.txt")
            self.assertEqual(code, 0)
            renamed_path = Path(renamed["affected"][0])
            self.assertTrue(renamed_path.exists())

            code, duplicate = run_helper("operate", "duplicate", "--path", renamed_path)
            self.assertEqual(code, 0)
            self.assertTrue(Path(duplicate["affected"][0]).exists())

            code, copied = run_helper(
                "operate", "copy", "--destination", destination,
                "--paths-json", json.dumps([str(renamed_path)]),
            )
            self.assertEqual(code, 0)
            self.assertEqual(Path(copied["affected"][0]).read_text(encoding="utf-8"), "content")

    def test_operation_rejects_path_separators_in_names(self):
        with tempfile.TemporaryDirectory() as directory:
            code, reply = run_helper("operate", "create-file", "--destination", directory, "--name", "../escape")
            self.assertNotEqual(code, 0)
            self.assertFalse(reply["ok"])
            self.assertFalse((Path(directory).parent / "escape").exists())

    def test_copy_rejects_a_directory_destination_inside_itself(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            child = root / "child"
            child.mkdir(parents=True)
            code, reply = run_helper(
                "operate", "copy", "--destination", child,
                "--paths-json", json.dumps([str(root)]),
            )
            self.assertNotEqual(code, 0)
            self.assertFalse(reply["ok"])
            self.assertIn("inside itself", reply["error"])

    def test_operations_preserve_literal_environment_variable_names(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / "destination"
            destination.mkdir()
            literal = root / "$FB_LITERAL_PATH"
            literal.write_text("literal", encoding="utf-8")

            environment = dict(os.environ)
            environment["FB_LITERAL_PATH"] = str(root / "different-file")
            result = subprocess.run(
                [
                    "python3", str(HELPER), "operate", "copy",
                    "--destination", str(destination),
                    "--paths-json", json.dumps([str(literal)]),
                ],
                capture_output=True,
                text=True,
                check=False,
                env=environment,
            )
            reply = json.loads(result.stdout)

            self.assertEqual(result.returncode, 0)
            self.assertEqual(Path(reply["affected"][0]).name, "$FB_LITERAL_PATH")
            self.assertEqual(Path(reply["affected"][0]).read_text(encoding="utf-8"), "literal")


if __name__ == "__main__":
    unittest.main()
