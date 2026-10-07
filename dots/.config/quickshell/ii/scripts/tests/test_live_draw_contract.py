"""Contracts for live draw: the shared store, the overlay and every way into it."""

from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
HYPR = ROOT.parents[1] / "hypr/hyprland"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


class StoreTests(unittest.TestCase):
    def test_one_store_for_both_families(self):
        self.assertTrue((ROOT / "services/LiveDraw.qml").exists())
        self.assertFalse((ROOT / "modules/tablet/liveDraw/TabletLiveDrawStore.qml").exists())
        for rel in ("modules/tablet/liveDraw/TabletLiveDraw.qml", "panelFamilies/TabletFamily.qml",
                    "modules/common/draw/LiveDrawWindow.qml", "modules/ii/liveDraw/LiveDrawOverlay.qml"):
            self.assertNotIn("TabletLiveDrawStore", read(rel), rel)

    def test_ink_survives_a_live_reload(self):
        store = read("services/LiveDraw.qml")
        self.assertIn("PersistentProperties", store)
        for name in ("sheets", "drawing", "trayOpen", "trayOffsetX", "trayOffsetY", "trayCollapsed"):
            self.assertRegex(store, rf"property alias {name}: keptSheets\.{name}")

    def test_no_hyprctl_at_startup(self):
        # The launchers reference the store from the bar and the dock; the animation
        # probe waits for the first open.
        self.assertNotIn("Component.onCompleted: root.refreshWorkspaceAnimation()", read("services/LiveDraw.qml"))


class EngineTests(unittest.TestCase):
    def test_live_stroke_is_not_frame_animated(self):
        # Starting a FrameAnimation per pointer event woke the animation driver of
        # every window in the shell: ~90 % of a core while drawing.
        canvas = read("modules/common/draw/DrawCanvas.qml")
        self.assertNotRegex(canvas, r"^\s*FrameAnimation\s*\{", )
        self.assertIn("Shape.CurveRenderer", canvas)

    def test_committed_canvas_paints_incrementally(self):
        canvas = read("modules/common/draw/DrawCanvas.qml")
        self.assertIn("_repaintAll", canvas)
        self.assertIn("next[i] === previous[i]", canvas)

    def test_live_points_are_appended_in_place(self):
        surface = read("modules/common/draw/DrawSurface.qml")
        self.assertIn("points.push(root.smoothPoint)", surface)
        self.assertNotIn("livePoints.concat", surface)

    def test_toolbar_is_opaque(self):
        # A transparency theme makes the layer tokens translucent, and nothing blurs
        # behind this layer.
        for rel in ("modules/common/draw/DrawToolbar.qml", "modules/common/draw/DrawToolButton.qml"):
            self.assertNotRegex(read(rel), r"colLayer[01]\b", rel)


class OverlayTests(unittest.TestCase):
    def test_family_loads_the_overlay(self):
        family = read("panelFamilies/IllogicalImpulseFamily.qml")
        self.assertIn("import qs.modules.ii.liveDraw", family)
        self.assertIn("modules/ii/liveDraw/LiveDrawOverlay.qml", family)
        self.assertIn("LiveDrawOverlay 1.0 LiveDrawOverlay.qml", read("modules/ii/liveDraw/qmldir"))

    def test_surface_only_while_needed(self):
        overlay = read("modules/ii/liveDraw/LiveDrawOverlay.qml")
        self.assertIn("LiveDraw.trayOpen || LiveDraw.screenHasInk(screenScope.modelData.name)", overlay)
        self.assertIn('namespace: "quickshell:liveDraw"', overlay)
        self.assertIn('name: "liveDrawToggle"', overlay)

    def test_hyprland_rules_and_keybind(self):
        rules = (HYPR / "rules.lua").read_text()
        self.assertIn('namespace = "quickshell:liveDraw" }, blur = false', rules)
        keybinds = (HYPR / "keybinds.lua").read_text()
        self.assertIn('hl.bind("SUPER + ALT + D", hl.dsp.global("quickshell:liveDrawToggle")', keybinds)


class LauncherTests(unittest.TestCase):
    LAUNCHERS = [
        "modules/common/models/quickToggles/LiveDrawToggle.qml",
        "modules/common/quickToggles/classicStyle/LiveDrawQuickToggle.qml",
        "modules/ii/bar/widgets/indicators/RecordIndicator.qml",
        "modules/ii/dynamicIsland/widgets/FloatingNotchRecording.qml",
        "modules/ii/dynamicIsland/activities/recording/RecordingExpanded.qml",
        "modules/ii/dock/utilities/LiveDrawTile.qml",
        "modules/ii/dock/utilities/ToolsTile.qml",
        "modules/ii/bar/widgets/utilButtons/UtilButtons.qml",
        "modules/ii/bar/widgets/utilButtons/ExpressiveUtilButtons.qml",
        "modules/ii/bar/widgets/utilButtons/SegmentedUtilButtons.qml",
    ]

    def test_every_launcher_toggles_the_store(self):
        for rel in self.LAUNCHERS:
            self.assertIn("LiveDraw.toggle()", read(rel), rel)

    def test_registries_know_the_toggle(self):
        self.assertIn('"liveDraw": liveDrawComp', read("services/QuickToggleRegistry.qml"))
        self.assertIn("liveDraw: { kind: \"toggle\"", read("modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"))
        self.assertIn('roleValue: "liveDraw"', read("modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"))
        self.assertIn('roleValue: "liveDraw"', read("modules/common/quickToggles/classicStyle/ClassicToggleDelegateChooser.qml"))
        self.assertIn('"liveDraw"', read("modules/common/quickToggles/classicStyle/ClassicQuickToggleCatalog.js"))
        self.assertIn('kind: "liveDraw"', read("modules/ii/dock/utilities/DockUtilityCatalog.js"))
        self.assertIn('id: "liveDraw"', read("modules/ii/dock/utilities/UtilityTools.js"))
        self.assertRegex(read("modules/common/TouchGestureActionRegistry.qml"),
                         r'id: "liveDraw".*families: \["tablet", "ii"\]')

    def test_bar_option_exists(self):
        self.assertIn("property bool showLiveDraw: true", read("modules/common/Config.qml"))
        self.assertIn("showLiveDraw", read("modules/settings/configs/widgets/UtilButtonsConfig.qml"))

    def test_strings_are_translated(self):
        en = json.loads(read("translations/en_US.json"))
        pt = json.loads(read("translations/pt_BR.json"))
        files = self.LAUNCHERS + ["modules/ii/dock/utilities/LiveDrawPanel.qml",
                                  "modules/common/draw/LiveDrawWindow.qml",
                                  "modules/common/draw/DrawToolbar.qml"]
        for rel in files:
            for key in re.findall(r'Translation\.tr\("([^"]+)"\)', read(rel)):
                self.assertIn(key, en, f"{rel}: {key}")
                self.assertIn(key, pt, f"{rel}: {key}")


if __name__ == "__main__":
    unittest.main()
