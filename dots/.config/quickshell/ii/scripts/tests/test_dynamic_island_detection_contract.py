"""Contract tests for the Dynamic Island's event detection.

Each assertion here corresponds to a bug that shipped: a notch that opened with no
cause, a timer that restarted every few seconds, and widgets that were destroyed and
rebuilt by unrelated state changes. They are structural on purpose - the behaviour lives
in QML, and these are the shapes that make it correct.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
ISLAND_DIR = ROOT / "modules/ii/dynamicIsland"
CORE = ISLAND_DIR / "core"
SOURCES = CORE / "sources"
NOTCH = ISLAND_DIR / "styles/notch"
CLIPHIST = ROOT / "services/Cliphist.qml"
AI_SERVICE = ROOT / "services/AiStatusService.qml"


class ClipboardCauseTest(unittest.TestCase):
    """`clipboardUpdated` means "the list was re-read", which the external
    `wl-paste --watch` IPC triggers with no copy involved. Only `entryAdded` is a copy."""

    def setUp(self):
        self.cliphist = CLIPHIST.read_text(encoding="utf-8")
        self.source = (SOURCES / "ClipboardSource.qml").read_text(encoding="utf-8")

    def test_service_exposes_entry_added(self):
        self.assertIn("signal entryAdded(string entry)", self.cliphist)

    def test_island_listens_to_entry_added_and_not_to_list_rereads(self):
        self.assertIn("function onEntryAdded(", self.source)
        self.assertNotIn("onClipboardUpdated", self.source)

    def test_announcement_requires_a_growing_id_and_changed_content(self):
        # A deletion or a wipe never raises the id; re-advertising the same selection
        # (what an unlock does) raises the id but does not change the content.
        self.assertIn("const idGrew = id > root.idWatermark", self.cliphist)
        self.assertIn("if (!idGrew || clean === root.lastAnnounced)", self.cliphist)

    def test_first_read_only_seeds_the_baseline(self):
        self.assertIn("if (firstRead)", self.cliphist)

    def test_baseline_lives_in_the_service(self):
        """It used to be panel-local and seeded inside a 2s race window, so a recreated
        surface announced a stale history entry as if it had just been copied."""
        self.assertIn("property int idWatermark", self.cliphist)
        self.assertIn("property string lastAnnounced", self.cliphist)
        for path in ISLAND_DIR.rglob("*.qml"):
            text = path.read_text(encoding="utf-8")
            with self.subTest(file=path.name):
                self.assertNotIn("lastClipboardItem", text,
                                 "the island must not keep its own clipboard baseline")


class QuietWindowTest(unittest.TestCase):
    """Boot, hot reload and unlock restore state in bulk; none of it is a user action."""

    def test_the_policy_owns_the_quiet_window_and_rearms_on_unlock(self):
        policy = (CORE / "IslandPolicy.qml").read_text(encoding="utf-8")
        self.assertIn("property bool quietWindowActive: true", policy)
        self.assertIn("function onScreenLockedChanged()", policy)

    def test_every_announcement_goes_through_the_gate(self):
        """`TransientSource.trigger()` is the only way an announcement reaches the
        island, so the gate lives there once instead of in every activity."""
        base = (SOURCES / "TransientSource.qml").read_text(encoding="utf-8")
        self.assertIn("IslandPolicy.quietWindowActive", base)
        trigger = base.split("function trigger(", 1)[1].split("\n    }", 1)[0]
        self.assertIn("return false", trigger)

    def test_announcements_are_transient_sources(self):
        """A state-derived event that used a continuous source would bypass the gate."""
        for activity in ("Battery", "Wifi", "Bluetooth", "KeyboardLayout", "Clipboard",
                         "Workspace"):
            text = (SOURCES / f"{activity}Source.qml").read_text(encoding="utf-8")
            with self.subTest(activity=activity):
                self.assertIn("TransientSource {", text)

    def test_battery_does_not_announce_preexisting_state_at_startup(self):
        battery = (SOURCES / "BatterySource.qml").read_text(encoding="utf-8")
        completed = battery.split("Component.onCompleted:", 1)[1]
        self.assertNotIn("trigger", completed,
                         "being already plugged in is a state, not an event")
        self.assertNotIn("announce", completed)


class NoRebuildOnUnrelatedChangeTest(unittest.TestCase):
    """The panel rebuilt every widget whenever any dependency of its model changed - the
    agent list, progress jobs, a config read. The engine's equivalent invariant is that
    a source appearing or leaving is the *only* thing that changes what is loaded."""

    def test_the_surface_loads_by_activity_and_not_by_state(self):
        content = (NOTCH / "NotchContent.qml").read_text(encoding="utf-8")
        self.assertIn("source: content.sourcePath", content)
        self.assertIn("IslandRegistry.legacyContentFor(content.activityId)", content)

    def test_the_agent_list_is_not_rebuilt_on_a_tick(self):
        service = AI_SERVICE.read_text(encoding="utf-8")
        self.assertIn("if (signature === root._agentsSignature)", service)


class WorkspaceSourceTest(unittest.TestCase):
    def setUp(self):
        self.source = (SOURCES / "WorkspaceSource.qml").read_text(encoding="utf-8")

    def test_workspace_comes_from_the_focused_workspace(self):
        """Deriving it from the island window's monitor turned a monitor focus change
        into a workspace change."""
        self.assertIn("Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1",
                      self.source)

    def test_previous_workspace_is_state_not_a_binding(self):
        """A binding on the current id kept both in lockstep, so the handler compared
        the new value against itself and never fired."""
        self.assertIn("property int previousId: -1", self.source)
        self.assertNotIn("property int previousId: source.currentId", self.source)


def duplicate_behaviors(text):
    """Every property animated twice *within the same item*.

    Two `Behavior on <prop>` blocks are only a conflict when they share an owner, so the
    check tracks the enclosing block: the container's height had two, while a container
    and a child loader both animating width is perfectly legal.
    """
    owners = {}
    stack = []
    duplicates = []
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped.startswith("//"):
            match = re.match(r"Behavior on ([A-Za-z.]+)", stripped)
            if match:
                key = (tuple(stack), match.group(1))
                if key in owners:
                    duplicates.append((match.group(1), owners[key], number))
                else:
                    owners[key] = number
        for char in line.split("//")[0]:
            if char == "{":
                stack.append(number)
            elif char == "}" and stack:
                stack.pop()
    return duplicates


class SingleInterceptorTest(unittest.TestCase):
    def test_no_property_is_animated_twice_in_the_same_item(self):
        """Two `Behavior on height` blocks on the container logged "Attempting to set
        another interceptor ... property height - unsupported" on every reload, and the
        second one silently did nothing."""
        for path in ISLAND_DIR.rglob("*.qml"):
            with self.subTest(file=path.relative_to(ROOT).as_posix()):
                found = duplicate_behaviors(path.read_text(encoding="utf-8"))
                self.assertEqual(found, [], f"duplicate Behavior blocks: {found}")


class NoDeadLoggingTest(unittest.TestCase):
    def test_module_has_no_console_log(self):
        """Quickshell does not persist debug-level messages, so these were pure cost in
        hot paths - one of them inside the widget-list binding itself."""
        offenders = []
        for path in ISLAND_DIR.rglob("*.qml"):
            text = path.read_text(encoding="utf-8")
            if "console.log" in text:
                offenders.append(path.relative_to(ROOT).as_posix())
        self.assertEqual(offenders, [])


class AiStatusStabilityTest(unittest.TestCase):
    def setUp(self):
        self.service = AI_SERVICE.read_text(encoding="utf-8")

    def test_agent_list_is_only_reassigned_when_it_changes(self):
        self.assertIn("if (signature === root._agentsSignature)", self.service)

    def test_runtime_is_not_part_of_the_signature(self):
        signature_fn = self.service.split("function agentsSignature(", 1)[1][:400]
        for volatile in ("runtime", "tokensIn", "tokensOut"):
            self.assertNotIn(volatile, signature_fn,
                             f"{volatile} changes constantly and would rebuild the list")

    def test_the_clock_ticks_without_rebuilding_the_list(self):
        ticker = self.service.split("id: ticker", 1)[1].split("\n    }", 1)[0]
        self.assertIn("nowSeconds", ticker)
        self.assertNotIn("updateCombinedAgents", ticker,
                         "the 1s tick must not rebuild the agent list")


class EngineStructureTest(unittest.TestCase):
    """Invariants of the new engine (core/), which the legacy panel will be ported onto."""

    CORE = ROOT / "modules/ii/dynamicIsland/core"

    def test_every_registry_activity_has_a_descriptor_shape(self):
        registry = (self.CORE / "IslandRegistry.qml").read_text(encoding="utf-8")
        ids = re.findall(r'^\s*id: "([a-zA-Z]+)",$', registry, re.MULTILINE)
        self.assertGreater(len(ids), 10, "the registry should describe every activity")
        self.assertEqual(len(ids), len(set(ids)), "duplicate activity id in the registry")
        for field in ("tier:", "preferredSide:", "canDetach:", "settleMs:", "content:"):
            self.assertEqual(registry.count(field), len(ids),
                             f"every descriptor needs exactly one {field}")

    def test_sources_declare_child_objects_as_named_properties(self):
        """`IslandSource` derives from QtObject, which has no default property, so a bare
        `Connections {}` or `Timer {}` inside a source fails to compile with "Cannot
        assign to non-existent default property" - and it takes the whole island's type
        chain down with it."""
        for path in (self.CORE / "sources").glob("*.qml"):
            text = path.read_text(encoding="utf-8")
            for line in text.splitlines():
                stripped = line.strip()
                for child in ("Connections {", "Timer {", "Process {"):
                    if stripped.startswith(child):
                        self.fail(f"{path.name}: `{child}` must be assigned to a named "
                                  f"property (e.g. `property Timer _ttl: Timer {{`)")

    def test_the_settle_clock_is_not_a_binding(self):
        """`Date.now()` cannot be a binding dependency, so a `readonly property` version
        stayed true forever and left a 120ms timer running for the whole session."""
        controller = (self.CORE / "IslandController.qml").read_text(encoding="utf-8")
        self.assertIn("function anySettling()", controller)
        self.assertNotIn("property bool anySettling", controller)
        self.assertIn("settleTimer.stop()", controller)

    def test_continuous_sources_do_not_overwrite_a_bound_payload(self):
        """An imperative assignment to `payload` destroys a subclass's binding to its
        service and freezes the value at whatever it held on arrival."""
        base = (self.CORE / "sources/IslandSource.qml").read_text(encoding="utf-8")
        self.assertIn("if (data !== undefined)", base)
        continuous = (self.CORE / "sources/ContinuousSource.qml").read_text(encoding="utf-8")
        self.assertIn("source.begin();", continuous)
        self.assertNotIn("source.begin(source.payload)", continuous)

    def test_gating_reads_the_policy_rather_than_the_config(self):
        entry = (ROOT / "modules/ii/dynamicIsland/DynamicIsland.qml").read_text(encoding="utf-8")
        self.assertIn("IslandPolicy.enabled", entry)
        self.assertNotIn("floatingNotch.enable", entry)


class SourceCoverageTest(unittest.TestCase):
    """Every activity needs a source, and every source needs a descriptor - a mismatch
    means an activity that can never appear, or one with no shape to draw."""

    CORE = ROOT / "modules/ii/dynamicIsland/core"

    def setUp(self):
        registry = (self.CORE / "IslandRegistry.qml").read_text(encoding="utf-8")
        self.registry_ids = set(re.findall(r'^\s*id: "([a-zA-Z]+)",$', registry, re.MULTILINE))
        self.sources = {}
        for path in (self.CORE / "sources").glob("*.qml"):
            match = re.search(r'^\s*activityId: "([a-zA-Z]+)"', path.read_text(encoding="utf-8"),
                              re.MULTILINE)
            if match:
                self.sources[match.group(1)] = path.name

    def test_every_activity_has_a_source_except_the_clock(self):
        # The clock is not an event: nothing *happens* to make a clock, it is simply what
        # the centre shows when nothing else needs it, so the controller synthesises it.
        missing = self.registry_ids - set(self.sources) - {"clock"}
        self.assertEqual(missing, set(), f"activities with no source: {sorted(missing)}")

    def test_no_source_reports_an_unknown_activity(self):
        unknown = set(self.sources) - self.registry_ids
        self.assertEqual(unknown, set(),
                         f"sources with no descriptor: {sorted(unknown)}")

    def test_every_source_is_wired_into_the_set(self):
        wiring = (self.CORE / "sources/IslandSources.qml").read_text(encoding="utf-8")
        listed = wiring.split("readonly property list<QtObject> all: [", 1)[1].split("]", 1)[0]
        for activity_id, filename in self.sources.items():
            type_name = filename[:-4]
            self.assertIn(type_name, wiring, f"{type_name} is never instantiated")
            prop = re.search(rf"readonly property {type_name} (\w+):", wiring)
            self.assertIsNotNone(prop, f"{type_name} has no named property")
            self.assertIn(prop.group(1), listed,
                          f"{type_name} is instantiated but missing from `all`")


class GatingTest(unittest.TestCase):
    """Ownership is one question with one answer; nine hand-written copies of it had
    already drifted apart."""

    CONSUMERS = (
        "panelFamilies/IllogicalImpulseFamily.qml",
        "modules/ii/onScreenDisplay/OnScreenDisplay.qml",
        "modules/ii/topLayer/TopLayerPanel.qml",
        "modules/ii/bar/core/BarLayout.qml",
        "modules/ii/dynamicIsland/DynamicIsland.qml",
    )

    def test_consumers_ask_the_policy_instead_of_the_config(self):
        for relative in self.CONSUMERS:
            text = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(file=relative):
                self.assertIn("IslandPolicy", text)
                self.assertNotIn("floatingNotch.enable", text)
                self.assertNotIn("floatingNotch.centerInBar", text)

    def test_the_policy_does_not_depend_on_what_depends_on_it(self):
        """GlobalStates and ShellModePolicy are read *by* IslandPolicy, so they must not
        read it back - a singleton cycle fails silently and leaves the island unloaded."""
        for relative in ("GlobalStates.qml", "modules/common/ShellModePolicy.qml"):
            text = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(file=relative):
                self.assertNotIn("IslandPolicy", text)


class CenterInBarStyleTest(unittest.TestCase):
    """The island in the bar centre needs a bar that leaves it a centre to sit in."""

    def test_only_hug_and_the_island_bar_style_are_allowed(self):
        policy = (ROOT / "modules/common/ShellModePolicy.qml").read_text(encoding="utf-8")
        self.assertIn("centerInBarStyles: [0, 3]", policy,
                      "Hug (0) and Dynamic Island (3) only; Float and Rect are refused")
        self.assertIn("centerInBarStyleSupported", policy)

    def test_the_runtime_refuses_an_unsupported_combination(self):
        island = (ROOT / "modules/ii/dynamicIsland/core/IslandPolicy.qml").read_text(encoding="utf-8")
        self.assertIn("barStyleSupportsCenterInBar", island)

    def test_settings_blocks_both_directions(self):
        bar = (ROOT / "modules/settings/configs/widgets/BarAppearanceConfig.qml").read_text(encoding="utf-8")
        self.assertIn("ShellModePolicy.centerInBarActive", bar,
                      "Float and Rect must be disabled while the island is in the bar")
        island = (ROOT / "modules/settings/configs/DynamicIslandConfig.qml").read_text(encoding="utf-8")
        self.assertIn("ShellModePolicy.centerInBarStyleSupported", island,
                      "the switch must be refused on an unsupported bar style")

    def test_the_bar_reserves_the_island_width_rather_than_animating_it(self):
        """Two animations chasing each other is what made the pill lag behind its own
        contents; the bar follows the island's live width instead."""
        style = (ROOT / "modules/ii/bar/styles/DynamicIslandStyle.qml").read_text(encoding="utf-8")
        self.assertIn("islandInBarCenter", style)
        self.assertIn("IslandGeometry.centerWidth", style)
        self.assertIn("enabled: root.modeResizing && !root.islandInBarCenter", style)

    def test_nothing_may_stretch_in_the_combined_row(self):
        """Layout.fillWidth defaults to true for a Layout inside a Layout, which let the
        sections absorb the row's slack and made the right margin 22px wider."""
        style = (ROOT / "modules/ii/bar/styles/DynamicIslandStyle.qml").read_text(encoding="utf-8")
        # The two spacers start with the same expression but continue with ` && (`, so
        # match the sections' whole line.
        sections = re.findall(r"Layout\.fillWidth: !root\.islandInBarCenter$", style,
                              re.MULTILINE)
        self.assertEqual(len(sections), 3,
                         "all three sections must stop stretching in combined mode")
        self.assertIn("width: root.islandInBarCenter ? implicitWidth", style,
                      "the row must be exactly its content, so there is no slack to give")


