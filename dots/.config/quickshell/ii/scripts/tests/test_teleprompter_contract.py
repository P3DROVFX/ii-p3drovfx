import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CONFIG = ROOT / "modules/common/Config.qml"
SERVICE = ROOT / "services/Teleprompter.qml"
SOURCE = ROOT / "modules/ii/dynamicIsland/core/sources/TeleprompterSource.qml"
SOURCES = ROOT / "modules/ii/dynamicIsland/core/sources/IslandSources.qml"
CONTROLLER = ROOT / "modules/ii/dynamicIsland/core/IslandController.qml"
REGISTRY = ROOT / "modules/ii/dynamicIsland/core/IslandRegistry.qml"
NOTCH = ROOT / "modules/ii/dynamicIsland/styles/notch/NotchIsland.qml"
CONTENT = ROOT / "modules/ii/dynamicIsland/styles/notch/NotchContent.qml"
COMPACT_FACE = ROOT / "modules/ii/dynamicIsland/widgets/FloatingNotchTeleprompter.qml"
TEXT_COMPONENT = ROOT / "modules/ii/dynamicIsland/activities/teleprompter/TeleprompterText.qml"
EXPANDED_FACE = ROOT / "modules/ii/dynamicIsland/activities/teleprompter/TeleprompterExpanded.qml"
BANNER = ROOT / "modules/ii/dynamicIsland/widgets/FloatingNotchClipboard.qml"
PANEL = ROOT / "modules/ii/overview/ClipboardPanel.qml"
GLOBALSTATES = ROOT / "GlobalStates.qml"
PAGE_REGISTRY = ROOT / "modules/common/SettingsPageRegistry.qml"
DI_CONFIG = ROOT / "modules/settings/configs/DynamicIslandConfig.qml"
SUBPAGE = ROOT / "modules/settings/configs/features/TeleprompterConfig.qml"
PREVIEW = ROOT / "modules/settings/configs/features/TeleprompterPreview.qml"
FEATURES_QMLDIR = ROOT / "modules/settings/configs/features/qmldir"
EN = ROOT / "translations/en_US.json"
PT = ROOT / "translations/pt_BR.json"


def service_path_read():
    return SERVICE.read_text(encoding="utf-8")


class TeleprompterConfigContractTest(unittest.TestCase):
    def setUp(self):
        self.config = CONFIG.read_text(encoding="utf-8")

    def test_config_block_with_every_knob(self):
        start = self.config.index("property JsonObject teleprompter: JsonObject {")
        block = self.config[start:start + 2400]
        for key in ["enable", "lines", "expandedLines", "width", "fontSize", "bold",
                    "speed", "loop", "countdownSeconds", "mirror", "showProgress",
                    "holdVisible", "finishHoldSeconds", "text"]:
            self.assertIn(key + ":", block, msg=key)
        self.assertIn("property bool enable: false", block, "the feature ships off")
        self.assertIn("property int lines: 2", block)
        self.assertIn("property int expandedLines: 5", block)
        self.assertIn("property int countdownSeconds: 3", block)
        self.assertIn("property int finishHoldSeconds: 4", block)

    def test_service_is_the_single_reader_and_clamps(self):
        service = SERVICE.read_text(encoding="utf-8")
        self.assertIn("Math.min(4, Math.max(1, root.cfg?.lines ?? 2))", service)
        self.assertIn("readonly property real speedMin: 10", service)
        self.assertIn("readonly property real speedMax: 80", service)
        self.assertIn("Math.min(root.speedMax, Math.max(root.speedMin, root.cfg?.speed ?? 45))", service)
        # The engine is splittable for the offscreen tests.
        self.assertIn("function advance(dtMs)", service)
        self.assertIn("function stepCountdown()", service)
        self.assertIn('target: "teleprompter"', service)
        # A finished session gives the island back instead of parking on it.
        self.assertIn("property Timer _finishGrace", service)
        self.assertIn("onTriggered: root.stop()", service)
        # The card is always wider than the strip it grows from.
        self.assertIn("readonly property int expandedBoxWidth", service)
        # The service must not import the island core (IpcHandler resolution, see header).
        self.assertNotIn("import qs.modules.ii.dynamicIsland.core", service)


