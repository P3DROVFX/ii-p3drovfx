#!/usr/bin/env python3
"""Contract tests for MPRIS, lyrics and reviewed song identification tools."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
ADAPTER = (ROOT / "services/ai/integrations/AiMediaIntegration.qml").read_text(encoding="utf-8")
SONGREC = (ROOT / "scripts/musicRecognition/recognize-music.sh").read_text(encoding="utf-8")


class AiMediaContractTests(unittest.TestCase):
    def test_registry_exposes_media_tools_with_network_and_approval_rules(self):
        for tool_id in ("media_status", "media_control", "lyrics_get", "song_identify"):
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        self.assertIn('id: "lyrics_get"', REGISTRY)
        self.assertIn('network: "optional"', REGISTRY)
        self.assertIn('id: "song_identify"', REGISTRY)
        self.assertIn('defaultApproval: "ask"', REGISTRY)

    def test_adapter_uses_existing_services_and_bounds_lyrics(self):
        for token in ("MprisController", "LyricsService", "SongRec", "function status", "function control", "function lyrics", "function identify"):
            self.assertIn(token, ADAPTER)
        self.assertIn("temporaryAudioDeleted", ADAPTER)
        self.assertNotIn("Quickshell.exec", ADAPTER)

    def test_ai_has_reviewed_control_and_identification_flow(self):
        for token in ("toolMediaStatus", "toolMediaControl", "approveMediaControl", "rejectMediaControl", "toolLyricsGet", "toolSongIdentify", "approveSongIdentify", "rejectSongIdentify", "pendingSongIdentify", "finishSongIdentify"):
            self.assertIn(token, AI)
        self.assertIn('"media_control": pending', AI)
        self.assertIn('"song_identify": pending', AI)
        self.assertIn('rm -f "$FIFO"', SONGREC)


if __name__ == "__main__":
    unittest.main()
