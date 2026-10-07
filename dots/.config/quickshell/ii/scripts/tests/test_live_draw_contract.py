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


class ImprovementTests(unittest.TestCase):
    def test_keyboard_only_while_drawing(self):
        window = read("modules/common/draw/LiveDrawWindow.qml")
        # Grabbed for a moment, then on demand, so a window focused by keybind gets
        # typing with the pen still down (B6).
        self.assertIn("root.grabbingKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand", window)
        for key in ("Qt.Key_Z", "Qt.Key_Y", "Qt.Key_Escape", "Qt.Key_Delete", "Qt.Key_BracketLeft", "Qt.Key_S"):
            self.assertIn(key, window)
        # Buttons must not steal focus from the sheet.
        self.assertIn("focusPolicy: Qt.NoFocus", read("modules/common/draw/DrawToolButton.qml"))

    def test_shortcuts_need_ctrl(self):
        # A bare letter is typed into whatever text field has the keyboard.
        window = read("modules/common/draw/LiveDrawWindow.qml")
        handler = window.split("function handleKey(event)")[1].split("Item {")[0]
        self.assertIn("if (!ctrl)\n            return false;", handler)
        self.assertLess(handler.index("if (!ctrl)"), handler.index("Qt.Key_H"))

    def test_undo_redo_history(self):
        store = read("services/LiveDraw.qml")
        for name in ("function undo(key)", "function redo(key)", "function canUndo(key)", "function canRedo(key)"):
            self.assertIn(name, store)
        self.assertIn("root._remember(key);\n        root._setSheet(key, []);", store)

    def test_mouse_is_steadied(self):
        surface = read("modules/common/draw/DrawSurface.qml")
        self.assertIn("StrokeGeometry.pulled(root.brush, raw, root.stringLength)", surface)
        self.assertIn("function pulled(", read("modules/common/draw/StrokeGeometry.js"))
        self.assertIn("property int mouseSmoothing: 60", read("modules/common/Config.qml"))

    def test_settings_live_in_the_drawing(self):
        window = read("modules/common/draw/LiveDrawWindow.qml")
        self.assertIn("LiveDrawSettings {", window)
        self.assertIn("flyoutRegion", window)
        self.assertIn("showPressure: false", window)
        popup = read("modules/common/draw/LiveDrawSettings.qml")
        for key in ('"pressure"', '"smoothing"', '"workspaceParallax"', "mouseSmoothing", '"sheetMode"',
                    '"boardPattern"', '"nativeCursor"'):
            self.assertIn(key, popup)

    def test_tooltips_show_without_an_overlay(self):
        self.assertIn("requireOverlay: false", read("modules/common/draw/DrawToolButton.qml"))

    def test_can_be_switched_off(self):
        self.assertIn("Config.options.liveDraw.enable = checked", read("modules/settings/configs/OverlaysConfig.qml"))
        self.assertIn("readonly property bool enabled:", read("services/LiveDraw.qml"))
        self.assertIn("LiveDraw.enabled", read("modules/ii/liveDraw/LiveDrawOverlay.qml"))


class WhiteboardTests(unittest.TestCase):
    def test_tools_and_geometry(self):
        geometry = read("modules/common/draw/StrokeGeometry.js")
        for name in ("function shapePolylines(", "function constrained(", "function documentSvg(", "function hitPoints("):
            self.assertIn(name, geometry)
        surface = read("modules/common/draw/DrawSurface.qml")
        self.assertIn('property string tool: "pen"', surface)
        self.assertIn("canvas.releaseLaser(finished)", surface)

    def test_highlighter_is_under_the_ink(self):
        canvas = read("modules/common/draw/DrawCanvas.qml")
        self.assertLess(canvas.index("id: underLoader"), canvas.index("id: committed"))
        self.assertLess(canvas.index("id: committed"), canvas.index("id: liveOver"))

    def test_board_spotlight_zoom(self):
        window = read("modules/common/draw/LiveDrawWindow.qml")
        self.assertIn("fillMode: Image.Tile", window)
        self.assertIn("ShapePath.OddEvenFill", window)
        self.assertIn("ScreencopyView {", window)
        # toDataURL into an Image source overflowed the JS stack on every window build.
        self.assertNotIn("toDataURL", window)
        for pattern in ("grid", "dots", "lines"):
            for tone in ("light", "dark"):
                self.assertTrue((ROOT / f"assets/images/liveDraw/{pattern}-{tone}.png").exists())

    def test_slide_follows_the_compositor_style(self):
        store = read("services/LiveDraw.qml")
        self.assertIn("function applySlideStyle(style)", store)
        self.assertIn('root.workspaceSlideAxis = kind.startsWith("slide")', store)

    def test_no_close_on_teardown(self):
        # A dying store wrote close() into the PersistentProperties the next one inherits.
        store = read("services/LiveDraw.qml")
        self.assertNotIn("onEnabledChanged", store)
        self.assertNotIn("LiveDraw.close()", read("modules/ii/liveDraw/LiveDrawOverlay.qml").split("Component.onDestruction")[1])

    def test_vertical_and_measured_compaction(self):
        toolbar = read("modules/common/draw/DrawToolbar.qml")
        self.assertIn("function widthAt(lvl)", toolbar)
        self.assertIn("function heightAt(lvl)", toolbar)
        window = read("modules/common/draw/LiveDrawWindow.qml")
        self.assertIn("tray.widthAt(0) <= room", window)
        self.assertIn("function settleTray(pointer)", window)

    def test_ipc_covers_the_toolbar(self):
        overlay = read("modules/ii/liveDraw/LiveDrawOverlay.qml")
        for name in ("quick", "pen", "tool", "color", "width", "board", "spotlight", "zoom", "sheet",
                     "toolbar", "undo", "redo", "clear", "clearAll", "copy", "copyScreen", "exportAs",
                     "save", "screenshot", "status"):
            self.assertRegex(overlay, rf"function {name}\(")

    def test_native_cursor_costs_nothing(self):
        surface = read("modules/common/draw/DrawSurface.qml")
        self.assertIn("active: !root.nativeCursor && root.drawing && hover.hovered", surface)


class OverlayTests(unittest.TestCase):
    def test_family_loads_the_overlay(self):
        family = read("panelFamilies/IllogicalImpulseFamily.qml")
        self.assertIn("import qs.modules.ii.liveDraw", family)
        self.assertIn("modules/ii/liveDraw/LiveDrawOverlay.qml", family)
        self.assertIn("LiveDrawOverlay 1.0 LiveDrawOverlay.qml", read("modules/ii/liveDraw/qmldir"))

    def test_surface_only_while_needed(self):
        overlay = read("modules/ii/liveDraw/LiveDrawOverlay.qml")
        self.assertIn("((LiveDraw.trayOpen || LiveDraw.spotlight || LiveDraw.zoom) && focused)", overlay)
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
                                  "modules/common/draw/DrawToolbar.qml",
                                  "modules/common/draw/LiveDrawSettings.qml",
                                  "modules/common/draw/LiveDrawMenus.qml"]
        for rel in files:
            for key in re.findall(r'Translation\.tr\("([^"]+)"\)', read(rel)):
                self.assertIn(key, en, f"{rel}: {key}")
                self.assertIn(key, pt, f"{rel}: {key}")


if __name__ == "__main__":
    unittest.main()
