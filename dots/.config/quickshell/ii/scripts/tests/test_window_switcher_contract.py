#!/usr/bin/env python3
"""Contract for the Alt+Tab window switcher.

What the nested-Hyprland runs proved and a later edit could quietly undo: that the keys are
compositor binds (Alt coming up is a *root* release bind, Q survives type-to-search's unbinds,
the submap's Tab comes back with the entry bind), that the commit from a release bind is
handled on `released`, that both faces are views on the one service, and that nothing in the
views brings its own timing.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HYPR = ROOT.parents[1] / "hypr"

SERVICE = ROOT / "services/WindowSwitcher.qml"
BINDS = ROOT / "services/HyprlandBinds.qml"
PANEL_DIR = ROOT / "modules/common/panels/windowSwitcher"
PANEL = PANEL_DIR / "WindowSwitcherPanel.qml"
CARD = PANEL_DIR / "SwitcherCard.qml"
ISLAND = ROOT / "modules/ii/dynamicIsland"
ISLAND_FACE = ISLAND / "widgets/IslandWindowSwitcher.qml"
ISLAND_SOURCE = ISLAND / "core/sources/WindowSwitcherSource.qml"
ISLAND_SOURCES = ISLAND / "core/sources/IslandSources.qml"
REGISTRY = ISLAND / "core/IslandRegistry.qml"
POLICY = ISLAND / "core/IslandPolicy.qml"
NOTCH_CONTENT = ISLAND / "styles/notch/NotchContent.qml"
NOTCH_ISLAND = ISLAND / "styles/notch/NotchIsland.qml"
CONFIG = ROOT / "modules/common/Config.qml"
APPEARANCE = ROOT / "modules/common/Appearance.qml"
GLOBAL_STATES = ROOT / "GlobalStates.qml"
WINDOWS_PAGE = ROOT / "modules/settings/configs/WindowsConfig.qml"
ISLAND_PAGE = ROOT / "modules/settings/configs/widgets/DynamicIslandActivitiesConfig.qml"
PAGE_REGISTRY = ROOT / "modules/common/SettingsPageRegistry.qml"
FAMILIES = [ROOT / f"panelFamilies/{name}.qml" for name in ("IllogicalImpulseFamily", "WaffleFamily", "TabletFamily")]

VIEWS = [PANEL, CARD, ISLAND_FACE]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class KeyTests(unittest.TestCase):
    def setUp(self):
        self.service = read(SERVICE)

    def test_submap_name_is_shared_with_the_binds_browser(self):
        name = re.search(r'submapName: "([^"]+)"', self.service).group(1)
        self.assertIn(f'windowSwitcherSubmap: "{name}"', read(BINDS))

    def test_alt_release_is_a_transparent_root_bind(self):
        # Hyprland matches a release against the submap the key went down in, and Alt went
        # down before the submap was entered.
        self.assertRegex(self.service,
            r'hl\.bind\(k, finish\("Commit"\), \{ release = true, ignore_mods = true, transparent = true')

    def test_finishing_leaves_the_submap_inside_the_compositor(self):
        self.assertIn('hl.dispatch(hl.dsp.submap("reset")); g(n)', self.service)

    def test_release_globals_are_handled_on_released(self):
        self.assertRegex(self.service, r'onReleased: \{\s*if \(modelData === "Commit" \|\| modelData === "Cancel"\)')

    def test_q_survives_bare_letter_unbinds(self):
        self.assertIn('hl.bind("ALT + Q"', self.service)
        self.assertNotRegex(self.service, r'hl\.bind\("Q"')

    def test_submap_tab_is_restored_with_the_entry(self):
        # hl.unbind("ALT + Tab") reaches into every submap.
        entry = self.service[self.service.index("function entryChunk"):]
        entry = entry[:entry.index("\n    }\n")]
        self.assertIn('pcall(hl.unbind, "ALT + Tab")', entry)
        self.assertIn('hl.define_submap("${S}"', entry)

    def test_submap_is_defined_once_per_config_generation(self):
        self.assertIn("if not __ii_window_switcher then", self.service)

    def test_shortcut_descriptions_are_not_translated(self):
        self.assertNotRegex(self.service, r"description: Translation\.tr")


class StructureTests(unittest.TestCase):
    def test_every_family_loads_the_panel(self):
        for family in FAMILIES:
            with self.subTest(family=family.name):
                self.assertIn("WindowSwitcherPanel", read(family))

    def test_views_do_not_keep_their_own_model(self):
        for view in VIEWS:
            with self.subTest(view=view.name):
                text = read(view)
                self.assertNotIn("HyprlandData.windowList", text)
                self.assertNotIn("Hyprland.dispatch", text)

    def test_panel_never_takes_the_keyboard(self):
        self.assertIn("WlrLayershell.keyboardFocus: WlrKeyboardFocus.None", read(PANEL))

    def test_panel_namespace_has_a_layer_rule(self):
        namespace = re.search(r'WlrLayershell\.namespace: "([^"]+)"', read(PANEL)).group(1)
        self.assertIn(f'namespace = "{namespace}"', read(HYPR / "hyprland/rules.lua"))

    def test_island_activity_is_registered(self):
        self.assertIn('id: "windowSwitcher"', read(REGISTRY))
        sources = read(ISLAND_SOURCES)
        self.assertIn("windowSwitcher, askpass", sources)
        self.assertIn("WindowSwitcherSource windowSwitcher", sources)
        self.assertIn('activityId: "windowSwitcher"', read(ISLAND_SOURCE))

    def test_island_switcher_covers_the_face_instead_of_replacing_it(self):
        content = read(NOTCH_CONTENT)
        self.assertIn('if (content.activityId === "windowSwitcher")\n            return;', content)
        self.assertIn("(1 - content.switcherReveal)", content)

    def test_island_shows_the_switcher_over_fullscreen(self):
        island = read(NOTCH_ISLAND)
        hidden = island[island.index("readonly property bool hidden: {"):]
        self.assertIn("root.windowSwitcherActive", hidden[:600])

    def test_island_ownership_is_mirrored(self):
        self.assertIn('property: "islandOwnsWindowSwitcher"', read(POLICY))
        self.assertIn("property bool islandOwnsWindowSwitcher: false", read(GLOBAL_STATES))


class MotionTests(unittest.TestCase):
    def test_views_use_appearance_timing(self):
        for view in VIEWS:
            with self.subTest(view=view.name):
                self.assertNotRegex(read(view), r"duration:\s*\d")

    def test_snap_token_does_not_run_to_end(self):
        appearance = read(APPEARANCE)
        snap = appearance[appearance.index("property QtObject elementMoveSnap"):]
        snap = snap[:snap.index("property QtObject elementResize")]
        self.assertNotIn("alwaysRunToEnd", snap)

    def test_selection_retargets(self):
        # Behaviours built from the run-to-end components would queue a burst of Tabs.
        for view in VIEWS:
            with self.subTest(view=view.name):
                text = read(view)
                self.assertNotIn("elementMoveFast.numberAnimation.createObject(highlight", text)
                self.assertNotIn("elementMove.numberAnimation", text)


class SettingsTests(unittest.TestCase):
    def test_config_keys(self):
        config = read(CONFIG)
        block = config[config.index("property JsonObject windowSwitcher: JsonObject {\n                property bool enable"):]
        block = block[:block.index("}")]
        for key in ("bool enable: true", "bool includeOtherWorkspaces: true", "bool showThumbnails: true"):
            self.assertIn(key, block)
        # The island toggle needs the legacy key while useModernSchema is false.
        self.assertIn("property bool disableWindowSwitcher: false", config)

    def test_settings_entries(self):
        page = read(WINDOWS_PAGE)
        for text in ("Enable Alt+Tab window switcher", "Include windows on other workspaces", "Show window thumbnails"):
            self.assertIn(f'text: Translation.tr("{text}")', page)
        self.assertIn("disableWindowSwitcher", read(ISLAND_PAGE))
        self.assertIn('"Alt+Tab"', read(PAGE_REGISTRY))

    def test_cheatsheet_documents_the_runtime_bind(self):
        self.assertIn("--#/# bind = ALT, Tab,,", read(HYPR / "hyprland/keybinds.lua"))


if __name__ == "__main__":
    unittest.main()
