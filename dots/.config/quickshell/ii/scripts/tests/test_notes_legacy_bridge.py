#!/usr/bin/env python3
"""The old notes surfaces must keep working, untouched.

The game overlay, the two desktop widgets, the tablet's live draw and the AI integration
all call `NotesService` directly, and none of them is being changed while the store
underneath them is replaced. That is the promise of this stage, and it is exactly the kind
of promise that decays quietly: a member gets renamed during a refactor, and nobody notices
until somebody opens the overlay.

So the test does not hold a list of API names to keep in step by hand. It reads what the
callers actually call and requires the service to declare every one of it.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SERVICE = ROOT / "services/NotesService.qml"
STORE = ROOT / "services/notes/NotesStore.qml"
DOCUMENT_FILE = ROOT / "services/notes/NotesDocumentFile.qml"
SHELL = ROOT / "shell.qml"

CONSUMERS = [
    ROOT / "modules/ii/overlay/notes/NotesContent.qml",
    ROOT / "modules/ii/overlay/notes/NotesSketchEditor.qml",
    ROOT / "modules/ii/background/widgets/utility/NotesWidget.qml",
    ROOT / "modules/ii/background/widgets/utility/NotesWidget2x1.qml",
    ROOT / "modules/tablet/liveDraw/TabletLiveDrawWindow.qml",
    ROOT / "modules/ii/cheatsheet/timetable/EventSidebar.qml",
    ROOT / "services/ai/integrations/AiNotesIntegration.qml",
    ROOT / "services/ai/AiTools.qml",
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def used_members() -> set:
    """Every `NotesService.<name>` any caller in the shell reaches for."""
    names = set()
    for path in CONSUMERS:
        if not path.exists():
            continue
        names |= set(re.findall(r"NotesService\.(\w+)", read(path)))
    return names


def declared_members() -> set:
    body = read(SERVICE)
    names = set(re.findall(r"^\s*function\s+(\w+)\s*\(", body, re.M))
    names |= set(re.findall(r"^\s*(?:readonly\s+)?property\s+\S+\s+(\w+)\s*:", body, re.M))
    names |= set(re.findall(r"^\s*signal\s+(\w+)\s*\(", body, re.M))
    return names


class LegacySurfaceTests(unittest.TestCase):
    def test_the_callers_were_actually_found(self):
        # A rename of a consumer file would otherwise make this whole test vacuously pass.
        self.assertGreaterEqual(sum(1 for path in CONSUMERS if path.exists()), 6)
        self.assertGreater(len(used_members()), 8)

    def test_every_member_the_old_surfaces_call_still_exists(self):
        missing = sorted(used_members() - declared_members())
        self.assertEqual(missing, [], f"NotesService no longer declares: {missing}")

    def test_the_shapes_those_surfaces_read_are_still_produced(self):
        body = read(SERVICE)
        # The desktop widgets and the overlay iterate `tabsData.tabs` and read these four
        # fields off every entry.
        for field in ("title:", "icon:", "content:", "sketch:"):
            self.assertIn(field, body)
        self.assertIn("property var tabsData", body)
        # `noteId` is what makes `replaceTabs` able to tell an edited list from a new one:
        # the callers all build theirs by slicing the array they were handed.
        self.assertIn("noteId: note.id", body)

    def test_a_saving_indicator_still_has_something_to_read(self):
        body = read(SERVICE)
        self.assertIn("property bool writing", body)
        self.assertIn("property var pendingData", body)


class OwnershipTests(unittest.TestCase):
    def test_only_the_store_opens_files(self):
        # One writer. Two FileViews over the same note is how a debounce and an AI append
        # race each other, which is the reason the old service was written this way too.
        service = read(SERVICE)
        views = re.findall(r"\bFileView\s*\{", service)
        self.assertEqual(len(views), 1, "NotesService should only open the legacy file")
        self.assertIn("id: legacyFile", service)

    def test_the_legacy_file_is_never_written(self):
        service = read(SERVICE)
        legacy = service[service.index("id: legacyFile"):]
        legacy = legacy[:legacy.index("\n    }")]
        for token in ("setText", "atomicWrites", "onSaved", "writer"):
            self.assertNotIn(token, legacy, "the legacy notes.json is read-only now")

    def test_the_legacy_file_is_only_opened_when_there_is_a_reason_to(self):
        # Reading a file that was deliberately renamed logs a failure on every startup,
        # for nothing.
        service = read(SERVICE)
        self.assertIn("legacyWanted", service)
        self.assertIn('path: root.legacyWanted ? Qt.resolvedUrl(Directories.notesPath) : ""', service)

    def test_each_note_has_its_own_writer_with_its_own_debounce(self):
        # The point of splitting the store: a keystroke in one note writes one file. A
        # single shared timer would mean flushing one note writes all of them.
        body = read(DOCUMENT_FILE)
        self.assertIn("required property string noteId", body)
        self.assertIn("atomicWrites: true", body)
        self.assertIn("id: debounce", body)
        self.assertIn("id: watchdog", body)
        # A write held back by continuous typing must still land.
        self.assertIn("maximumHold", body)

    def test_a_pending_write_is_never_dropped_on_destruction(self):
        self.assertIn("Component.onDestruction", read(DOCUMENT_FILE))
        self.assertIn("Component.onDestruction: root.flushAll()", read(STORE))


class BootstrapTests(unittest.TestCase):
    def test_readiness_is_declared_rather_than_called(self):
        # The index FileView loads as soon as its path is bound, usually before the helper
        # that creates the directory has finished — and `reload()` does not re-announce a
        # load when the content has not changed. Ordering-dependent settling never fired.
        body = read(STORE)
        self.assertIn("readonly property bool bootstrapped:", body)
        self.assertIn("onBootstrappedChanged: root.settle()", body)

    def test_a_migrated_index_is_adopted_rather_than_re_read(self):
        self.assertIn("function adoptIndex", read(STORE))
        self.assertIn("store.adoptIndex", read(SERVICE))

    def test_the_migration_renames_the_legacy_file_and_never_deletes_it(self):
        service = read(SERVICE)
        self.assertIn("Directories.notesLegacyBackupPath", service)
        self.assertNotIn("unlink", service)
        self.assertNotIn('"rm"', service)

    def test_the_singleton_is_instantiated_at_boot(self):
        # A QML singleton is created on first use. Left to that, the migration would run
        # whenever some surface happened to ask for a note first — mid-interaction, and
        # only on the machines where such a surface is enabled at all.
        self.assertIn("NotesService.ready;", read(SHELL))


if __name__ == "__main__":
    unittest.main()
