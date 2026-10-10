"""Contracts for the Real Gnome overview style.

Real Gnome is a separate style next to Gnome Like: it must reuse the Gnome-like
pipeline without changing it, and add GNOME Shell's window picker, eased motion,
neighbouring workspace peeks and vignette. The picker layout itself is executed
with node against real window sets.
"""

from pathlib import Path
import json
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = (ROOT / "modules/ii/background/overview/OverviewBackgroundController.qml").read_text()
TRANSITION = (ROOT / "modules/ii/overview/OverviewWindowTransition.qml").read_text()
OVERVIEW = (ROOT / "modules/ii/overview/Overview.qml").read_text()
PICKER = (ROOT / "modules/ii/overview/RealGnomeWindowPicker.qml").read_text()
WALLPAPER_IMAGE = (ROOT / "modules/ii/background/wallpaper/WallpaperImage.qml").read_text()
BG_ROOT = (ROOT / "modules/ii/background/BackgroundRoot.qml").read_text()
GLOBAL_STATES = (ROOT / "GlobalStates.qml").read_text()
CONFIG_QML = (ROOT / "modules/common/Config.qml").read_text()
OVERVIEW_CONFIG = (ROOT / "modules/settings/configs/OverviewConfig.qml").read_text()
BG_CONFIG = (ROOT / "modules/settings/configs/BackgroundConfig.qml").read_text()
BG_OPTIONS = (ROOT / "modules/settings/configs/sections/BackgroundOptionsSection.qml").read_text()
NOTCH_ISLAND = (ROOT / "modules/ii/dynamicIsland/styles/notch/NotchIsland.qml").read_text()
NOTCH_CONTENT = (ROOT / "modules/ii/dynamicIsland/styles/notch/NotchContent.qml").read_text()
WIDGETS_WINDOW = (ROOT / "modules/ii/background/BackgroundWidgetsWindow.qml").read_text()
PERSISTENT = (ROOT / "modules/common/Persistent.qml").read_text()


def extract_function(source, name):
    start = source.index(f"function {name}(")
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError(f"unterminated function {name}")


