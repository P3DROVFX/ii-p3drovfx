from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = ROOT / "modules/ii/bar/widgets/media"
NEW_WIDGETS = ("RingMedia.qml", "TonalMedia.qml")
BASE = "MediaWidgetBase.qml"


class BarMediaWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def widget(self, name: str) -> str:
        return (WIDGET_DIR / name).read_text(encoding="utf-8")

    def test_both_new_styles_are_registered(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")

        entry = registry.split('id: "music_player"', 1)[1].split("\n        {", 1)[0]
        for style in ("default", "expressive", "neural", "ring", "tonal"):
            self.assertIn(f'value: "{style}"', entry)

        for component in ("RingMedia", "TonalMedia"):
            self.assertIn(component, router)
        self.assertIn('if (style === "ring")', router)
        self.assertIn('if (style === "tonal")', router)

    def test_new_styles_render_without_the_bar_group_chip(self):
        router = self.read("modules/ii/bar/BarComponent.qml")
        self.assertIn(
            '["expressive", "neural", "ring", "tonal"].includes(Config.options.bar.styles.media)',
            router,
        )

    def test_lyrics_are_a_horizontal_bar_feature_only(self):
        base = self.widget(BASE)
        gate = base.split("readonly property bool lyricsEnabled:", 1)[1].split("\n", 1)[0]
        self.assertIn("!root.vertical", gate)
        # Every new widget reads the gated property, never the raw config flag.
        for name in NEW_WIDGETS:
            body = self.widget(name)
            self.assertIn("root.showLyrics", body, name)
            self.assertNotIn("Config.options.bar.mediaPlayer.lyrics.enable", body, name)

    def test_new_widgets_share_the_base_instead_of_copying_it(self):
        for name in NEW_WIDGETS:
            body = self.widget(name)
            self.assertIn("MediaWidgetBase {", body, name)
            # The artwork cache, popup anchor and mouse contract live in the
            # base; a copy here is how they drift apart.
            self.assertNotIn("Process {", body, name)
            self.assertNotIn("MouseArea {", body, name)
            self.assertNotIn("mediaPopupRect", body, name)

    def test_preview_instances_cannot_hijack_the_popup_anchor(self):
        base = self.widget(BASE)
        self.assertIn("property bool previewMode: false", base)
        guard = base.split("function updatePopupRect()", 1)[1].split("\n", 2)[1]
        self.assertIn("root.previewMode", guard)
        page = self.read("modules/settings/configs/widgets/MediaPlayerConfig.qml")
        self.assertEqual(page.count("previewMode: true"), 4)

    def test_both_orientations_are_handled(self):
        for name in NEW_WIDGETS:
            body = self.widget(name)
            self.assertIn("Appearance.sizes.verticalBarWidth", body, name)
            self.assertIn("Appearance.sizes.baseBarHeight", body, name)
            self.assertIn("root.vertical", body, name)

    def test_one_animation_per_geometry_axis(self):
        for name in NEW_WIDGETS:
            body = self.widget(name)
            self.assertLessEqual(body.count("Behavior on implicitWidth"), 1, name)
            self.assertLessEqual(body.count("Behavior on implicitHeight"), 1, name)

    def test_no_borders_and_no_looping_animations(self):
        combined = "".join(self.widget(n) for n in NEW_WIDGETS) + self.widget(BASE)
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)
        self.assertNotIn("loops: Animation.Infinite", combined)

    def test_neural_media_no_longer_fights_over_its_height(self):
        body = self.widget("NeuralMedia.qml")
        head = body.split("readonly property MprisPlayer", 1)[0]
        # The root is the album-art card. `Layout.fillHeight` made the router
        # bind height to the bar row (40) while the layout reserved 32, and a
        # `height:` line on top of that was simply overwritten.
        self.assertNotIn("Layout.fillHeight: true", head)
        self.assertNotIn("\n    height: implicitHeight", body)
        self.assertIn("implicitHeight: hasTrack ? Appearance.sizes.baseBarHeight - 8 : 0", body)


if __name__ == "__main__":
    unittest.main()
