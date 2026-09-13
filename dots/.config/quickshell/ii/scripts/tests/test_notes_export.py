#!/usr/bin/env python3
"""Contract and functional tests for Universal Notes Export Engine."""

import json
import os
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

import sys

# `scripts/notes` on the path, then a plain module import — the convention the other
# script tests here follow (see test_preset_store.py). `from scripts.notes...` only works
# if the repository root happens to be the working directory, which is why these three
# tests failed the moment they were run from anywhere else.
NOTES_DIR = str(Path(__file__).resolve().parents[1] / "notes")
if NOTES_DIR not in sys.path:
    sys.path.insert(0, NOTES_DIR)


# Import target
from notes_export import (
    document_to_markdown,
    document_to_html,
    export_notes
)


class TestNotesExport(unittest.TestCase):
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp(prefix="test_export_"))
        self.store_dir = self.temp_dir / "store"
        self.out_dir = self.temp_dir / "output"
        self.store_dir.mkdir(parents=True, exist_ok=True)
        self.out_dir.mkdir(parents=True, exist_ok=True)

        (self.store_dir / "docs").mkdir(parents=True, exist_ok=True)
        (self.store_dir / "assets").mkdir(parents=True, exist_ok=True)

        # Create sample note in store
        self.note_id = "nt_export_sample"
        self.sample_doc = {
            "id": self.note_id,
            "schema": 1,
            "blocks": [
                {"id": "b1", "type": "heading", "level": 1, "text": "Título Principal"},
                {"id": "b2", "type": "text", "text": "Este é um parágrafo demonstrativo."},
                {"id": "b3", "type": "list", "style": "checkbox", "checked": True, "text": "Item concluído"},
                {"id": "b4", "type": "list", "style": "checkbox", "checked": False, "text": "Item pendente"},
                {"id": "b5", "type": "code", "language": "python", "text": "print('hello world')"},
                {"id": "b6", "type": "callout", "tone": "info", "text": "Dica importante em callout."},
                {"id": "b7", "type": "table", "columns": 2, "rows": [["Chave", "Valor"], ["A", "1"], ["B", "2"]]}
            ]
        }

        self.sample_meta = {
            "id": self.note_id,
            "title": "Título Principal",
            "tags": ["#projeto", "#release"],
            "created": 1695000000000,
            "modified": 1696000000000
        }

        (self.store_dir / "docs" / f"{self.note_id}.json").write_text(
            json.dumps(self.sample_doc), encoding="utf-8"
        )
        (self.store_dir / "index.json").write_text(
            json.dumps({"schema": 1, "notes": [self.sample_meta], "notebooks": []}), encoding="utf-8"
        )

    def tearDown(self):
        shutil.rmtree(str(self.temp_dir), ignore_errors=True)

    def test_document_to_markdown_formatting(self):
        md = document_to_markdown(self.sample_doc, self.sample_meta, asset_prefix="assets/")
        self.assertIn('title: "Título Principal"', md)
        self.assertIn("#projeto", md)
        self.assertIn("# Título Principal", md)
        self.assertIn("Este é um parágrafo demonstrativo.", md)
        self.assertIn("- [x] Item concluído", md)
        self.assertIn("- [ ] Item pendente", md)
        self.assertIn("```python", md)
        self.assertIn("print('hello world')", md)
        self.assertIn("> [!NOTE]", md)
        self.assertIn("| Chave | Valor |", md)

    def test_document_to_html_formatting(self):
        html_out = document_to_html(self.sample_doc, self.sample_meta, self.store_dir)
        self.assertIn("<!DOCTYPE html>", html_out)
        self.assertIn("<h1>Título Principal</h1>", html_out)
        self.assertIn("Item concluído", html_out)
        self.assertIn('class="lang-python"', html_out)
        self.assertIn('callout-info', html_out)
        self.assertIn("<table>", html_out)

    def test_export_markdown_files(self):
        dest_md = self.out_dir / "md_export"
        res = export_notes(self.store_dir, "markdown", dest_md, export_all=True)
        self.assertTrue(res["ok"])
        self.assertEqual(res["count"], 1)

        exported_files = list(dest_md.glob("*.md"))
        self.assertEqual(len(exported_files), 1)
        content = exported_files[0].read_text(encoding="utf-8")
        self.assertIn("Título Principal", content)

    def test_export_html_file(self):
        dest_html = self.out_dir / "exported_note.html"
        res = export_notes(self.store_dir, "html", dest_html, note_id=self.note_id)
        self.assertTrue(res["ok"])
        self.assertEqual(res["count"], 1)
        self.assertTrue(dest_html.exists())
        self.assertIn("<!DOCTYPE html>", dest_html.read_text(encoding="utf-8"))

    def test_export_zip_archive(self):
        dest_zip = self.out_dir / "backup.zip"
        res = export_notes(self.store_dir, "zip", dest_zip, export_all=True)
        self.assertTrue(res["ok"])
        self.assertTrue(dest_zip.exists())

        with zipfile.ZipFile(str(dest_zip), "r") as zf:
            namelist = zf.namelist()
            self.assertIn("index.json", namelist)
            self.assertIn(f"docs/{self.note_id}.json", namelist)


if __name__ == "__main__":
    unittest.main()
