from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
WIDGET_DIR = ROOT / "modules/ii/bar/widgets/search"


class BarSearchWidgetContractTest(unittest.TestCase):
    def read(self, relative_path: str) -> str:
        return (ROOT / relative_path).read_text(encoding="utf-8")

    def test_all_three_styles_are_registered(self):
        registry = self.read("modules/common/BarComponentRegistry.qml")
        router = self.read("modules/ii/bar/BarComponent.qml")

        self.assertIn('id: "search"', registry)
        for style in ("default", "expressive", "neural"):
            self.assertIn(f'value: "{style}"', registry)
        for component in (
            "SearchBarWidget",
            "ExpressiveSearchBarWidget",
            "NeuralSearchBarWidget",
        ):
            self.assertIn(component, router)

    def test_widget_is_wired_through_the_bar_and_settings_registries(self):
        config = self.read("modules/common/Config.qml")
        style_registry = self.read("modules/ii/bar/registry/BarWidgetRegistry.qml")
        settings_registry = self.read("modules/common/SettingsPageRegistry.qml")
        waffle = self.read("modules/settings/configs/widgets/BarWidgetsWaffleConfig.qml")

        self.assertIn('property string search: "default"', config)
        self.assertIn('"id": "search"', config)
        self.assertIn('case "search":', style_registry)
        self.assertIn('widgets/SearchBarWidgetConfig.qml', settings_registry)
        self.assertIn('root.openComponentPage("search")', waffle)

    def test_click_uses_the_launcher_only_state_boundary(self):
        global_states = self.read("GlobalStates.qml")
        self.assertIn("function toggleSearchOnly(monitorName)", global_states)
        helper = global_states.split("function toggleSearchOnly(monitorName)", 1)[1].split("function", 1)[0]
        self.assertIn("root.searchOnlyMode = true", helper)
        self.assertIn("root.openSearch(monitorName)", helper)
        self.assertIn("root.overviewOpen && root.searchOnlyMode && sameMonitor", helper)

        for widget in WIDGET_DIR.glob("*SearchBarWidget.qml"):
            self.assertIn("GlobalStates.toggleSearchOnly", widget.read_text(encoding="utf-8"))

    def test_size_and_colour_variants_are_persisted(self):
        config = self.read("modules/common/Config.qml")
        page = self.read("modules/settings/configs/widgets/SearchBarWidgetConfig.qml")

        self.assertIn('property string sizeMode: "compact"', config)
        self.assertIn('property string colorMode: "tonal"', config)
        for value in ("compact", "balanced", "extended"):
            self.assertIn(f'value: "{value}"', page)
        for value in ("tonal", "vibrant", "neutral"):
            self.assertIn(f'value: "{value}"', page)

    def test_colour_icons_and_vertical_labels_have_valid_responsive_contracts(self):
        page = self.read("modules/settings/configs/widgets/SearchBarWidgetConfig.qml")
        self.assertNotIn('icon: "colors_spark"', page)
        self.assertIn('icon: "auto_awesome", value: "vibrant"', page)

        for widget in WIDGET_DIR.glob("*.qml"):
            body = widget.read_text(encoding="utf-8")
            if widget.name == "SearchShortcutBadge.qml":
                continue
            self.assertIn("readonly property int contentRotation", body)
            self.assertIn("Config.options.bar.bottom ? 90 : -90", body)
            self.assertIn("rotation: root.contentRotation", body)
            self.assertIn("fontSizeMode: Text.Fit", body)
            self.assertIn("minimumPixelSize: Appearance.font.pixelSize.smallest", body)

    def test_extended_mode_reuses_horizontal_copy_and_super_glyph_in_both_orientations(self):
        badge = self.read("modules/ii/bar/widgets/search/SearchShortcutBadge.qml")
        self.assertIn("Config.options.cheatsheet.superKey", badge)
        self.assertIn("Appearance.font.family.iconNerd", badge)
        self.assertIn("MaterialShape.Shape.Circle", badge)

        for widget in WIDGET_DIR.glob("*SearchBarWidget.qml"):
            body = widget.read_text(encoding="utf-8")
            self.assertIn("SearchShortcutBadge", body)
            self.assertNotIn("&& !root.vertical", body)
            self.assertNotIn('Translation.tr("Search launcher")', body)

    def test_widget_surfaces_keep_the_bar_design_contract(self):
        bodies = "\n".join(path.read_text(encoding="utf-8") for path in WIDGET_DIR.glob("*.qml"))
        self.assertNotIn("border.width", bodies)
        self.assertNotIn("border.color", bodies)
        self.assertNotRegex(bodies, re.compile(r"\bscale\s*:"))
        self.assertNotIn("loops: Animation.Infinite", bodies)
        self.assertIn("Appearance.sizes.baseBarHeight - 8", bodies)
        self.assertIn("Appearance.sizes.verticalBarWidth - 8", bodies)
        self.assertEqual(bodies.count("requireOverlay: false"), 3)

    def test_settings_subsections_only_wrap_selection_arrays(self):
        page = self.read("modules/settings/configs/widgets/SearchBarWidgetConfig.qml")
        subsection_bodies = re.findall(
            r"ContentSubsection\s*\{(.*?)(?=\n\s{8}(?:ContentSubsection|ConfigSwitch)|\n\s{4}\})",
            page,
            flags=re.DOTALL,
        )
        self.assertGreaterEqual(len(subsection_bodies), 3)
        for body in subsection_bodies:
            self.assertIn("ConfigSelectionArray", body)
            self.assertNotIn("ConfigSwitch", body)


if __name__ == "__main__":
    unittest.main()
