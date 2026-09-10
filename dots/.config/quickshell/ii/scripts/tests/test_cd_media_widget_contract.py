"""Regression contract for CD media artwork and its unclipped shadow."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CD_MEDIA = ROOT / "modules/ii/background/widgets/media/CdMediaWidget.qml"


class CdMediaWidgetContractTests(unittest.TestCase):
    def setUp(self):
        self.source = CD_MEDIA.read_text(encoding="utf-8")

    def test_artwork_refreshes_from_the_derived_path_on_startup(self):
        self.assertIn("function refreshArt()", self.source)
        self.assertIn("onArtFilePathChanged: root.refreshArt()", self.source)
        self.assertIn("Component.onCompleted: root.refreshArt()", self.source)
        self.assertIn("if (root.isLocalArt)\n            return root.rawArtUrl;", self.source)
        self.assertIn("return root.downloaded ? Qt.resolvedUrl(root.artFilePath) : \"\";", self.source)
        self.assertIn("root.downloaded = exitCode === 0;", self.source)

    def test_artwork_shadow_has_room_to_fade_below_the_viewport(self):
        self.assertIn("id: albumArtShadow", self.source)
        self.assertIn("source: circleMaskArea", self.source)
        self.assertIn("transparentBorder: true", self.source)
        self.assertIn("z: -1", self.source)


if __name__ == "__main__":
    unittest.main()
