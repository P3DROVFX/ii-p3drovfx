from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = ROOT / "modules/ii/bar/widgets/clock"
FAMILIES = ("NeuralClockWidget.qml", "ReliefClockWidget.qml")
# Variants extracted to their own file because a die-cut mask has to replay its
# content at offsets, which needs explicit x/y rather than anchors.
VARIANT_PARTS = (
    "NeuralClockBloom.qml",
    "ReliefClockSplit.qml",
    "ReliefClockSeam.qml",
    "ReliefClockOutline.qml",
)
EVERY_QML = FAMILIES + VARIANT_PARTS
PALETTE = ROOT / "modules/common/widgets/BarWidgetPalette.qml"
RING = ROOT / "modules/common/widgets/DieCutRing.qml"


class BarClockWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def widget(self, name: str) -> str:
        return (WIDGET_DIR / name).read_text(encoding="utf-8")

    def test_all_five_styles_are_registered(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")

        clock_entry = registry.split('id: "clock"', 1)[1].split("\n        {", 1)[0]
        self.assertIn('styleConfigKey: "clock"', clock_entry)
        for style in ("default", "material", "expressive", "neural", "relief"):
            self.assertIn(f'value: "{style}"', clock_entry)

        for component in ("NeuralClockWidget", "ReliefClockWidget"):
            self.assertIn(component, router)

    def test_widget_is_wired_through_the_registries(self):
        config = self.read("modules/common/Config.qml")
        settings_registry = self.read("modules/common/SettingsPageRegistry.qml")
        waffle = self.read("modules/settings/configs/widgets/BarWidgetsWaffleConfig.qml")

        self.assertIn("property JsonObject clockWidget: JsonObject {", config)
        self.assertIn("widgets/ClockBarWidgetConfig.qml", settings_registry)
        self.assertIn('root.openComponentPage("clock")', waffle)

    def test_styled_families_render_without_the_bar_group_chip(self):
        router = self.read("modules/ii/bar/BarComponent.qml")
        self.assertIn(
            'modelData.id === "clock" && (Config.options.bar.styles.clock === "neural" '
            '|| Config.options.bar.styles.clock === "relief")',
            router,
        )

    def test_every_variant_is_selectable_and_dispatched(self):
        config = self.read("modules/common/Config.qml")
        page = self.read("modules/settings/configs/widgets/ClockBarWidgetConfig.qml")
        neural = self.widget("NeuralClockWidget.qml")
        relief = self.widget("ReliefClockWidget.qml")

        self.assertIn('property string neuralVariant: "orbit"', config)
        self.assertIn('property string reliefVariant: "split"', config)
        self.assertIn('property string colorMode: "tonal"', config)

        for value in ("orbit", "bloom", "dial"):
            self.assertIn(f'value: "{value}"', page)
            self.assertIn(f"id: {value}Variant", neural)
        for value in ("split", "seam", "outline"):
            self.assertIn(f'value: "{value}"', page)
            self.assertIn(f"id: {value}Variant", relief)
        for value in ("tonal", "vibrant", "neutral"):
            self.assertIn(f'value: "{value}"', page)

    def test_both_orientations_are_handled(self):
        for name in EVERY_QML:
            self.assertIn("property bool vertical: false", self.widget(name), name)
        for name in FAMILIES:
            body = self.widget(name)
            self.assertIn("Appearance.sizes.verticalBarWidth - 8", body, name)
            self.assertIn("Appearance.sizes.baseBarHeight - 8", body, name)

    def test_one_animation_per_geometry_axis(self):
        for name in FAMILIES:
            body = self.widget(name)
            self.assertEqual(body.count("Behavior on implicitWidth"), 0, name)
            self.assertEqual(body.count("Behavior on implicitHeight"), 0, name)
            self.assertEqual(body.count("Behavior on animatedLength"), 1, name)

    def test_no_borders_anywhere_in_the_family(self):
        # Every outline in Relief is a gap, never a stroked border.
        combined = "".join(self.widget(name) for name in EVERY_QML)
        combined += self.read("modules/settings/configs/widgets/ClockBarWidgetConfig.qml")
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)

    def test_no_hover_scale_and_no_looping_animations(self):
        for name in EVERY_QML:
            body = self.widget(name)
            self.assertNotIn("loops: Animation.Infinite", body, name)
            self.assertNotIn("RotationAnimator", body, name)
            for line in body.splitlines():
                stripped = line.strip()
                if stripped.startswith("scale:"):
                    self.assertNotIn("Mouse", stripped, name)
                    self.assertNotIn("hovered", stripped, name)

    def test_every_die_cut_uses_the_shared_ring(self):
        # Five copies of the same offset maths is how they drift apart.
        ring = RING.read_text(encoding="utf-8")
        self.assertIn("property real radius", ring)
        self.assertIn("readonly property var samples", ring)

        for name in ("NeuralClockBloom.qml", "ReliefClockSplit.qml",
                     "ReliefClockSeam.qml", "ReliefClockOutline.qml"):
            body = self.widget(name)
            self.assertIn("DieCutRing {", body, name)
            self.assertIn("import Qt5Compat.GraphicalEffects", body, name)
            self.assertIn("invert: true", body, name)
            self.assertNotIn("Math.PI * 2", body, name)

    def test_vertical_staggering_never_leaves_the_bar(self):
        # Two number pairs offset sideways is wider than a 44px bar. The shift
        # has to come from the room left over, not from a fraction of the pair.
        for name in ("ReliefClockSplit.qml", "ReliefClockOutline.qml"):
            body = self.widget(name)
            self.assertIn("readonly property real shiftX:", body, name)
            self.assertIn("root.thickness - root.pairW", body, name)
            self.assertIn("root.hoursX + root.shiftX", body, name)

    def test_outline_is_a_subtraction_not_a_stroke(self):
        body = self.widget("ReliefClockOutline.qml")
        # Grown copy minus the exact glyph. Both halves have to be present or
        # the "hollow" numerals come out solid.
        self.assertIn("id: grownLayer", body)
        self.assertIn("id: coreLayer", body)
        self.assertIn("source: grownLayer", body)
        self.assertIn("maskSource: coreLayer", body)

    def test_colour_pairs_go_through_the_shared_palette(self):
        for name in FAMILIES:
            body = self.widget(name)
            self.assertIn("BarWidgetPalette {", body, name)
            self.assertNotIn("Appearance.colors.colOn", body, name)
            self.assertNotIn("Appearance.m3colors", body, name)
        # The parts take resolved colours as properties instead of resolving
        # their own, so a variant cannot quietly pick a different pairing.
        for name in VARIANT_PARTS:
            body = self.widget(name)
            self.assertNotIn("Appearance.colors.col", body, name)

    def test_clock_parts_come_from_the_service(self):
        service = self.read("services/DateTime.qml")
        for prop in ("hours", "minutes", "meridiem", "minuteProgress", "hourProgress"):
            self.assertIn(prop, service)
        for name in EVERY_QML:
            body = self.widget(name)
            self.assertNotIn("Qt.locale()", body, name)
            self.assertNotIn("Qt.formatDateTime", body, name)


if __name__ == "__main__":
    unittest.main()
