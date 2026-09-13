from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = ROOT / "modules/ii/bar/widgets/date"
STYLED_WIDGETS = ("ExpressiveDateWidget.qml", "NeuralDateWidget.qml")
ALL_WIDGETS = ("DateWidget.qml",) + STYLED_WIDGETS
# Variants extracted to their own file because they need explicit placement.
VARIANT_PARTS = ("ExpressiveDateStack.qml", "NeuralDateInlay.qml")
EVERY_QML = ALL_WIDGETS + VARIANT_PARTS
PALETTE = ROOT / "modules/common/widgets/BarWidgetPalette.qml"


class BarDateWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def widget(self, name: str) -> str:
        return (WIDGET_DIR / name).read_text(encoding="utf-8")

    def test_all_three_styles_are_registered(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")

        date_entry = registry.split('id: "date"', 1)[1].split("\n        {", 1)[0]
        self.assertIn('styleConfigKey: "date"', date_entry)
        for style in ("default", "expressive", "neural"):
            self.assertIn(f'value: "{style}"', date_entry)

        for component in ("DateWidget", "ExpressiveDateWidget", "NeuralDateWidget"):
            self.assertIn(component, router)

    def test_widget_is_wired_through_the_bar_and_settings_registries(self):
        config = self.read("modules/common/Config.qml")
        style_registry = self.read("modules/ii/bar/registry/BarWidgetRegistry.qml")
        settings_registry = self.read("modules/common/SettingsPageRegistry.qml")
        waffle = self.read("modules/settings/configs/widgets/BarWidgetsWaffleConfig.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")

        self.assertIn('property string date: "default"', config)
        self.assertIn('case "date":', style_registry)
        self.assertIn("widgets/DateBarWidgetConfig.qml", settings_registry)
        self.assertIn('root.openComponentPage("date")', waffle)
        self.assertIn('import "widgets/date"', router)

    def test_styled_variants_render_without_the_bar_group_chip(self):
        # Both families draw their own surface, so the BarGroup must not add a
        # second one behind them.
        router = self.read("modules/ii/bar/BarComponent.qml")
        self.assertIn(
            'modelData.id === "date" && (Config.options.bar.styles.date === "expressive" '
            '|| Config.options.bar.styles.date === "neural")',
            router,
        )

    def test_every_variant_is_selectable_and_persisted(self):
        config = self.read("modules/common/Config.qml")
        page = self.read("modules/settings/configs/widgets/DateBarWidgetConfig.qml")

        self.assertIn('property string expressiveVariant: "stack"', config)
        self.assertIn('property string neuralVariant: "orbit"', config)
        self.assertIn('property string colorMode: "tonal"', config)

        expressive = self.widget("ExpressiveDateWidget.qml")
        for value in ("stack", "badge", "ribbon"):
            self.assertIn(f'value: "{value}"', page)
            self.assertIn(f"id: {value}Variant", expressive)

        neural = self.widget("NeuralDateWidget.qml")
        for value in ("orbit", "glyph", "inlay"):
            self.assertIn(f'value: "{value}"', page)
            self.assertIn(f"id: {value}Variant", neural)
        for value in ("tonal", "vibrant", "neutral"):
            self.assertIn(f'value: "{value}"', page)

    def test_both_orientations_are_handled_by_every_widget(self):
        for name in ALL_WIDGETS:
            body = self.widget(name)
            self.assertIn("property bool vertical: false", body, name)
            self.assertIn("Appearance.sizes.verticalBarWidth", body, name)
            self.assertIn("Appearance.sizes.baseBarHeight", body, name)

    def test_styled_widgets_size_from_the_documented_thickness(self):
        for name in STYLED_WIDGETS:
            body = self.widget(name)
            self.assertIn("Appearance.sizes.verticalBarWidth - 8", body, name)
            self.assertIn("Appearance.sizes.baseBarHeight - 8", body, name)

    def test_one_animation_per_geometry_axis(self):
        # AGENTS.md §6.1: a single interpolated driver, never a Behavior on the
        # reserved slot and another on the surface.
        for name in STYLED_WIDGETS:
            body = self.widget(name)
            self.assertEqual(body.count("Behavior on implicitWidth"), 0, name)
            self.assertEqual(body.count("Behavior on implicitHeight"), 0, name)
            self.assertEqual(body.count("Behavior on animatedLength"), 1, name)

    def test_no_borders_anywhere_in_the_family(self):
        # The `stack` outline is a die-cut gap, not a stroked border: nothing in
        # the family may reach for `border.*` to draw it.
        combined = "".join(self.widget(name) for name in EVERY_QML)
        combined += PALETTE.read_text(encoding="utf-8")
        combined += self.read("modules/settings/configs/widgets/DateBarWidgetConfig.qml")
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)

    def test_stack_die_cuts_the_numeral_with_an_inverted_mask(self):
        body = self.widget("ExpressiveDateStack.qml")
        self.assertIn("import Qt5Compat.GraphicalEffects", body)
        self.assertIn("OpacityMask", body)
        self.assertIn("invert: true", body)
        # Source and mask are rendered, not shown.
        self.assertEqual(body.count("visible: false"), 2)
        # The mask is the labels dilated by a ring of offsets, which is what
        # turns "covered by" into "cut out with a margin".
        self.assertIn("cutSamples", body)
        self.assertIn("cutStroke", body)
        self.assertIn("Repeater", body)
        self.assertIn("ExpressiveDateStack", self.widget("ExpressiveDateWidget.qml"))

    def test_stack_places_every_element_explicitly(self):
        # An anchored sub-tree cannot be replayed at offsets inside the mask, so
        # the variant positions the numeral, the month and the chip by x/y from
        # measured metrics. Anchors here would silently desync mask and content.
        body = self.widget("ExpressiveDateStack.qml")
        for prop in ("dayX", "dayY", "monthX", "monthY", "chipX", "chipY"):
            self.assertIn(f"readonly property real {prop}:", body)
        self.assertNotIn("anchors.verticalCenter:", body)
        self.assertNotIn("anchors.left:", body)

    def test_no_hover_scale_and_no_looping_animations(self):
        for name in ALL_WIDGETS + VARIANT_PARTS:
            body = self.widget(name)
            self.assertNotIn("loops: Animation.Infinite", body, name)
            for line in body.splitlines():
                stripped = line.strip()
                if stripped.startswith("scale:"):
                    self.assertNotIn("Mouse", stripped, name)
                    self.assertNotIn("hovered", stripped, name)

    def test_colour_pairs_go_through_the_shared_theme(self):
        # Crossing a container with another family's `on*` colour is the defect
        # BarWidgetPalette exists to prevent, so the styled variants must not
        # reach for Appearance colour tokens directly.
        theme = PALETTE.read_text(encoding="utf-8")
        for pair in (
            ("colPrimaryContainer", "colOnPrimaryContainer"),
            ("colTertiaryContainer", "colOnTertiaryContainer"),
            ("colSurfaceContainerHighest", "colOnSurface"),
            ("colPrimary", "colOnPrimary"),
            ("colSecondary", "colOnSecondary"),
            ("colTertiary", "colOnTertiary"),
        ):
            for token in pair:
                self.assertIn(f"Appearance.colors.{token}", theme)

        for name in STYLED_WIDGETS:
            body = self.widget(name)
            self.assertNotIn("Appearance.colors.colOn", body, name)
            self.assertNotIn("Appearance.m3colors", body, name)

    def test_inlay_punches_the_numeral_out_of_the_plate(self):
        body = self.widget("NeuralDateInlay.qml")
        self.assertIn("import Qt5Compat.GraphicalEffects", body)
        self.assertIn("OpacityMask", body)
        self.assertIn("invert: true", body)
        self.assertIn("cutSamples", body)
        # The numeral is the hole, so nothing paints it — its metrics have to
        # come from an item that is measured and never drawn.
        self.assertIn("id: dayMetrics", body)
        self.assertIn("source: plateLayer", body)
        self.assertIn("maskSource: punchLayer", body)
        self.assertIn("NeuralDateInlay", self.widget("NeuralDateWidget.qml"))

    def test_variants_do_not_repeat_the_rounded_plate_pair(self):
        # `strata` was two rounded plates side by side, which `badge` already
        # was. Nothing in the Neural family may go back to that shape.
        neural = self.widget("NeuralDateWidget.qml")
        self.assertNotIn("labelPlate", neural)
        self.assertNotIn("dayPlate", neural)
        self.assertNotIn("strata", neural)

    def test_date_parts_come_from_the_service(self):
        service = self.read("services/DateTime.qml")
        for prop in (
            "dayOfMonth",
            "dayOfMonthPadded",
            "monthNumberPadded",
            "monthNameShort",
            "dayNameShortPrev",
            "dayNameShortNext",
            "daysInMonth",
            "monthProgress",
        ):
            self.assertIn(prop, service)

        # DST cannot be crossed by adding a fixed number of milliseconds, so the
        # neighbouring weekdays are built from calendar fields.
        for prop in ("dayNameShortPrev", "dayNameShortNext"):
            expression = service.split(f"property string {prop}:", 1)[1].split("\n", 1)[0]
            self.assertIn("getDate()", expression)
            self.assertNotIn("86400000", expression)

        for name in ALL_WIDGETS + VARIANT_PARTS:
            body = self.widget(name)
            self.assertNotIn("Qt.locale()", body, name)

    def test_locale_abbreviations_shorter_than_three_letters_still_render(self):
        body = self.widget("NeuralDateWidget.qml")
        head = body.split("readonly property string glyphHead:", 1)[1].split("\n", 1)[0]
        self.assertIn("length > 0", head)
        self.assertIn('visible: root.glyphHead !== ""', body)
        self.assertIn('visible: root.glyphTail !== ""', body)


if __name__ == "__main__":
    unittest.main()
