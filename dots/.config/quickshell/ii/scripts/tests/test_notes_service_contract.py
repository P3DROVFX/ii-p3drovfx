#!/usr/bin/env python3
"""Regression contract for the single owner of the notes store."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SERVICE = (ROOT / "services/NotesService.qml").read_text(encoding="utf-8") if (ROOT / "services/NotesService.qml").exists() else ""
OVERLAY = (ROOT / "modules/ii/overlay/notes/NotesContent.qml").read_text(encoding="utf-8")
WIDGET = (ROOT / "modules/ii/background/widgets/utility/NotesWidget.qml").read_text(encoding="utf-8")
WIDGET_2X1 = (ROOT / "modules/ii/background/widgets/utility/NotesWidget2x1.qml").read_text(encoding="utf-8")
STORE = (ROOT / "services/notes/NotesStore.qml").read_text(encoding="utf-8")
DOCUMENT_FILE = (ROOT / "services/notes/NotesDocumentFile.qml").read_text(encoding="utf-8")
HELPER = (ROOT / "scripts/notes/notes_store.py").read_text(encoding="utf-8")


class NotesServiceContractTests(unittest.TestCase):
    def test_service_owns_atomic_files_and_write_guard(self):
        self.assertIn("pragma Singleton", SERVICE)
        self.assertIn("FileView", SERVICE)
        self.assertIn("property bool ready: false", SERVICE)
        self.assertIn("function append", SERVICE)
        self.assertIn("function create", SERVICE)
        self.assertIn("function updateTab", SERVICE)

    def test_every_write_to_the_store_is_atomic(self):
        # The guarantee did not change; the files it applies to did. There is no single
        # notes.json for the service to open any more — the index and each note's document
        # are written by services/notes/, and the multi-file work by the helper. A partial
        # write of the index is a store that looks corrupt to the watcher reading it.
        self.assertIn("atomicWrites: true", STORE)
        self.assertIn("atomicWrites: true", DOCUMENT_FILE)
        self.assertIn("os.replace", HELPER)

    def test_visual_consumers_do_not_own_file_view_or_notes_path(self):
        for source in (OVERLAY, WIDGET, WIDGET_2X1):
            self.assertNotIn("FileView", source)
            self.assertNotIn("Directories.notesPath", source)

    def test_service_exposes_provenance_without_prompt_storage(self):
        self.assertIn("provenance", SERVICE)
        self.assertIn("sessionId", SERVICE)
        self.assertIn("messageId", SERVICE)
        self.assertNotIn("prompt", SERVICE)


if __name__ == "__main__":
    unittest.main()
