#!/usr/bin/env python3
"""Contract and behaviour tests for the notes store helper.

This one really runs the script, in a temporary directory. `notes_store.py` is the only
part of the store that touches the filesystem, so the things worth checking are the things
a filesystem can get wrong: a half-written index, a path that escapes the store, a
migration that half-succeeds, an asset that overwrites another one.
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/notes/notes_store.py"


def run(args, stdin=""):
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        input=stdin, capture_output=True, text=True, timeout=30,
    )
    lines = [line for line in result.stdout.splitlines() if line.strip()]
    # The contract is one JSON line and nothing else; a helper that printed twice would
    # give the QML side something it has no parser for.
    assert len(lines) == 1, f"expected one line, got {result.stdout!r} / {result.stderr!r}"
    return json.loads(lines[0])


class HelperContractTests(unittest.TestCase):
    def test_an_unknown_command_is_an_answer_not_a_crash(self):
        self.assertIn("error", run(["nonsense"]))
        self.assertIn("error", run(["purge"]))

    def test_bad_json_on_stdin_is_an_answer_not_a_crash(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertIn("error", run(["commit", folder], stdin="{not json"))
            self.assertIn("error", run(["commit", folder], stdin=""))


class TreeTests(unittest.TestCase):
    def test_init_creates_the_tree_and_reports_whether_a_store_was_there(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Path(folder) / "notes"
            first = run(["init", str(store)])
            self.assertTrue(first["ok"])
            self.assertFalse(first["hasIndex"])
            for name in ("docs", "assets", "revisions"):
                self.assertTrue((store / name).is_dir())

            (store / "index.json").write_text("{}", encoding="utf-8")
            # The whole migration decision hangs on this flag: a false negative migrates
            # a second time on top of a store that already exists.
            self.assertTrue(run(["init", str(store)])["hasIndex"])


class CommitTests(unittest.TestCase):
    def store(self, folder):
        store = Path(folder) / "notes"
        run(["init", str(store)])
        return store

    def test_files_are_written_as_json(self):
        with tempfile.TemporaryDirectory() as folder:
            store = self.store(folder)
            batch = {"files": [
                {"path": "index.json", "contents": {"schema": 1, "notes": []}},
                {"path": "docs/nt_1.json", "contents": {"id": "nt_1", "blocks": []}},
            ]}
            result = run(["commit", str(store)], json.dumps(batch))
            self.assertEqual(result["written"], ["index.json", "docs/nt_1.json"])
            self.assertEqual(json.loads((store / "index.json").read_text())["schema"], 1)

    def test_no_temporary_files_are_left_behind(self):
        # Writes go through a temporary in the same directory so a watcher never reads a
        # half-written index. What it must not do is leave the temporary there.
        with tempfile.TemporaryDirectory() as folder:
            store = self.store(folder)
            run(["commit", str(store)], json.dumps({"files": [{"path": "index.json", "contents": {}}]}))
            leftovers = [p.name for p in store.iterdir() if p.name.startswith(".tmp-")]
            self.assertEqual(leftovers, [])

    def test_a_path_that_escapes_the_store_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            store = self.store(folder)
            outside = Path(folder) / "outside.json"
            result = run(["commit", str(store)],
                         json.dumps({"files": [{"path": "../outside.json", "contents": {"x": 1}}]}))
            self.assertIn("error", result)
            self.assertFalse(outside.exists())

    def test_a_missing_sketch_does_not_take_the_note_down_with_it(self):
        # The old format stores an absolute path; the file it names may be long gone. The
        # note still migrates — a block naming a missing picture is recoverable, and
        # dropping the note is not.
        with tempfile.TemporaryDirectory() as folder:
            store = self.store(folder)
            result = run(["commit", str(store)], json.dumps({
                "files": [{"path": "index.json", "contents": {"schema": 1}}],
                "copies": [{"from": "/definitely/not/here.png", "to": "assets/nt_1/here.png"}],
            }))
            self.assertTrue(result["ok"])
            self.assertEqual(result["copied"], [])
            self.assertEqual(len(result["missing"]), 1)
            self.assertTrue((store / "index.json").exists())

    def test_assets_are_copied_under_the_note_that_owns_them(self):
        with tempfile.TemporaryDirectory() as folder:
            store = self.store(folder)
            source = Path(folder) / "sketch.png"
            source.write_bytes(b"PNG")
            run(["commit", str(store)], json.dumps({
                "copies": [{"from": str(source), "to": "assets/nt_1/sketch.png"}],
            }))
            self.assertEqual((store / "assets/nt_1/sketch.png").read_bytes(), b"PNG")
            # The original is copied, not moved: the tablet's live draw wrote it and may
            # still be pointing at it.
            self.assertTrue(source.exists())

    def test_the_legacy_file_is_renamed_and_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            store = self.store(folder)
            legacy = Path(folder) / "notes.json"
            backup = Path(folder) / "notes.json.migrated"
            backup.write_text("an older migration", encoding="utf-8")
            legacy.write_text("the current one", encoding="utf-8")

            result = run(["commit", str(store)],
                         json.dumps({"renames": [{"from": str(legacy), "to": str(backup)}]}))
            self.assertTrue(result["ok"])
            self.assertFalse(legacy.exists())
            # The first backup is somebody's only copy of their notes. A second migration
            # must not land on top of it.
            self.assertEqual(backup.read_text(), "an older migration")
            self.assertEqual(len(result["renamed"]), 1)
            self.assertTrue(Path(result["renamed"][0]).read_text() == "the current one")


class PurgeAndAssetTests(unittest.TestCase):
    def test_purge_takes_the_document_the_assets_and_the_revisions(self):
        # The reason assets are filed per note at all: today a sketch outlives the note
        # that showed it forever, because nothing records whose it was.
        with tempfile.TemporaryDirectory() as folder:
            store = Path(folder) / "notes"
            run(["init", str(store)])
            (store / "docs/nt_1.json").write_text("{}", encoding="utf-8")
            (store / "assets/nt_1").mkdir(parents=True)
            (store / "assets/nt_1/a.png").write_bytes(b"x")
            (store / "revisions/nt_1").mkdir(parents=True)
            (store / "docs/nt_2.json").write_text("{}", encoding="utf-8")

            run(["purge", str(store), "nt_1"])
            self.assertFalse((store / "docs/nt_1.json").exists())
            self.assertFalse((store / "assets/nt_1").exists())
            self.assertFalse((store / "revisions/nt_1").exists())
            self.assertTrue((store / "docs/nt_2.json").exists())

    def test_purge_refuses_an_id_that_is_a_path(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Path(folder) / "notes"
            run(["init", str(store)])
            for bad in ("../..", "a/b", "", "."):
                self.assertIn("error", run(["purge", str(store), bad]))
            self.assertTrue((store / "docs").is_dir())

    def test_importing_an_asset_never_overwrites_another_one(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Path(folder) / "notes"
            run(["init", str(store)])
            first = Path(folder) / "photo.png"
            first.write_bytes(b"one")
            second = Path(folder) / "sub"
            second.mkdir()
            (second / "photo.png").write_bytes(b"two")

            a = run(["import-asset", str(store), "nt_1", str(first)])
            b = run(["import-asset", str(store), "nt_1", str(second / "photo.png")])
            self.assertEqual(a["name"], "photo.png")
            self.assertNotEqual(b["name"], "photo.png")
            # A name already taken belongs to another block; reusing it would silently
            # change a picture elsewhere in the same note.
            self.assertEqual((store / "assets/nt_1/photo.png").read_bytes(), b"one")

    def test_importing_a_file_that_is_not_there_is_an_answer(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Path(folder) / "notes"
            run(["init", str(store)])
            self.assertIn("error", run(["import-asset", str(store), "nt_1", "/nope.png"]))


if __name__ == "__main__":
    unittest.main()