class TeleprompterIslandContractTest(unittest.TestCase):
    def test_descriptor_registers_both_presentations(self):
        registry = REGISTRY.read_text(encoding="utf-8")
        start = registry.index('id: "teleprompter"')
        block = registry[start:start + 1300]
        self.assertIn('tier: "live"', block)
        self.assertIn("canDetach: false", block)
        self.assertIn("bodyClickOpensDashboard: false", block)
        self.assertIn('compact: "widgets/FloatingNotchTeleprompter.qml"', block)
        self.assertIn('expanded: "activities/teleprompter/TeleprompterExpanded.qml"', block)
        self.assertIn("function bodyClickOpensDashboard(id)", registry)

    def test_source_registered_and_sizes_the_island(self):
        sources = SOURCES.read_text(encoding="utf-8")
        self.assertIn("readonly property TeleprompterSource teleprompter: TeleprompterSource {}", sources)
        self.assertIn("songRec, teleprompter,", sources)
        source = SOURCE.read_text(encoding="utf-8")
        self.assertIn("condition: Teleprompter.running && Teleprompter.featureEnabled", source)
        self.assertIn("expandedWidth: Teleprompter.expandedBoxWidth", source)
        self.assertIn("readonly property bool holdsSurface", source)

    def test_running_session_pins_the_centre(self):
        controller = CONTROLLER.read_text(encoding="utf-8")
        self.assertIn('? "teleprompter" : "";', controller)
        self.assertIn("pinnedId: pinned", controller)
        # Search is the single exception: it takes the surface, and the
        # prompter takes the centre back when it closes.
        self.assertIn("const searchUp = controller.sources.search && controller.sources.search.active;", controller)
        self.assertIn("&& !searchUp", controller)

    def test_surface_holds_the_prompter_on_screen(self):
        notch = NOTCH.read_text(encoding="utf-8")
        self.assertIn("controller.sources.teleprompter.holdsSurface", notch)
        self.assertIn("GlobalStates.islandTextDragActive", notch)
        # A text drop starts a session; files keep their own path.
        self.assertIn('keys: ["text/uri-list", "text/plain"]', notch)
        self.assertIn("Teleprompter.available && Teleprompter.start(script)", notch)
        self.assertIn('property: "dragHovering"', notch)
        # The expanded card measures itself; the compact override never caps it.
        self.assertIn("if (presentation === \"expanded\" && notchContent.expandedFaceHeight > 0)\n            return Math.min(registered, notchContent.expandedFaceHeight);\n        const override = root.pagedSizeOverride;", notch)
        # The expanded presentation may be wider than the strip.
        self.assertIn("presentation === \"expanded\" && override.expandedWidth > 0", notch)
        # A click on the reading surface never summons the dashboard.
        self.assertIn("IslandRegistry.bodyClickOpensDashboard(root.pagedId)", notch)

    def test_expanded_card_width_follows_the_override(self):
        content = CONTENT.read_text(encoding="utf-8")
        self.assertIn("readonly property real expandedBoxWidth", content)
        self.assertIn("override.expandedWidth > 0 ? override.expandedWidth : override.width", content)
        self.assertIn("? content.expandedBoxWidth : 0", content)

    def test_faces_share_one_scroll_with_progress_on_top(self):
        compact = COMPACT_FACE.read_text(encoding="utf-8")
        expanded = EXPANDED_FACE.read_text(encoding="utf-8")
        text = TEXT_COMPONENT.read_text(encoding="utf-8")
        self.assertIn("root.prompter.reportLayout(script.textHeight, viewport.height)", compact)
        # Progress is the top edge of both faces, full-bleed.
        self.assertIn("anchors.top: parent.top\n        height: 3", compact)
        self.assertIn("height: root.progressHeight", expanded)
        self.assertNotIn("check_circle", compact, "no orphan finished chip on the strip")
        # One control bar: status left, adjustments and transport grouped right.
        self.assertIn("Translation.tr(\"%1 left\")", expanded)
        self.assertIn("Translation.tr(\"Ready\")", expanded)
        self.assertIn("symbol: \"restart_alt\"", expanded)
        self.assertIn("implicitHeight: Math.round(root.progressHeight + root.bandGap + root.textAreaHeight", expanded)
        # Neutral tinted actions read on the translucent body; edit deep-links.
        self.assertIn("ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.10)", expanded)
        self.assertIn('GlobalStates.openSettingsPage("dynamicIsland", "features/TeleprompterConfig.qml")', expanded)
        # Editing the saved script mid-session rewrites the live one.
        self.assertIn("onSavedTextChanged", service_path_read())
        # Both faces translate by the session's scrollY through the shared text.
        self.assertIn("root.prompter.scrollY", text)
        self.assertIn("property var prompter: Teleprompter", compact)
        self.assertIn("property var prompter: Teleprompter", expanded)