class NotchSurfaceTest(unittest.TestCase):
    """The engine-driven notch, which replaces DynamicIslandPanel."""

    NOTCH = ROOT / "modules/ii/dynamicIsland/styles/notch"

    def setUp(self):
        self.island = (self.NOTCH / "NotchIsland.qml").read_text(encoding="utf-8")
        self.content = (self.NOTCH / "NotchContent.qml").read_text(encoding="utf-8")

    def test_the_surface_is_driven_by_the_controller(self):
        self.assertIn("IslandController", self.island)
        self.assertIn("maxIslands: 1", self.island,
                      "the notch is a single slot; the rest is the pager")

    def test_expanding_rebinds_rather_than_reloads(self):
        """The widgets render both states from `isExpanded`; reloading them on expand
        would restart their internal state, the album art machine being the costly one."""
        self.assertIn('property: "isExpanded"', self.content)
        loader = self.content.split("Loader {", 1)[1].split("}", 1)[0]
        self.assertNotIn("presentation", loader,
                         "the loader's source must follow the activity, not the state")

    def test_only_search_takes_the_keyboard(self):
        """A notch holding focus while merely showing a track swallows every shortcut."""
        self.assertIn("root.searchActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None",
                      self.island)

    def test_the_window_stays_click_through(self):
        """Its window spans the screen, so anything but the shape itself must not take
        input."""
        self.assertIn("mask: Region {", self.island)
        self.assertIn("edgeSensor", self.island)

    def test_a_drag_keeps_the_island_visible(self):
        """No hover signal arrives during a drag, so a drop target that hides as the
        pointer approaches cannot be hit."""
        self.assertIn("dragHovering", self.island)
        hidden = self.island.split("readonly property bool hidden: {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("dragHovering", hidden)

    def test_legacy_widgets_are_resolved_from_the_shell_root(self):
        """A relative `source` resolves against whichever file holds the Loader, and the
        surface lives two directories away from the widgets."""
        registry = (ROOT / "modules/ii/dynamicIsland/core/IslandRegistry.qml").read_text(encoding="utf-8")
        self.assertIn("Quickshell.shellPath(\"modules/ii/dynamicIsland/widgets/\"", registry)
        self.assertNotIn('legacyContent: "../widgets/', registry)

    def test_the_panel_and_its_switch_are_gone(self):
        """One island, one surface. While both existed the switch was the honest way to
        ship a partial port; keeping it afterwards would just be a second code path
        nobody exercises."""
        self.assertFalse((ISLAND_DIR / "DynamicIslandPanel.qml").exists(),
                         "the legacy panel must be deleted, not left unreferenced")
        entry = (ISLAND_DIR / "DynamicIsland.qml").read_text(encoding="utf-8")
        self.assertIn("NotchIsland", entry)
        for path in ISLAND_DIR.rglob("*.qml"):
            with self.subTest(file=path.name):
                self.assertNotIn("useEngineNotch", path.read_text(encoding="utf-8"))

    def test_the_surface_provides_what_the_widgets_reach_for(self):
        """Some widgets walk up their parent chain for state the panel used to hold; a
        missing property there is silent - the widget just renders empty."""
        content = (NOTCH / "NotchContent.qml").read_text(encoding="utf-8")
        for expected in ("wifiSsid", "workspaceWidgetRef"):
            self.assertIn(expected, content)

    def test_search_keeps_the_running_activities_on_screen(self):
        """The strip along the bottom of search is the controller's overflow, not a
        second hand-written list - which is how the panel's two lists drifted apart."""
        island = (NOTCH / "NotchIsland.qml").read_text(encoding="utf-8")
        self.assertIn("searchStripIds: root.searchActive ? controller.overflowIds", island)


class NoExtraCompactTest(unittest.TestCase):
    """Extra Compact scaled the whole notch to fake a smaller island. The engine sizes
    the surface from the activity it is showing, so the option had nothing left to
    mean and the user asked for it gone."""

    def test_the_option_is_gone_from_the_schema_and_the_ui(self):
        config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        self.assertNotIn("property bool extraCompact", config)
        settings = (ROOT / "modules/settings/configs/DynamicIslandConfig.qml").read_text(encoding="utf-8")
        self.assertNotIn("extraCompact", settings)

    def test_nothing_in_the_island_still_reads_it(self):
        for path in ISLAND_DIR.rglob("*.qml"):
            with self.subTest(file=path.name):
                self.assertNotIn("extraCompact", path.read_text(encoding="utf-8"))

    def test_the_leftover_key_is_cleaned_up(self):
        """A key removed from the schema but left in the user's file comes back as an
        unknown key in ConfigHealthBanner."""
        config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        self.assertIn("delete raw.bar.floatingNotch.extraCompact", config)


if __name__ == "__main__":
    unittest.main(verbosity=2)
