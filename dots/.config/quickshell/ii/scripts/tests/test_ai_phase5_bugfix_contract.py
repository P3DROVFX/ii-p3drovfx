#!/usr/bin/env python3
"""Regression contracts for the Phase 5 approval and wallpaper fixes."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
BROKER = (ROOT / "services/ai/AiToolBroker.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
SONG_CARD = (ROOT / "services/ai/blocks/AiSongIdentifyCard.qml").read_text(encoding="utf-8")
THEME = (ROOT / "services/ai/integrations/AiThemeIntegration.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class ApprovalLifecycleTests(unittest.TestCase):
    def test_completed_model_round_keeps_its_approval_owner(self):
        finished = body_between(AI, "function onRunFinished(run: var)", "function commitRunSession")
        self.assertIn("root.broker.pendingCount", finished)
        self.assertIn("!waitingOnApproval", finished)

    def test_approval_can_start_after_the_provider_round_completed(self):
        begin = body_between(AI, "function beginToolExecution(message: AiMessageData", "function markToolNeedsInspection")
        self.assertIn('run.state === "completed"', begin)
        self.assertIn("root.broker.isPending(approvalKey)", begin)
        self.assertIn("completedRunOwnsApproval", begin)


class ApprovalRenderingTests(unittest.TestCase):
    def test_cards_that_call_ai_import_the_service_namespace_they_use(self):
        for name in (
            "AiFileAttachCard.qml",
            "AiMediaControlCard.qml",
            "AiNotesCard.qml",
            "AiReminderCard.qml",
            "AiSystemControlCard.qml",
            "AiWallpaperCard.qml",
            "AiWindowMoveCard.qml",
        ):
            card = (ROOT / "services/ai/blocks" / name).read_text(encoding="utf-8")
            with self.subTest(card=name):
                self.assertIn("import qs.services", card)


class SongIconTests(unittest.TestCase):
    def test_song_identification_uses_a_glyph_present_in_the_bundled_font(self):
        self.assertNotIn('"music_search"', SONG_CARD)
        self.assertNotIn('icon: "music_search"', REGISTRY)
        self.assertIn('text: root.listening ? "graphic_eq" : "music_note"', SONG_CARD)
        self.assertIn('icon: "music_note"', REGISTRY)


class WallpaperSearchTests(unittest.TestCase):
    def test_wallpaper_search_reads_plain_list_model_roles(self):
        self.assertIn("const entry = model.get(i);", THEME)
        self.assertIn("entry?.filePath", THEME)
        self.assertIn("entry?.fileName", THEME)
        self.assertIn("entry?.fileUrl", THEME)
        self.assertNotIn('model.get(i, "filePath")', THEME)
        self.assertNotIn('model.get(i, "fileName")', THEME)
        self.assertNotIn('model.get(i, "fileURL")', THEME)


if __name__ == "__main__":
    unittest.main()