class TeleprompterEntryPointsContractTest(unittest.TestCase):
    def test_copied_banner_offers_the_copy(self):
        banner = BANNER.read_text(encoding="utf-8")
        self.assertIn("Teleprompter.startFromClipboard()", banner)
        self.assertIn('text: Translation.tr("Read with Teleprompter")', banner)
        self.assertIn("requireOverlay: false", banner)

    def test_clipboard_panel_action_and_drag(self):
        panel = PANEL.read_text(encoding="utf-8")
        self.assertIn("Teleprompter.start(root.selectedDecodedContent.length > 0", panel)
        self.assertIn('"text/plain": entryRow.dragText', panel)
        self.assertIn("Drag.dragType: Drag.Automatic", panel)
        self.assertIn("drag.target: dragProxy", panel)
        self.assertIn("readonly property bool dragAvailable: Teleprompter.available && !entryRow.isImage", panel)
        # The panel's action is icon-only, named by its tooltip.
        self.assertIn('text: Translation.tr("Read with Teleprompter")', panel)
        self.assertNotIn('text: Translation.tr("Teleprompter")\n                                    font.pixelSize', panel)
        # The drag reveals the island: no hover signal fires mid-drag.
        self.assertIn("GlobalStates.islandTextDragActive = dragProxy.Drag.active", panel)
        self.assertIn("property bool islandTextDragActive: false", GLOBALSTATES.read_text(encoding="utf-8"))


class TeleprompterSettingsContractTest(unittest.TestCase):
    def test_settings_live_inside_the_island_page(self):
        registry = PAGE_REGISTRY.read_text(encoding="utf-8")
        self.assertNotIn('"id": "features"', registry, "no standalone Features page or group")
        self.assertNotIn("FeaturesConfig.qml", registry)
        start = registry.index('"id": "dynamicIsland"')
        block = registry[start:start + 700]
        self.assertIn('"features/TeleprompterConfig.qml"', block)
        di = DI_CONFIG.read_text(encoding="utf-8")
        self.assertIn('subPageOverlay.open(Qt.resolvedUrl("features/TeleprompterConfig.qml"))', di)
        self.assertIn("Translation.tr(\"Teleprompter layout & script\")", di)

    def test_subpage_preview_and_qmldir(self):
        subpage = SUBPAGE.read_text(encoding="utf-8")
        preview = PREVIEW.read_text(encoding="utf-8")
        qmldir = FEATURES_QMLDIR.read_text(encoding="utf-8")
        self.assertIn("property bool showBackButton: false", subpage)
        self.assertIn("signal goBack()", subpage)
        self.assertIn("ConfigSelectionArray {", subpage)
        self.assertIn("MaterialTextArea {", subpage)
        self.assertIn("from: Teleprompter.speedMin", subpage)
        self.assertIn("to: Teleprompter.speedMax", subpage)
        # The preview draws the real faces, not a stand-in.
        self.assertIn("modules/ii/dynamicIsland/widgets/FloatingNotchTeleprompter.qml", preview)
        self.assertIn("modules/ii/dynamicIsland/activities/teleprompter/TeleprompterExpanded.qml", preview)
        self.assertIn("Teleprompter.running ? Teleprompter : demo", preview)
        for entry in ["TeleprompterConfig 1.0 TeleprompterConfig.qml",
                      "TeleprompterPreview 1.0 TeleprompterPreview.qml",
                      "PreviewPrompter 1.0 PreviewPrompter.qml"]:
            self.assertIn(entry, qmldir)

    def test_translations_in_both_locales(self):
        en = json.loads(EN.read_text(encoding="utf-8"))
        pt = json.loads(PT.read_text(encoding="utf-8"))
        keys = ["Teleprompter", "Read with Teleprompter", "Start reading",
                "Lines on the island", "Lines in the hover card", "Scroll speed",
                "Countdown before reading", "Loop the script", "Mirror the text",
                "Stay on screen while reading", "Script complete", "%1 left",
                "Hover to preview the control card", "Finish and close",
                "Teleprompter layout & script"]
        for key in keys:
            self.assertIn(key, en, msg=key)
            self.assertIn(key, pt, msg=key)
            self.assertEqual(en[key], key)
            if key != "Teleprompter":  # a proper noun in both locales
                self.assertNotEqual(pt[key], key, msg="pt_BR must translate " + key)


if __name__ == "__main__":
    unittest.main()
