#!/usr/bin/env python3
"""Contract and functional tests for Google Keep Takeout import."""

import json
import os
import shutil
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


# Import target
from keep_import import (
    parse_keep_note_json,
    convert_keep_to_document,
    import_from_directory_or_zip,
    export_to_takeout_directory
)


class TestNotesKeepImport(unittest.TestCase):
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp(prefix="test_keep_"))
        self.store_dir = self.temp_dir / "store"
        self.takeout_dir = self.temp_dir / "takeout"
        self.store_dir.mkdir(parents=True, exist_ok=True)
        self.takeout_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(str(self.temp_dir), ignore_errors=True)

    def test_parse_text_note_with_labels_and_color(self):
        sample = {
            "title": "Projeto Alpha",
            "textContent": "Primeiro parágrafo de texto.\n\nSegundo parágrafo detalhado.",
            "color": "RED",
            "labels": [{"name": "Trabalho"}, {"name": "Importante"}],
            "isPinned": True,
            "isArchived": False,
            "createdTimestampUsec": 1690000000000000,
            "userEditedTimestampUsec": 1691000000000000
        }

        parsed = parse_keep_note_json(sample, "projeto_alpha.json")
        self.assertEqual(parsed["title"], "Projeto Alpha")
        self.assertEqual(parsed["tone"], "error") # RED -> error
        self.assertIn("#Trabalho", parsed["tags"])
        self.assertIn("#Importante", parsed["tags"])
        self.assertTrue(parsed["isPinned"])
        self.assertEqual(parsed["created"], 1690000000000)
        self.assertEqual(parsed["modified"], 1691000000000)

    def test_parse_checklist_note(self):
        sample = {
            "title": "Tarefas Semanais",
            "listContent": [
                {"text": "Comprar café", "isChecked": True},
                {"text": "Revisar PR do Notes", "isChecked": False}
            ],
            "color": "GREEN"
        }

        parsed = parse_keep_note_json(sample, "checklist.json")
        doc = convert_keep_to_document(parsed, "nt_test_1")

        self.assertEqual(parsed["title"], "Tarefas Semanais")
        self.assertEqual(len(parsed["listContent"]), 2)

        # First block should be heading
        self.assertEqual(doc["blocks"][0]["type"], "heading")
        self.assertEqual(doc["blocks"][0]["text"], "Tarefas Semanais")

        # Second block checkbox checked
        self.assertEqual(doc["blocks"][1]["type"], "list")
        self.assertEqual(doc["blocks"][1]["style"], "checkbox")
        self.assertTrue(doc["blocks"][1]["checked"])
        self.assertEqual(doc["blocks"][1]["text"], "Comprar café")

        # Third block checkbox unchecked
        self.assertEqual(doc["blocks"][2]["type"], "list")
        self.assertFalse(doc["blocks"][2]["checked"])
        self.assertEqual(doc["blocks"][2]["text"], "Revisar PR do Notes")

    def test_idempotent_import_does_not_duplicate(self):
        # Create a mock takeout folder with 2 notes
        note1 = {
            "title": "Nota Unica",
            "textContent": "Conteudo original",
            "createdTimestampUsec": 1680000000000000
        }
        note2 = {
            "title": "Nota Check",
            "listContent": [{"text": "Item A", "isChecked": False}],
            "createdTimestampUsec": 1681000000000000
        }

        (self.takeout_dir / "nota_1.json").write_text(json.dumps(note1), encoding="utf-8")
        (self.takeout_dir / "nota_2.json").write_text(json.dumps(note2), encoding="utf-8")

        # First import run
        res1 = import_from_directory_or_zip(self.takeout_dir, self.store_dir)
        self.assertTrue(res1["ok"])
        self.assertEqual(res1["imported"], 2)
        self.assertEqual(res1["updated"], 0)

        index1 = json.loads((self.store_dir / "index.json").read_text(encoding="utf-8"))
        self.assertEqual(len(index1["notes"]), 2)

        # Modify note1 in takeout
        note1["textContent"] = "Conteudo modificado e atualizado"
        (self.takeout_dir / "nota_1.json").write_text(json.dumps(note1), encoding="utf-8")

        # Second import run (must update, not duplicate)
        res2 = import_from_directory_or_zip(self.takeout_dir, self.store_dir)
        self.assertTrue(res2["ok"])
        self.assertEqual(res2["imported"], 0)
        self.assertEqual(res2["updated"], 2)

        index2 = json.loads((self.store_dir / "index.json").read_text(encoding="utf-8"))
        self.assertEqual(len(index2["notes"]), 2, "Duplicate notes were created!")

    def test_export_to_takeout_format(self):
        # Seed store with an imported note
        note = {
            "title": "Nota Exportavel",
            "textContent": "Linha 1\nLinha 2",
            "labels": [{"name": "teste"}],
            "createdTimestampUsec": 1680000000000000
        }
        (self.takeout_dir / "orig.json").write_text(json.dumps(note), encoding="utf-8")
        import_from_directory_or_zip(self.takeout_dir, self.store_dir)

        out_takeout = self.temp_dir / "out_takeout"
        exp_res = export_to_takeout_directory(self.store_dir, out_takeout)
        self.assertTrue(exp_res["ok"])
        self.assertEqual(exp_res["exported"], 1)

        exported_files = list(out_takeout.glob("*.json"))
        self.assertEqual(len(exported_files), 1)

        exp_data = json.loads(exported_files[0].read_text(encoding="utf-8"))
        self.assertEqual(exp_data["title"], "Nota Exportavel")
        self.assertIn("Linha 1", exp_data["textContent"])


if __name__ == "__main__":
    unittest.main()
