"""Contract tests for the bar's record indicator.

These are string checks, but they pin design decisions that no linter sees:
the three families stay wired, `minimal` means the same thing in all of them,
the elapsed time animates per digit rather than as a pulse, and the colour
pairs are never crossed.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = ROOT / "modules/ii/bar/widgets/indicators"
HOST = "RecordIndicator.qml"
FAMILIES = (
    "DefaultRecordIndicator.qml",
    "ExpressiveRecordIndicator.qml",
    "NeuralRecordIndicator.qml",
)
CLOCK_PARTS = ("RecordTimerText.qml", "RecordDigitCell.qml")
EVERY_QML = (HOST,) + FAMILIES + CLOCK_PARTS
PALETTE = ROOT / "modules/common/widgets/BarWidgetPalette.qml"


class BarRecordIndicatorContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def widget(self, name: str) -> str:
        return (WIDGET_DIR / name).read_text(encoding="utf-8")

    def test_all_three_styles_are_registered(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        entry = registry.split('id: "record_indicator"', 1)[1].split("\n        {", 1)[0]

        self.assertIn('styleConfigKey: "recordIndicator"', entry)
        self.assertIn('configPage: "RecordIndicatorConfig.qml"', entry)
        for style in ("default", "expressive", "neural"):
            self.assertIn(f'value: "{style}"', entry)

    def test_widget_is_wired_through_the_bar_and_settings_registries(self):
        config = self.read("modules/common/Config.qml")
        style_registry = self.read("modules/ii/bar/registry/BarWidgetRegistry.qml")
        settings_registry = self.read("modules/common/SettingsPageRegistry.qml")
        waffle = self.read("modules/settings/configs/widgets/BarWidgetsWaffleConfig.qml")

        self.assertIn('property string recordIndicator: "expressive"', config)
        self.assertIn('case "record_indicator":       return s.recordIndicator', style_registry)
        self.assertIn("widgets/RecordIndicatorConfig.qml", settings_registry)
        self.assertIn('root.openComponentPage("record_indicator")', waffle)

    def test_only_the_styled_families_lose_the_bar_group_chip(self):
        # The default family is an ordinary bar widget and wants the group chip
        # behind it; the other two paint their own surface, so a second one
        # behind them would be a box inside a box.
        router = self.read("modules/ii/bar/BarComponent.qml")
        self.assertIn(
            'modelData.id === "record_indicator" '
            '&& Config.options.bar.styles.recordIndicator !== "default"',
            router,
        )

    def test_every_variant_is_selectable_and_persisted(self):
        config = self.read("modules/common/Config.qml")
        page = self.read("modules/settings/configs/widgets/RecordIndicatorConfig.qml")

        for key in ("expressiveVariant", "neuralVariant", "colorMode", "minimal",
                    "showLabel", "animateDigits"):
            self.assertIn(key, config)
            self.assertIn(f"Config.options.bar.indicators.record.{key}", page)

        expressive = self.widget("ExpressiveRecordIndicator.qml")
        neural = self.widget("NeuralRecordIndicator.qml")
        for variant in ("capsule", "badge", "ribbon"):
            self.assertIn(f'value: "{variant}"', page)
            self.assertIn(variant, expressive)
        for variant in ("duo", "slab", "meter"):
            self.assertIn(f'value: "{variant}"', page)
            self.assertIn(variant, neural)

    def test_minimal_mode_means_the_same_thing_in_every_family(self):
        # The host decides what is on show; the families only decide how it
        # looks. That is what keeps one switch working for all three.
        for name in FAMILIES:
            body = self.widget(name)
            self.assertIn("property bool minimal", body, name)
        for name in ("ExpressiveRecordIndicator.qml", "NeuralRecordIndicator.qml"):
            body = self.widget(name)
            self.assertIn("readonly property bool showTime: !root.minimal && !root.loading", body, name)
        self.assertIn(
            "readonly property bool showTime: !root.minimal && !root.loading",
            self.widget("DefaultRecordIndicator.qml"),
        )

    def test_both_orientations_are_drawn(self):
        for name in FAMILIES:
            body = self.widget(name)
            self.assertIn("property bool vertical", body, name)
            self.assertIn("root.vertical", body, name)
        host = self.widget(HOST)
        self.assertIn("Appearance.sizes.verticalBarWidth - 8", host)
        self.assertIn("Appearance.sizes.baseBarHeight - 8", host)
        # The vertical bar re-stacks the clock rather than rotating it.
        self.assertIn("property bool stacked", self.widget("RecordTimerText.qml"))
        for name in ("ExpressiveRecordIndicator.qml", "NeuralRecordIndicator.qml",
                     "DefaultRecordIndicator.qml"):
            self.assertIn("stacked: root.vertical", self.widget(name), name)

    def test_the_clock_animates_and_nothing_else_does(self):
        cell = self.widget("RecordDigitCell.qml")
        # Two glyphs travelling together: one label fading out and back in
        # leaves the cell empty for a moment, which reads as a blink at one
        # change per second.
        self.assertIn("id: outgoing", cell)
        self.assertIn("id: incoming", cell)
        self.assertIn("ParallelAnimation", cell)
        self.assertNotIn("loops: Animation.Infinite", cell)

        for name in EVERY_QML:
            body = self.widget(name)
            self.assertNotIn("SequentialAnimation on scale", body, name)
            self.assertNotIn("SequentialAnimation on opacity", body, name)

    def test_no_pulse_and_the_only_loop_is_the_portal_spinner(self):
        for name in EVERY_QML:
            body = self.widget(name)
            for index, line in enumerate(body.splitlines()):
                if "loops: Animation.Infinite" not in line:
                    continue
                window = "\n".join(body.splitlines()[max(0, index - 6):index + 1])
                # An infinite loop is only allowed while an operation is
                # genuinely outstanding — here, the screen-sharing portal.
                self.assertIn("running: root.loading", window, f"{name}:{index + 1}")

    def test_surfaces_define_no_borders(self):
        combined = "\n".join(self.widget(name) for name in EVERY_QML)
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)

    def test_the_slot_and_the_surface_share_one_animation(self):
        host = self.widget(HOST)
        self.assertIn("Behavior on animatedLength", host)
        self.assertEqual(host.count("Behavior on implicitWidth"), 0)
        self.assertEqual(host.count("Behavior on implicitHeight"), 0)
        for name in FAMILIES:
            body = self.widget(name)
            self.assertEqual(body.count("Behavior on implicitWidth"), 0, name)
            self.assertEqual(body.count("Behavior on implicitHeight"), 0, name)

    def test_the_bar_chip_follows_the_state_by_binding_not_by_push(self):
        # `toggleHighlight()` from a change handler reads `live`, a binding that
        # may not have been re-evaluated yet, so the chip ended up one state
        # behind: dark content on a lit chip, and the reverse.
        host = self.widget(HOST)
        self.assertIn("readonly property bool activated: root.live", host)
        self.assertNotIn("rootItem.toggleHighlight(", host)

    def test_colour_pairs_are_never_crossed(self):
        palette = PALETTE.read_text(encoding="utf-8")
        # QML reserves the `on` prefix for signal handlers: a property declared
        # `onContainer` with a binding never receives it and silently stays
        # black. Every name here must survive that rule.
        for member in ("colContainer", "colOnContainer", "colAccent", "colOnAccent",
                       "colBare", "colBareAccent"):
            self.assertIn(f"property color {member}", palette)
        for forbidden in ("property color onContainer", "property color onAccent"):
            self.assertNotIn(forbidden, palette)

        self.assertIn('root.alert\n        ? Appearance.colors.colErrorContainer', palette)

        expressive = self.widget("ExpressiveRecordIndicator.qml")
        neural = self.widget("NeuralRecordIndicator.qml")
        for body, name in ((expressive, "expressive"), (neural, "neural")):
            self.assertIn("BarWidgetPalette", body, name)
            self.assertNotIn("theme.colOnAccent : theme.colContainer", body, name)
            self.assertNotIn("#", body.split("BarWidgetPalette", 1)[1].split("\n")[0], name)

    def test_the_default_family_borrows_the_bar_idiom_rather_than_inventing_one(self):
        body = self.widget("DefaultRecordIndicator.qml")
        self.assertNotIn("BarWidgetPalette", body)
        self.assertNotIn("colError", body)
        self.assertIn("property color colContent", body)
        host = self.widget(HOST)
        self.assertIn("property color onActivatedColor", host)


if __name__ == "__main__":
    unittest.main()