class RealGnomeStyleTests(unittest.TestCase):
    def test_style_is_selectable_next_to_gnome_like(self):
        self.assertIn('"background.overviewBackgroundStyle": ["", "gnome", "real-gnome"', CONFIG_QML)
        for page in (OVERVIEW_CONFIG, BG_CONFIG, BG_OPTIONS):
            self.assertIn('"real-gnome"', page)
            self.assertIn('Translation.tr("Gnome Like")', page)
            self.assertIn('Translation.tr("Real Gnome")', page)

    def test_controller_reuses_gnome_pipeline(self):
        self.assertIn('return root.resolvedStyle === "real-gnome" ? "gnome" : root.resolvedStyle;', CONTROLLER)
        self.assertIn('readonly property bool isGnomeLike: effectiveStyle === "gnome"', CONTROLLER)
        self.assertRegex(CONTROLLER, r'isRealGnome: resolvedStyle === "real-gnome" && isGnomeLike\s*\n\s*&& !scrollingLayout && !lockDriven && !isOverviewAlwaysActive')

    def test_gnome_like_keeps_its_original_motion(self):
        # Plain Gnome Like still runs on elementMove; only Real Gnome swaps curves.
        self.assertIn(": Appearance.animation.elementMove.duration", CONTROLLER)
        self.assertIn(": Appearance.animation.elementMove.bezierCurve", CONTROLLER)
        self.assertIn("realGnomeOpenCurve: [0.22, 1, 0.36, 1, 1, 1]", CONTROLLER)
        # No overshoot in either Real Gnome curve.
        for name in ("realGnomeOpenCurve", "realGnomeCloseCurve"):
            values = [float(v) for v in re.search(name + r": \[([^\]]+)\]", CONTROLLER).group(1).split(",")]
            self.assertTrue(all(0.0 <= v <= 1.0 for v in values), name)

    def test_plane_aims_under_the_thumbnails(self):
        self.assertIn("GlobalStates.realGnomeAreas[name]", BG_ROOT)
        self.assertIn("function setRealGnomeArea(screenName, rect)", GLOBAL_STATES)
        self.assertIn("realGnomeAimed ? realGnomeTarget.x / (1.0 - realGnomeScale)", CONTROLLER)
        # No workspace grid: the plane and its neighbours are the workspaces.
        self.assertIn("active: root.visible && !root.realGnome && !GlobalStates.searchOnlyMode", OVERVIEW)
        self.assertIn("&& !root.realGnome\n        && LauncherSearch.query", NOTCH_ISLAND)
        self.assertIn("borderOpacity: isGnomeLike && !scrollingLayout && !isRealGnome", CONTROLLER)
        self.assertIn("&& !wallpaperImageRoot.overviewController.isRealGnome", WALLPAPER_IMAGE)

    def test_vignette_only_for_real_gnome(self):
        self.assertIn("id: realGnomeVignette", WALLPAPER_IMAGE)
        self.assertIn("visible: wallpaperImageRoot.overviewController.isRealGnome && wallpaperImageRoot.overviewAnimationVisible", WALLPAPER_IMAGE)
        self.assertIn("vignetteAmount: isRealGnome ? progress : 0.0", CONTROLLER)

    def test_open_zoom_waits_for_the_handoff(self):
        # The zoom is held at 0 until the captures have a frame and Hyprland hid the windows.
        self.assertIn("property bool overviewZoomHeld: false", GLOBAL_STATES)
        self.assertIn("openHold: GlobalStates.overviewZoomHeld && bgRoot.isMonitorFocused", BG_ROOT)
        self.assertIn("(active && !root.openHold ? 1.0 : 0.0)", CONTROLLER)
        self.assertIn("onIncomingCapturesReadyChanged", TRANSITION)
        self.assertIn("transitionScope.windowHandoffApplied = true;", TRANSITION)
        self.assertNotIn("openDelayTimer.restart();", TRANSITION.replace("openDelayTimer.restart();\n                Qt.callLater(tRoot.requestOpenHandoff)", ""))

    def test_restore_does_not_fade_windows_in(self):
        # Disabling the hide rule alone fades alpha in over fadeSwitch (800 ms):
        # a named no_anim rule is held on across the restore, then switched off.
        self.assertIn("name = 'quickshell-overview-window-restore'", TRANSITION)
        self.assertIn("no_anim = true", TRANSITION)
        self.assertIn("restoreRuleOffTimer.restart()", TRANSITION)
        self.assertNotIn("class = '.*' }, opacity = '1.0", TRANSITION)

    def test_current_workspace_slides_with_its_wallpaper(self):
        # The background publishes the plane's exact picture; the cards paint it and the
        # plane steps aside only once a card covers it, and returns before the card leaves.
        self.assertIn("GlobalStates.setRealGnomePlaneWallpaper(wallpaperImageRoot.screenName", WALLPAPER_IMAGE)
        self.assertIn("opacity: wallpaperPlanes.realGnomePlaneHidden ? 0 : 1", WALLPAPER_IMAGE)
        self.assertIn("GlobalStates.realGnomePlaneHiddenScreen = tRoot.screenName;", TRANSITION)
        self.assertIn("(tRoot.isRealGnome && !tRoot.planeHandedOver)", TRANSITION)
        self.assertIn("tRoot.returnPlane()", TRANSITION)
        self.assertIn("clip: tRoot.isRealGnome && ((tRoot.sliding && !tRoot.stripFullMode) || tRoot.searchSlide > 0.001)", TRANSITION)

    def test_workspace_indicator_under_the_plane(self):
        indicator = (ROOT / "modules/ii/overview/RealGnomeWorkspaceIndicator.qml").read_text()
        # In-use workspaces of the group plus one empty, like GNOME's dynamic workspaces.
        self.assertIn("Math.max(root.highestUsed, root.activeWs) - root.groupStart + 2", indicator)
        self.assertIn("hl.dsp.focus({ workspace = ${dot.workspaceId} })", indicator)
        self.assertIn("RealGnomeWorkspaceIndicator {", NOTCH_ISLAND)
        self.assertIn("RealGnomeWorkspaceIndicator {", OVERVIEW)
        # The plane leaves the bottom strip to it.
        self.assertIn("root.realGnomeIndicatorRoom - top", NOTCH_ISLAND)

    def test_strip_is_shown_in_bands_not_through_a_mask(self):
        self.assertIn("component StripBand: ShaderEffectSource", TRANSITION)
        self.assertNotIn("maskInverted", TRANSITION)

    def test_close_restores_windows_when_the_zoom_lands(self):
        self.assertIn("tRoot.overviewController.progress === 0)", TRANSITION)
        self.assertIn("exitSettleTimer.restart()", TRANSITION)
        # Timers are fallbacks only, derived from the close duration.
        self.assertIn("interval: tRoot.closeDuration + 150", TRANSITION)
        self.assertIn("interval: tRoot.closeDuration + 600", TRANSITION)

    def test_slide_is_continuous_and_unscaled(self):
        self.assertIn("scale: tRoot.isRealGnome ? 1.0", TRANSITION)
        # One strip: slots and neighbour cards are both placed from stripCenter.
        self.assertIn("((incoming ? tRoot.displayedWsId : tRoot.slideFromWs) - tRoot.stripCenter) * tRoot.workspaceSlideDistance", TRANSITION)
        self.assertIn("(peek.workspaceId - tRoot.stripCenter) * tRoot.workspaceSlideDistance", TRANSITION)
        self.assertIn("slideFromCenter = center", TRANSITION)
        # Neighbours never fade out for a slide.
        self.assertNotIn("peekOpacity", TRANSITION)
        self.assertIn("clip: tRoot.isRealGnome && ((tRoot.sliding && !tRoot.stripFullMode) || tRoot.searchSlide > 0.001)", TRANSITION)

    def test_picker_input_layer(self):
        self.assertIn("RealGnomeWindowPicker {", OVERVIEW)
        self.assertIn("HoverHandler", PICKER)
        self.assertIn("GlobalStates.realGnomeHoveredWindow = slot.address", PICKER)
        self.assertIn("hl.dsp.window.close", PICKER)
        self.assertIn("objectProp: \"address\"", PICKER)

    def test_switch_never_hides_the_slot_on_screen(self):
        # Progress must reach 0 before the slots trade roles: the slot on screen
        # would otherwise be hidden for a moment and drop its screencopy frame.
        reset = TRANSITION.index("transitionProgress = 0.0\n                currentSlot = 1 - currentSlot")
        self.assertGreater(reset, 0)

    def test_captures_hold_still_while_sliding(self):
        self.assertIn("&& !(tRoot.isRealGnome && tRoot.sliding)", TRANSITION)

    def test_search_slides_windows_out_of_the_plane(self):
        # Windows leave vertically, away from the search; neighbours stay (no fade of the container).
        self.assertIn("y: (tRoot.isVertical ? offset : 0) + tRoot.searchSlideOffset", TRANSITION)
        self.assertIn("(tRoot.barBottom && !tRoot.barVertical ? -1 : 1)", TRANSITION)
        self.assertIn("opacity: tRoot.shouldBeActive ? 1.0 : 0.0", TRANSITION)
        self.assertNotIn("searchFade", TRANSITION)

    def test_search_fade_reads_both_query_sources(self):
        self.assertIn('LauncherSearch.query !== ""', TRANSITION)
        self.assertIn('LauncherSearch.query === ""', NOTCH_ISLAND)

    def test_island_hosts_picker_and_publishes_area(self):
        self.assertIn("RealGnomeWindowPicker {", NOTCH_ISLAND)
        self.assertIn("container.mapToItem(null, 0, container.height).y", NOTCH_ISLAND)
        self.assertIn("outsideGrid || root.realGnomeSearchOpen ? fullWindow : maskTarget", NOTCH_ISLAND)
        self.assertIn("active: root.realGnome && root.monitorIsFocused && !GlobalStates.islandOwnsSearch", OVERVIEW)

    def test_area_survives_restarts(self):
        self.assertIn("property var realGnomeAreas: ({})", PERSISTENT)
        self.assertIn("Persistent.states.overview.realGnomeAreas = saved", GLOBAL_STATES)
        self.assertIn("Persistent.states.overview?.realGnomeAreas?.[name]", BG_ROOT)

    def test_dock_steps_aside_in_the_overview(self):
        self.assertIn("!dockRoot.realGnomeOverviewOpen && (dock.pinned", (ROOT / "modules/ii/dock/Dock.qml").read_text())

    def test_desktop_widgets_leave_the_plane(self):
        self.assertIn("bgWidgetsWindow.overviewController.isRealGnome && bgWidgetsWindow.overviewController.active", WIDGETS_WINDOW)

    def test_qml_handlers_are_unique(self):
        for name, text in (("transition", TRANSITION), ("overview", OVERVIEW), ("picker", PICKER)):
            handlers = re.findall(r"^\s*(on[A-Z]\w*):", text, re.M)
            # Handlers repeat across different objects; the ones added here must not.
            for handler in ("onPickerRectChanged", "onSlidingChanged", "onIsRealGnomeChanged",
                            "onPickerFinalScaleChanged", "onRealGnomeChanged", "onShownChanged"):
                self.assertLessEqual(handlers.count(handler), 1, f"{name}: {handler}")


