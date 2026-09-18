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
PANEL = ROOT / "modules/ii/dynamicIsland/DynamicIslandPanel.qml"
ISLAND_DIR = ROOT / "modules/ii/dynamicIsland"
CLIPHIST = ROOT / "services/Cliphist.qml"
AI_SERVICE = ROOT / "services/AiStatusService.qml"


class ClipboardCauseTest(unittest.TestCase):
    """`clipboardUpdated` means "the list was re-read", which the external
    `wl-paste --watch` IPC triggers with no copy involved. Only `entryAdded` is a copy."""

    def setUp(self):
        self.cliphist = CLIPHIST.read_text(encoding="utf-8")
        self.panel = PANEL.read_text(encoding="utf-8")

    def test_service_exposes_entry_added(self):
        self.assertIn("signal entryAdded(string entry)", self.cliphist)

    def test_island_listens_to_entry_added_and_not_to_list_rereads(self):
        self.assertIn("function onEntryAdded(", self.panel)
        self.assertNotIn("function onClipboardUpdated(", self.panel)

    def test_announcement_requires_a_growing_id_and_changed_content(self):
        # A deletion or a wipe never raises the id; re-advertising the same selection
        # (what an unlock does) raises the id but does not change the content.
        self.assertIn("const idGrew = id > root.idWatermark", self.cliphist)
        self.assertIn("if (!idGrew || clean === root.lastAnnounced)", self.cliphist)

    def test_first_read_only_seeds_the_baseline(self):
        self.assertIn("if (firstRead)", self.cliphist)

    def test_baseline_lives_in_the_service(self):
        """It used to be panel-local and seeded inside a 2s race window, so a recreated
        panel announced a stale history entry as if it had just been copied."""
        self.assertIn("property int idWatermark", self.cliphist)
        self.assertIn("property string lastAnnounced", self.cliphist)
        self.assertNotIn("isStartup", self.panel)
        self.assertNotIn("lastClipboardItem", self.panel)


class QuietWindowTest(unittest.TestCase):
    """Boot, hot reload and unlock restore state in bulk; none of it is a user action."""

    def setUp(self):
        self.panel = PANEL.read_text(encoding="utf-8")

    def test_quiet_window_exists_and_rearms_on_unlock(self):
        self.assertIn("property bool quietWindowActive: true", self.panel)
        self.assertIn("function onScreenLockedChanged()", self.panel)

    def test_state_derived_triggers_respect_it(self):
        for trigger in ("showBatteryNotch", "onWifiStatusChanged", "onDeviceConnected",
                        "onActiveWsIdChanged", "onCurrentLayoutNameChanged"):
            body = self.panel.split(trigger, 1)[1][:700]
            self.assertIn("quietWindowActive", body,
                          f"{trigger} can fire while the shell is still restoring state")

    def test_battery_does_not_announce_preexisting_state_at_startup(self):
        completed = self.panel.split("Component.onCompleted:", 1)[1].split("\n    }", 1)[0]
        self.assertNotIn("batteryNotifActive", completed,
                         "being already plugged in is a state, not an event")


class StableModelTest(unittest.TestCase):
    """`getWidgetDetails()` returns a fresh object per call, so a model built from it
    handed the Repeater a new identity on every re-evaluation and rebuilt every widget."""

    def setUp(self):
        self.panel = PANEL.read_text(encoding="utf-8")

    def test_arbitration_produces_type_strings(self):
        types_block = self.panel.split("readonly property var activeWidgetTypes: {", 1)[1]
        types_block = types_block.split("// Geometry for the current types", 1)[0]
        self.assertNotIn("getWidgetDetails", types_block)
        self.assertIn('list.push("media")', types_block)

    def test_repeater_binds_to_the_cached_arrays(self):
        self.assertIn("root.stableWidgetTypes : root.stableLeadWidgetType", self.panel)
        model_lines = [line for line in self.panel.splitlines()
                       if re.match(r"\s*model:", line) and "activeWidgetsList" in line]
        self.assertEqual(model_lines, [],
                         "a Repeater model must never be the freshly built detail list")

    def test_cached_arrays_are_seeded_at_startup(self):
        self.assertIn("root.refreshStableWidgetTypes();", self.panel)


class WorkspaceSourceTest(unittest.TestCase):
    def setUp(self):
        self.panel = PANEL.read_text(encoding="utf-8")

    def test_workspace_comes_from_the_focused_workspace(self):
        """Deriving it from the island window's monitor turned a monitor focus change
        into a workspace change."""
        self.assertIn("Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1",
                      self.panel)

    def test_previous_workspace_is_state_not_a_binding(self):
        """`property int prevWsId: activeWsId` kept both in lockstep, so the handler
        compared the new value against itself and never fired."""
        self.assertNotIn("property int prevWsId: activeWsId", self.panel)
        self.assertIn("property int prevWsId: -1", self.panel)


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


if __name__ == "__main__":
    unittest.main(verbosity=2)
