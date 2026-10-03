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
ISLAND_PAGE = ROOT / "modules/settings/configs/DynamicIslandConfig.qml"
PAGE_REGISTRY = ROOT / "modules/common/SettingsPageRegistry.qml"
FAMILIES = [ROOT / f"panelFamilies/{name}.qml" for name in ("IllogicalImpulseFamily", "WaffleFamily", "TabletFamily")]

PEEK = PANEL_DIR / "WindowSwitcherPeek.qml"
LOGIC = ROOT / "services/windowSwitcher/WindowSwitcherLogic.js"
TYPE_TO_SEARCH = ROOT / "services/TypeToSearch.qml"
SHARED_VIEWS = [PANEL_DIR / f"{name}.qml" for name in
                ("PeekCountdown", "WorkspaceChip", "SwitcherTitleLine", "SwitcherSearchLine", "SwitcherHints")]

VIEWS = [PANEL, CARD, ISLAND_FACE] + SHARED_VIEWS


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class KeyTests(unittest.TestCase):
    """What the key sequences do is run for real in test_window_switcher_binds.cjs; these pin
    the shape that test cannot see (where binds live, what the shell does with the globals)."""

    def setUp(self):
        self.service = read(SERVICE)

    def test_submap_names_are_hidden_by_the_binds_browser(self):
        tag = re.search(r'bindTag: "([^"]+)"', self.service).group(1)
        self.assertIn(f'windowSwitcherSubmap: "{tag}"', read(BINDS))
        for prop in ("submapName", "typingSubmapName"):
            self.assertTrue(re.search(rf'{prop}: "([^"]+)"', self.service).group(1).startswith(tag))
        self.assertIn("startsWith(root.windowSwitcherSubmap)", read(BINDS))

    def test_alt_release_is_a_transparent_root_bind(self):
        # Hyprland matches a release against the submap the key went down in, and Alt went
        # down before the submap was entered.
        self.assertRegex(self.service,
            r'hl\.bind\(k, release, \{ release = true, ignore_mods = true, transparent = true')

    def test_finishing_leaves_the_submap_inside_the_compositor(self):
        self.assertIn('hl.dispatch(hl.dsp.submap("reset")); g(n)', self.service)

    def test_release_globals_are_handled_on_released(self):
        self.assertRegex(self.service, r'onReleased: \{\s*if \(modelData === "Commit" \|\| modelData === "Cancel"'
                                       r' \|\| modelData === "Release"\)')

    def test_search_keys_survive_bare_letter_unbinds(self):
        # Type-to-search unbinds bare letters, and hl.unbind reaches into every submap: Alt
        # held, they are spelled with Alt; Alt up, they are bound afresh as the typing submap opens.
        self.assertIn('hl.bind("ALT + " .. k, function() __ii_alt_tab_key(k) end', self.service)
        self.assertIn('hl.bind("ALT + SHIFT + " .. k', self.service)
        typing = self.service[self.service.index("function __ii_alt_tab_typing_keys()"):]
        typing = typing[:typing.index("\n  end\n")]
        self.assertIn('pcall(hl.unbind, k)', typing)
        self.assertIn('hl.bind(k, function() __ii_alt_tab_key(k) end', typing)
        # …and type-to-search stays disarmed while the switcher is open.
        self.assertIn("&& !WindowSwitcher.active", read(TYPE_TO_SEARCH))

    def test_digits_go_by_key_position(self):
        # AZERTY's 1 is Shift+&: the top row by keycode is the digits on every layout.
        self.assertIn('hl.bind("ALT + code:" .. d[2], digit(d[1])', self.service)
        self.assertIn('if __ii_alt_tab_q > 0 or d == "0" then __ii_alt_tab_key(d) else g("Jump_" .. d) end', self.service)
        self.assertIn('readonly property string sameAppKey: "code:49"', self.service)

    def test_close_and_editing_keys(self):
        define = self.service[self.service.index("readonly property string defineChunk"):]
        self.assertIn('hl.bind("Delete", function() g("Close") end', define)
        self.assertIn('hl.bind("BackSpace", back,', define)
        self.assertIn('hl.bind("Home", function() g("Home") end', define)
        self.assertIn('hl.bind("End", function() g("End") end', define)
        # Escape clears a search first (Alt held); with none, or with Alt up, it cancels -
        # leaving the submap inside the compositor either way.
        self.assertIn('hl.bind("Escape", escape,', define)
        self.assertIn('hl.bind("Escape", finish("Cancel"),', define)
        self.assertNotIn('hl.bind("ALT + Q"', self.service)

    def test_search_anywhere_never_takes_a_users_alt_letter(self):
        chunk = self.service[self.service.index("function searchChunk"):]
        chunk = chunk[:chunk.index("\n    }\n")]
        self.assertIn('on && owner === "none"', chunk)
        self.assertIn('!on && owner === "ours"', chunk)
        # Unbinding the root Alt+key takes the submap's too: it goes straight back.
        self.assertIn("root.searchKeyBind(key)", chunk)

    def test_release_after_a_peek_switches_without_animations(self):
        commit = self.service[self.service.index("function commit"):]
        commit = commit[:commit.index("\n    }\n")]
        self.assertIn("hl.config({ animations = { enabled = false } })", commit)
        # Back on a compositor timer: a shell dying right after cannot leave them off.
        self.assertIn("__ii_alt_tab_timer = hl.timer(function()", commit)
        self.assertIn("type = \"oneshot\"", commit)
        self.assertIn("hl.config({ animations = { enabled = __ii_alt_tab_animations } })", self.service)
        self.assertNotIn("animationsTimer", self.service)

    def test_a_starting_shell_cleans_up_after_a_dead_one(self):
        self.assertIn('Quickshell.execDetached(["hyprctl", "eval", root.restoreChunk]);', self.service)
        restore = self.service[self.service.index("readonly property string restoreChunk"):]
        restore = restore[:restore.index("end`")]
        self.assertIn('hl.dispatch(hl.dsp.submap("reset"))', restore)
        # The peek writes down every window it undims - in a file, since the config reload a
        # starting shell brings wipes Lua globals - and the next shell redims what it lists.
        peek = read(PEEK)
        self.assertIn("WindowSwitcher.undimRecordPath, root.noDimChunk(address, true)]", peek)
        self.assertLess(peek.index('printf "%s\\\\n" "$@" > "$0" && hyprctl eval "$c"'), peek.index("function redim"))
        self.assertIn('command: ["sh", "-c", \'cat "$0" 2>/dev/null; rm -f "$0"\', root.undimRecordPath]', self.service)
        self.assertIn("redimProc.running = true;", self.service)

    def test_commit_brings_the_pointer_along_with_follow_mouse(self):
        # Otherwise the shrinking island hands focus to the window under the pointer.
        focus = self.service[self.service.index("function focusChunk"):]
        self.assertIn('hl.get_config("input.follow_mouse") == 1', focus)
        self.assertIn("hl.dsp.cursor.move({ x = ", focus)

    def test_commit_leaves_the_pointer_alone_with_no_warps(self):
        # cursor:no_warps means the user never wants the pointer moved for them.
        focus = self.service[self.service.index("function focusChunk"):]
        self.assertIn('and not hl.get_config("cursor.no_warps") then', focus)

    def test_submap_tab_is_restored_with_the_entry(self):
        # hl.unbind("ALT + Tab") reaches into every submap.
        entry = self.service[self.service.index("function entryChunk"):]
        entry = entry[:entry.index("\n    }\n")]
        self.assertIn('pcall(hl.unbind, "ALT + Tab")', entry)
        self.assertIn('for _, m in ipairs({ "${S}", "${T}" }) do', entry)
        # Alt+` is never unbound when it is the user's.
        self.assertIn("if (!root.sameAppConflict)", entry)

    def test_submap_is_defined_once_per_config_generation(self):
        self.assertIn("if __ii_alt_tab_v ~= 2 then", self.service)

    def test_pure_logic_lives_where_the_tests_reach_it(self):
        self.assertIn('import "windowSwitcher/WindowSwitcherLogic.js" as Logic', self.service)
        self.assertTrue((ROOT / "scripts/tests/test_window_switcher_logic.cjs").exists())
        self.assertTrue((ROOT / "scripts/tests/test_window_switcher_binds.cjs").exists())

    def test_peek_follows_the_selection_to_nothing(self):
        # A search matching nothing peeks at nothing, rather than at a window it filtered out.
        arm = self.service[self.service.index("function armPeek"):]
        arm = arm[:arm.index("\n    }\n")]
        self.assertIn("root.peekEntry = root.selectedEntry;\n            return;", arm)
        self.assertNotIn("if (root.selectedEntry)\n                root.peekEntry", arm)

    def test_typing_puts_the_peek_aside_until_it_stops(self):
        # A peek following every keystroke flashed half-typed matches across workspaces.
        query = self.service[self.service.index("function setQuery"):]
        query = query[:query.index("\n    }\n")]
        self.assertLess(query.index("root.peeking = false;"), query.index("root.query = text;"))
        self.assertTrue(query.rstrip().endswith("root.armPeek();"))
        # The peek it ended fades out on its own picture, with no capture swapped in under it.
        peek = (PANEL_DIR / "WindowSwitcherPeek.qml").read_text()
        self.assertIn("!WindowSwitcher.peeking && !root.lingering && WindowSwitcher.selectedEntry", peek)
        self.assertIn("onLingeringChanged: root.prepare()", peek)

    def test_shortcut_descriptions_are_not_translated(self):
        self.assertNotRegex(self.service, r"description: Translation\.tr")