@unittest.skipUnless(shutil.which("node"), "node is required to run the picker layout")
class RealGnomePickerLayoutTests(unittest.TestCase):
    SCREEN = (1920, 1080)

    def layout(self, windows, final_scale=0.66):
        function = extract_function(TRANSITION, "computePickerLayout")
        function = re.sub(r"function computePickerLayout\(list\)", "function computePickerLayout(list)", function)
        script = """
const Qt = { rect: (x, y, width, height) => ({ x, y, width, height }) };
const windows = %s;
const tRoot = {
  pickerFinalScale: %f,
  pickerSpacing: 28,
  screen: { width: %d, height: %d },
  monitorData: { x: 0, y: 0 },
  normalizedAddress: (v) => v,
  clientForToplevel: (t) => windows.find(w => w.address === t.HyprlandToplevel.address),
};
%s
const list = windows.map(w => ({ HyprlandToplevel: { address: w.address } }));
console.log(JSON.stringify(computePickerLayout(list)));
""" % (json.dumps(windows), final_scale, self.SCREEN[0], self.SCREEN[1], function)
        out = subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True)
        return json.loads(out.stdout)

    def window(self, address, x, y, w, h):
        return {"address": address, "at": [x, y], "size": [w, h]}

    def assert_valid(self, windows, result, final_scale=0.66):
        self.assertEqual(set(result), {w["address"] for w in windows})
        rects = list(result.values())
        pad = 40 / final_scale
        for w in windows:
            r = result[w["address"]]
            # Aspect ratio kept, never above the real size.
            self.assertAlmostEqual(r["width"] / r["height"], w["size"][0] / w["size"][1], places=3)
            self.assertLessEqual(r["width"], w["size"][0] + 1e-6)
            # Inside the plane's padded area.
            self.assertGreaterEqual(r["x"], pad - 1e-6)
            self.assertGreaterEqual(r["y"], pad - 1e-6)
            self.assertLessEqual(r["x"] + r["width"], self.SCREEN[0] - pad + 1e-6)
            self.assertLessEqual(r["y"] + r["height"], self.SCREEN[1] - pad + 1e-6)
        spacing = 28 / final_scale
        for i, a in enumerate(rects):
            for b in rects[i + 1:]:
                overlap_x = min(a["x"] + a["width"], b["x"] + b["width"]) - max(a["x"], b["x"])
                overlap_y = min(a["y"] + a["height"], b["y"] + b["height"]) - max(a["y"], b["y"])
                self.assertFalse(overlap_x > -spacing + 1e-3 and overlap_y > -spacing + 1e-3,
                                 f"slots closer than the spacing: {a} {b}")

    def test_single_window_is_centred_at_real_size(self):
        windows = [self.window("0xa", 100, 100, 800, 600)]
        result = self.layout(windows)
        self.assert_valid(windows, result)
        r = result["0xa"]
        self.assertAlmostEqual(r["width"], 800)
        self.assertAlmostEqual(r["x"] + r["width"] / 2, self.SCREEN[0] / 2, delta=1)

    def test_overlapping_maximized_windows_spread_apart(self):
        windows = [self.window(f"0x{i}", 10, 50, 1900, 1020) for i in range(3)]
        self.assert_valid(windows, self.layout(windows))

    def test_many_mixed_windows(self):
        windows = [
            self.window("0x1", 10, 50, 945, 1020),
            self.window("0x2", 965, 50, 945, 500),
            self.window("0x3", 965, 570, 945, 500),
            self.window("0x4", 400, 300, 600, 400),
            self.window("0x5", 0, 0, 300, 900),
            self.window("0x6", 1500, 800, 400, 250),
            self.window("0x7", 700, 200, 1200, 700),
        ]
        self.assert_valid(windows, self.layout(windows))

    def test_rows_follow_vertical_order(self):
        windows = [
            self.window("0xtop", 100, 60, 1700, 400),
            self.window("0xbottom", 100, 600, 1700, 400),
        ]
        result = self.layout(windows)
        self.assert_valid(windows, result)
        self.assertLess(result["0xtop"]["y"], result["0xbottom"]["y"])

    def test_empty_workspace(self):
        self.assertEqual(self.layout([]), {})


if __name__ == "__main__":
    unittest.main()
