#!/usr/bin/env python3
"""Contract tests for wallpaper search, preview and theme actions."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
ADAPTER = (ROOT / "services/ai/integrations/AiThemeIntegration.qml").read_text(encoding="utf-8") if (ROOT / "services/ai/integrations/AiThemeIntegration.qml").exists() else ""


class AiThemeContractTests(unittest.TestCase):
    def test_registry_exposes_wallpaper_search_and_set(self):
        for tool_id in ("wallpaper_search", "wallpaper_set", "theme_set_mode"):
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        self.assertIn('network: "optional"', REGISTRY)
        self.assertIn('description: "Use the exact ref returned by wallpaper_search', REGISTRY)

    def test_adapter_is_configured_source_only_and_has_thumbnail_undo(self):
        self.assertIn("Wallpapers.sortedFolderModel", ADAPTER)
        self.assertIn("function search", ADAPTER)
        self.assertIn("function previewSet", ADAPTER)
        self.assertIn("thumbnail", ADAPTER)
        self.assertIn("undo", ADAPTER)
        self.assertIn("Wallpapers.apply", ADAPTER)
        self.assertNotIn("hyprctl", ADAPTER)

    def test_ai_has_reviewed_wallpaper_flow(self):
        self.assertIn("toolWallpaperSearch", AI)
        self.assertIn("toolWallpaperSet", AI)
        self.assertIn("approveWallpaperSet", AI)
        self.assertIn("rejectWallpaperSet", AI)
        self.assertIn('"wallpaper_set": pending', AI)


if __name__ == "__main__":
    unittest.main()
