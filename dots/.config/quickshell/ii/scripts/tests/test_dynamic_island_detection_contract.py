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


if __name__ == "__main__":
    unittest.main(verbosity=2)