class StructureTests(unittest.TestCase):
    def test_every_family_loads_the_panel_and_the_peek(self):
        for family in FAMILIES:
            with self.subTest(family=family.name):
                self.assertIn("WindowSwitcherPanel", read(family))
                self.assertIn("WindowSwitcherPeek", read(family))
        # The peek is its own load, not the panel's.
        self.assertNotIn("WindowSwitcherPeek {}", read(PANEL))

    def test_panel_stays_up_while_peeking(self):
        panel = read(PANEL)
        self.assertIn("readonly property bool open: panelWindow.entered && root.showing\n", panel)
        self.assertNotIn("!WindowSwitcher.peeking ||", panel)

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

    def test_peek_is_click_through_and_under_the_switcher(self):
        peek = read(PANEL_DIR / "WindowSwitcherPeek.qml")
        self.assertIn("mask: Region {}", peek)
        self.assertIn("WlrKeyboardFocus.None", peek)
        namespace = re.search(r'WlrLayershell\.namespace: "([^"]+)"', peek).group(1)
        # Outside quickshell.*, which rules.lua blurs wholesale.
        self.assertFalse(namespace.startswith("quickshell"))
        rules = read(HYPR / "hyprland/rules.lua")
        self.assertIn(f'namespace = "{namespace}" }}, order = 1', rules)
        # The click-outside catcher for a search left open with Alt up sits under them too.
        self.assertIn('WlrLayershell.namespace: "ii-alt-tab-catcher"', peek)
        self.assertIn('namespace = "ii-alt-tab-catcher" }, order = 1', rules)
        self.assertIn("active: WindowSwitcher.enabled && WindowSwitcher.active && WindowSwitcher.released", peek)

    def test_peek_gives_every_window_its_own_capture(self):
        # Pointing a live capture at another window left the old window's frames in its
        # buffers: the screen alternated between the two every frame.
        peek = read(PANEL_DIR / "WindowSwitcherPeek.qml")
        self.assertIn('model: win.address !== "" ? [win.address] : []', peek)
        self.assertIn("delegate: ScreencopyView", peek)
        # The windows around it are keyed by address, so a list refresh restarts no capture.
        self.assertEqual(peek.count('objectProp: "address"'), 3)

    def test_peek_opens_on_a_picture(self):
        peek = read(PANEL_DIR / "WindowSwitcherPeek.qml")
        # Captured ahead while the switcher is up, and the backdrop waits for the first frame.
        self.assertIn("root.preparing || root.showing || root.lingering", peek)
        self.assertIn("root.showing && peekWindow.currentSlot.ready", peek)

    def test_peek_asks_hyprctl_once_per_window(self):
        peek = read(PEEK)
        self.assertIn('command: ["hyprctl", "--batch", Logic.windowLookBatch(lookProc.address)]', peek)
        self.assertNotIn("alphaProc", peek)
        self.assertNotIn("root.alphas", peek)

    def test_peek_draws_hyprlands_corners(self):
        peek = read(PEEK)
        self.assertIn("Logic.roundedPath(win.width, win.height, win.look.rounding, win.look.power)", peek)
        self.assertIn("maskSource: cornerMask", peek)
        self.assertIn("rounding_power", read(LOGIC))

    def test_whole_workspace_peek_keeps_the_bar(self):
        peek = read(PEEK)
        self.assertIn("root.whole ? (peekWindow.monitor?.reserved ?? [0, 0, 0, 0]) : [0, 0, 0, 0]", peek)
        self.assertIn("clip: root.whole", peek)
        self.assertIn("Logic.stacking(WindowSwitcher.workspaceEntries(entry.workspaceId), entry.address)", peek)

    def test_peek_draws_the_window_at_its_own_opacity(self):
        peek = read(PANEL_DIR / "WindowSwitcherPeek.qml")
        logic = read(LOGIC)
        for prop in ("opacity", "opacity_override", "decoration:active_opacity", "opacity_inactive"):
            self.assertIn(prop, logic)
        self.assertIn("opacity: win.alpha", peek)
        self.assertIn("blurWhenWindowsOpen", peek)
        # Over the background as it really is: zoomed like BackgroundRoot (3 % more with a
        # blur on), and without WindowBlur's dim, which never reaches the screen.
        self.assertIn("? 1.03 : 1)", peek)
        self.assertIn("targetScale *= 1.03;", read(ROOT / "modules/ii/background/BackgroundRoot.qml"))
        self.assertIn("scale: root.wallpaperScale", peek)
        self.assertNotIn("colLayer0, 0.4", peek)
        # dim_inactive lands in the capture: captured windows go undimmed while the peek is
        # around, only if dimmed to begin with, and get their own setting back after.
        self.assertIn("getprop ${w} no_dim", logic)
        self.assertIn('prop = "no_dim", value = "${value}"', peek)
        self.assertIn("root.noDimChunk(address, false)", peek)
        self.assertIn("if (!peekLoader.active)\n                root.redim();", peek)
        self.assertIn("Component.onDestruction: root.redim()", peek)

    def test_peek_hides_the_screen_being_left(self):
        # A dim over the current screen let the window being left show through a
        # translucent one: the backdrop is the target workspace's, full screen and opaque.
        peek = read(PANEL_DIR / "WindowSwitcherPeek.qml")
        backdrop = peek[peek.index("id: backdrop"):]
        self.assertNotIn("visible: false", backdrop[:backdrop.index("Image {")])
        self.assertNotIn("m3shadow", peek)
        self.assertNotIn("ShaderEffectSource", peek)

    def test_peek_fades_out_as_one_picture_over_the_landed_window(self):
        peek = read(PANEL_DIR / "WindowSwitcherPeek.qml")
        # One flattened fade: piece by piece, the dim thinned and the wallpaper flashed.
        self.assertIn("opacity: peekWindow.reveal\n"
                      "                layer.enabled: peekWindow.reveal > 0 && peekWindow.reveal < 1\n", peek)
        self.assertEqual(peek.count("opacity: peekWindow.reveal"), 1)
        # No shrink on the way out: it fades into the real window in the same place.
        self.assertIn("scale: peekWindow.open ? 0.97 + 0.03 * peekWindow.reveal : 1", peek)
        # Held until the chosen window has focus underneath.
        self.assertIn("readonly property bool showing: root.wanted || root.holding", peek)
        self.assertIn("WindowSwitcher.currentAddress === WindowSwitcher.landingAddress", peek)
        service = read(SERVICE)
        self.assertLess(service.index("root.landingAddress = peeked && entry"),
                        service.index("root.finish();", service.index("function commit()")))
        # The real window's border is drawn too, so it does not pop in as the peek lets go.
        for prop in ("border_size", "active_border_color", "inactive_border_color", "rounding"):
            self.assertIn(f"getprop ${{w}} {prop}", read(LOGIC))
        self.assertIn("strokeColor: win.look.color", peek)
        # The window captured ahead never comes back at the release.
        self.assertIn("if (WindowSwitcher.peeking)\n                root.preparedEntry = null;", peek)

    def test_tab_from_an_empty_workspace_returns_to_the_last_window(self):
        # Hyprland.activeToplevel keeps naming the window you left; activewindowv2 says "".
        service = read(SERVICE)
        self.assertIn('event.name === "activewindowv2"', service)
        # Seeded at start: Quickshell knows no active window until focus first changes.
        self.assertIn('command: ["hyprctl", "-j", "activewindow"]', service)
        self.assertIn("list[0].address === root.currentAddress ? 1 : 0", service)
        self.assertIn("const current = root.currentAddress;", service)
        self.assertEqual(service.count("Hyprland.activeToplevel?.address"), 1)

    def test_island_click_centres_a_side_cover(self):
        island = read(ISLAND_FACE)
        self.assertIn("else if (cover.index === WindowSwitcher.selectedIndex)\n"
                      "                            WindowSwitcher.activate(cover.index);\n"
                      "                        else\n"
                      "                            WindowSwitcher.select(cover.index);", island)

    def test_island_switcher_uses_the_large_face_morph(self):
        island = read(NOTCH_ISLAND)
        self.assertIn("largeFace || settlingLarge || container.switcherMorph", island)
        self.assertNotIn("fastMorph", island)

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

    def test_island_cover_flow_loops_and_captures_only_near_covers(self):
        face = read(ISLAND_FACE)
        # The flow wraps past the last window, and each cover slides the short way round.
        self.assertIn("root.count * Math.round(d / root.count)", face)
        self.assertIn("offset -= root.count * Math.round(offset / root.count)", face)
        # Fifteen windows must not mean fifteen live streams.
        self.assertIn("live: root.shown && cover.a < root.reach + 0.5", face)
        self.assertIn("cover.a < root.reach + 1 && cover.entry?.toplevel", face)


