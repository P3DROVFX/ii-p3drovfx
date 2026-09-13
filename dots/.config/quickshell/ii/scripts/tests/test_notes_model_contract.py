#!/usr/bin/env python3
"""Contract tests for the notes document model.

The behaviour of the model is checked by `tests/notes/*.qml` under qmltestrunner. What
this file guards is the set of properties that a behavioural test cannot see: that the
model stayed pure, that the migration cannot write, and that the JavaScript keeps to the
subset QML's engine actually implements.

That last one is not theoretical. A lookbehind assertion parses fine under Node and
silently never matches under QML, so a table row arrives as one cell containing the whole
line and nothing anywhere reports an error.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

DOCUMENT = ROOT / "services/notes/NotesDocument.js"
MARKDOWN = ROOT / "services/notes/NotesMarkdown.js"
MIGRATION = ROOT / "services/notes/NotesMigration.js"
SEARCH_INDEX = ROOT / "services/notes/NotesSearchIndex.js"
DIRECTORIES = ROOT / "modules/common/Directories.qml"
DRY_RUN = ROOT / "scripts/notes/migrate_dry_run.js"

MODEL_FILES = (DOCUMENT, MARKDOWN, MIGRATION, SEARCH_INDEX)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class NotesModelLayoutTests(unittest.TestCase):
    def test_the_model_files_are_where_the_shell_and_the_tests_look(self):
        for path in MODEL_FILES:
            self.assertTrue(path.exists(), f"missing {path.relative_to(ROOT)}")
        for name in ("tst_NotesDocument.qml", "tst_NotesMarkdown.qml", "tst_NotesMigration.qml", "tst_NotesSearchIndex.qml"):
            self.assertTrue((ROOT / "tests/notes" / name).exists(), f"missing tests/notes/{name}")

    def test_each_model_file_is_a_qml_javascript_library(self):
        for path in MODEL_FILES:
            first = read(path).splitlines()[0].strip()
            self.assertEqual(first, ".pragma library", f"{path.name} must open with .pragma library")


class QmlJavaScriptSubsetTests(unittest.TestCase):
    def test_no_lookbehind_assertions(self):
        # Accepted by Node, silently inert under QML's engine. The failure mode is a
        # regex that never matches rather than an error anyone would notice.
        for path in MODEL_FILES:
            self.assertNotIn("(?<", read(path), f"{path.name} uses a lookbehind, which QML ignores")

    def test_exported_declarations_use_var(self):
        # A `.pragma library` exports its top-level `function` and `var` declarations.
        # `const` and `let` are scoped out of that in both QML and the Node loader, so a
        # constant declared with them exists for the file and for nobody else.
        for path in MODEL_FILES:
            for number, line in enumerate(read(path).splitlines(), start=1):
                match = re.match(r"^(const|let)\s", line)
                if match:
                    self.fail(f"{path.name}:{number} declares a top-level {match.group(1)}")


class ModelPurityTests(unittest.TestCase):
    def test_the_model_knows_nothing_about_qml_or_the_shell(self):
        # Pure so it can be checked without starting a shell, and so the same code can be
        # driven from Node by the dry run.
        forbidden = ("import QtQuick", "Quickshell", "FileView", "Qt.resolvedUrl", "Config.options")
        for path in MODEL_FILES:
            body = read(path)
            for token in forbidden:
                self.assertNotIn(token, body, f"{path.name} reaches for {token}")

    def test_the_migration_cannot_touch_the_filesystem(self):
        # It returns a description of the store that should exist. The caller writes it —
        # which is what lets the same function answer "what would you do" without being
        # allowed to do it.
        body = read(MIGRATION)
        for token in ("require(", "readFile", "writeFile", "mkdir", "unlink", "rename"):
            self.assertNotIn(token, body, f"NotesMigration.js reaches for {token}")

    def test_the_dry_run_only_reads(self):
        body = read(DRY_RUN)
        for token in ("writeFileSync", "writeFile(", "mkdirSync", "appendFile", "unlinkSync", "renameSync", "rmSync"):
            self.assertNotIn(token, body, f"the dry run reaches for {token}")
        self.assertIn("readFileSync", body)


def block_types() -> list:
    body = read(DOCUMENT)
    table = re.search(r"var BLOCK_FIELDS = \{(.*?)\n\};", body, re.S)
    assert table, "BLOCK_FIELDS table not found"
    return re.findall(r"^\s{4}(\w+):", table.group(1), re.M)


class SchemaCoverageTests(unittest.TestCase):
    def test_the_table_is_the_schema_and_it_is_not_empty(self):
        types = block_types()
        self.assertGreaterEqual(len(types), 10)
        for required in ("text", "heading", "list", "code", "image", "ink", "table"):
            self.assertIn(required, types)

    def test_every_block_type_can_be_written_as_markdown(self):
        # A type with no case falls through to null and is dropped from an export without
        # a word — the one bug in this area that loses user content.
        body = read(MARKDOWN)
        for kind in block_types():
            self.assertIn(f'case "{kind}":', body, f"{kind} has no markdown serialisation")

    def test_every_operation_in_the_dispatch_has_an_implementation(self):
        body = read(DOCUMENT)
        dispatch = re.search(r"function applyOne\(document, op\) \{(.*?)\n\}", body, re.S)
        self.assertIsNotNone(dispatch)
        for kind in re.findall(r'case "(\w+)": return (\w+)', dispatch.group(1)):
            self.assertIn(f"function {kind[1]}(", body, f"{kind[0]} dispatches to a missing function")

    def test_every_operation_returns_an_inverse(self):
        # Undo, revision history and conflict resolution all read the inverse. An
        # operation that changed something and returned none is a hole in every one of
        # them, and the hole only shows up later.
        body = read(DOCUMENT)
        for match in re.finditer(r"function op\w+\(document, op\) \{(.*?)\n\}", body, re.S):
            chunk = match.group(1)
            if "changed: true" not in chunk:
                continue
            self.assertIn("inverse:", chunk, "an operation reports a change with no inverse")


class DirectoriesTests(unittest.TestCase):
    def test_the_store_paths_are_declared(self):
        body = read(DIRECTORIES)
        for name in ("notesDir", "notesIndexPath", "notesDocsDir", "notesAssetsDir",
                     "notesRevisionsDir", "notesLegacyBackupPath"):
            self.assertIn(f"property string {name}:", body, f"Directories is missing {name}")

    def test_the_store_lives_in_state_not_cache(self):
        # Notes cannot be re-fetched from anywhere. A cache directory is a directory
        # something else is entitled to empty.
        body = read(DIRECTORIES)
        line = next(l for l in body.splitlines() if "property string notesDir:" in l)
        self.assertIn("${Directories.state}", line)
        self.assertNotIn("cache", line)

    def test_the_legacy_file_is_renamed_and_not_deleted(self):
        body = read(DIRECTORIES)
        self.assertIn("notesLegacyBackupPath", body)
        self.assertIn("${Directories.notesPath}.migrated", body)


if __name__ == "__main__":
    unittest.main()