class SettingsTests(unittest.TestCase):
    def test_config_keys(self):
        config = read(CONFIG)
        block = config[config.index("property JsonObject windowSwitcher: JsonObject {\n                property bool enable"):]
        block = block[:block.index("}")]
        for key in ("bool enable: true", "bool includeOtherWorkspaces: true", "bool showThumbnails: true",
                    "int peekDelayMs: 600", "bool searchAnywhere: false", "bool currentMonitorOnly: false",
                    "bool peekWholeWorkspace: false", "bool showKeyHints: true"):
            self.assertIn(key, block)
        # The island toggle needs the legacy key while useModernSchema is false.
        self.assertIn("property bool disableWindowSwitcher: false", config)

    def test_settings_entries(self):
        page = read(WINDOWS_PAGE)
        for text in ("Enable Alt+Tab window switcher", "Include windows on other workspaces", "Show window thumbnails",
                     "Only windows on this monitor", "Peek at the whole workspace", "Show key hints",
                     "Alt+Tab in the island"):
            self.assertIn(f'text: Translation.tr("{text}")', page)
        # Every switcher setting is on the Windows page; the island's own toggle stays on its page too.
        self.assertIn("Config.options.bar.floatingNotch.disableWindowSwitcher = !checked;", page)
        self.assertIn("disableWindowSwitcher", read(ISLAND_PAGE))
        self.assertIn('"Alt+Tab"', read(PAGE_REGISTRY))
        self.assertNotIn("dimmed screen", page)

    def test_cheatsheet_documents_the_runtime_binds(self):
        keybinds = read(HYPR / "hyprland/keybinds.lua")
        self.assertIn("--#/# bind = ALT, Tab,,", keybinds)
        self.assertIn("--#/# bind = ALT, grave,,", keybinds)


if __name__ == "__main__":
    unittest.main()
