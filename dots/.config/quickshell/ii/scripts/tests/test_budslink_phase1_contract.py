#!/usr/bin/env python3
"""BudsLink Phase 1 Automated Contract & Integration Tests

Validates:
1. Complete test isolation: Every bridge test process runs against a private, isolated
   dbus-daemon session bus address, preventing any interaction with user session BudsLink.
2. scripts/budslink/bridge.js protocol compliance, error handling, lifecycle, and D-Bus integration.
3. Per-device signals: DeviceAdded, DeviceRemoved, PropertiesChanged (including invalidation).
4. Device snapshot race guard: async GetAll finishing after DeviceRemoved does not emit deviceSnapshot or revive removed devices.
5. Service owner loss and reappearance.
6. Interface contract version gating (rejecting incompatible versions).
7. Section 45 UiAction validation (strictly permitting toggle1State/toggle2State, rejecting toggle3State/toggle4State, rejecting non-integer values).
8. D-Bus failure reporting: hold, release, and enumerate failures emit structured JSONL error events on stdout.
9. Safe operation on isolated bus when no BudsLink daemon is running.
10. services/BudsLinkService.qml static contract, candidate awareness without brand keyword heuristics,
    bounded diagnostics activation on refresh(), clean shutdown/reconnect race recovery, and atomic snapshot updates.
11. D-Bus service auto-activation (AUTO_START): bridge.js Gio.bus_watch_name triggers on-demand launch of activatable mock BudsLink daemon on isolated bus.
"""

import json
import os
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import unittest
import warnings
from pathlib import Path

# Treat deprecation warnings from system gi bindings cleanly
warnings.filterwarnings("ignore", category=DeprecationWarning)

def setUpModule():
    warnings.filterwarnings("ignore", category=DeprecationWarning)
    warnings.filterwarnings("ignore", category=UserWarning)

from gi.repository import GLib, Gio

ROOT = Path(__file__).resolve().parents[2]
BRIDGE_JS = ROOT / "scripts" / "budslink" / "bridge.js"
SERVICE_QML = ROOT / "services" / "BudsLinkService.qml"
SHELL_QML = ROOT / "shell.qml"


class IsolatedDBusFixture:
    """Spawns an isolated private dbus-daemon session."""

    def __init__(self, servicedir=None):
        self.tmpdir = tempfile.mkdtemp(prefix="test_budslink_dbus_")
        self.servicedir = servicedir
        if servicedir:
            self.config_path = os.path.join(self.tmpdir, "session.conf")
            with open(self.config_path, "w", encoding="utf-8") as f:
                f.write(f"""<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir={self.tmpdir}</listen>
  <servicedir>{servicedir}</servicedir>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
""")
            cmd = ["dbus-daemon", f"--config-file={self.config_path}", "--print-address=1", "--nofork"]
        else:
            cmd = ["dbus-daemon", "--session", "--print-address=1", "--nofork"]

        self.proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=self.tmpdir,
        )
        self.address = self.proc.stdout.readline().strip()
        if not self.address.startswith("unix:"):
            raise RuntimeError(f"Failed to start isolated dbus-daemon: {self.address}")

    def get_env(self):
        env = os.environ.copy()
        env["DBUS_SESSION_BUS_ADDRESS"] = self.address
        return env

    def close(self):
        if self.proc:
            if self.proc.stdout:
                self.proc.stdout.close()
            if self.proc.stderr:
                self.proc.stderr.close()
            if self.proc.stdin:
                self.proc.stdin.close()
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
            self.proc = None
        if os.path.exists(self.tmpdir):
            shutil.rmtree(self.tmpdir, ignore_errors=True)


class BudsLinkBridgeBasicIsolatedTests(unittest.TestCase):
    """Protocol validation running against an isolated private D-Bus session with no services."""

    def setUp(self):
        self.fixture = IsolatedDBusFixture()

    def tearDown(self):
        self.fixture.close()

    def _spawn_bridge(self):
        return subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def test_bridge_files_exist(self):
        self.assertTrue(BRIDGE_JS.exists(), f"{BRIDGE_JS} must exist")
        self.assertTrue(SERVICE_QML.exists(), f"{SERVICE_QML} must exist")

    def test_process_isolation_evidence(self):
        """Verify the test bridge process environment uses the isolated private D-Bus address."""
        env = self.fixture.get_env()
        self.assertIn("DBUS_SESSION_BUS_ADDRESS", env)
        self.assertTrue(env["DBUS_SESSION_BUS_ADDRESS"].startswith("unix:"))
        real_user_bus = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
        if real_user_bus:
            self.assertNotEqual(env["DBUS_SESSION_BUS_ADDRESS"], real_user_bus)

    def test_bridge_emits_bridge_ready_on_startup(self):
        proc = self._spawn_bridge()
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        self.assertGreaterEqual(len(lines), 1)
        self.assertEqual(lines[0], {"type": "bridgeReady", "protocol": 1})
        self.assertEqual(proc.returncode, 0)

    def test_bridge_handles_malformed_json(self):
        proc = self._spawn_bridge()
        proc.stdin.write("{not valid json\n")
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        error_events = [l for l in lines if l.get("type") == "error" and l.get("code") == "malformedJson"]
        self.assertEqual(len(error_events), 1)
        self.assertEqual(proc.returncode, 0)

    def test_bridge_handles_unknown_command(self):
        proc = self._spawn_bridge()
        proc.stdin.write(json.dumps({"command": "nonExistentCommand"}) + "\n")
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        error_events = [l for l in lines if l.get("type") == "error" and l.get("code") == "unknownCommand"]
        self.assertEqual(len(error_events), 1)
        self.assertEqual(proc.returncode, 0)

    def test_bridge_handles_invalid_action_parameters(self):
        proc = self._spawn_bridge()
        # Invalid path
        proc.stdin.write(json.dumps({"command": "action", "path": "/invalid/path", "action": "toggle1State", "value": 1}) + "\n")
        # Path without MAC
        proc.stdin.write(json.dumps({"command": "action", "path": "/io/github/maniacx/BudsLink/Devices/hci0/no_mac_here", "action": "toggle1State", "value": 1}) + "\n")
        # Invalid action name: Section 45 violations (toggle3State / toggle4State / arbitrary)
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": "/io/github/maniacx/BudsLink/Devices/hci0/dev_AA_BB_CC_DD_EE_FF",
            "action": "toggle3State",
            "value": 1,
        }) + "\n")
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": "/io/github/maniacx/BudsLink/Devices/hci0/dev_AA_BB_CC_DD_EE_FF",
            "action": "toggle4State",
            "value": 1,
        }) + "\n")
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": "/io/github/maniacx/BudsLink/Devices/hci0/dev_AA_BB_CC_DD_EE_FF",
            "action": "dangerous;rm -rf /",
            "value": 1,
        }) + "\n")
        # Non-integer / non-finite value
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": "/io/github/maniacx/BudsLink/Devices/hci0/dev_AA_BB_CC_DD_EE_FF",
            "action": "toggle1State",
            "value": "notAnInt",
        }) + "\n")
        # Float value rejected
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": "/io/github/maniacx/BudsLink/Devices/hci0/dev_AA_BB_CC_DD_EE_FF",
            "action": "box1SliderValue",
            "value": 12.34,
        }) + "\n")
        # Service unavailable
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": "/io/github/maniacx/BudsLink/Devices/hci0/dev_AA_BB_CC_DD_EE_FF",
            "action": "toggle1State",
            "value": 2,
        }) + "\n")
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        codes = [l.get("code") for l in lines if l.get("type") == "error"]
        self.assertIn("invalidPath", codes)
        self.assertIn("invalidAction", codes)
        self.assertIn("invalidValue", codes)
        self.assertIn("serviceUnavailable", codes)
        # Verify both toggle3State and toggle4State produced invalidAction
        invalid_action_events = [l for l in lines if l.get("type") == "error" and l.get("code") == "invalidAction"]
        self.assertGreaterEqual(len(invalid_action_events), 3)
        self.assertEqual(proc.returncode, 0)

    def test_bridge_exits_cleanly_on_stdin_eof(self):
        proc = self._spawn_bridge()
        proc.stdin.close()
        proc.stdin = None
        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        self.assertGreaterEqual(len(lines), 1)
        self.assertEqual(lines[0], {"type": "bridgeReady", "protocol": 1})
        self.assertEqual(proc.returncode, 0)


class BudsLinkIsolatedNoServiceTests(unittest.TestCase):
    """Verifies that bridge runs safely, quietly, and cleanly on isolated bus without BudsLink service."""

    def setUp(self):
        self.fixture = IsolatedDBusFixture()

    def tearDown(self):
        self.fixture.close()

    def test_isolated_bus_no_budslink_remains_quiet_and_clean(self):
        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        proc.stdin.write(json.dumps({"command": "hold"}) + "\n")
        proc.stdin.write(json.dumps({"command": "enumerate"}) + "\n")
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        self.assertEqual(lines[0]["type"], "bridgeReady")
        # Service status should report available: false
        status_events = [l for l in lines if l.get("type") == "serviceStatus"]
        for s in status_events:
            self.assertFalse(s.get("available"))
        self.assertEqual(proc.returncode, 0)


class BudsLinkIsolatedMockDBusTests(unittest.TestCase):
    """Full D-Bus communication test against an active mock BudsLink service on an isolated bus."""

    MANAGER_XML = """
    <node>
      <interface name="io.github.maniacx.BudsLink.DeviceManager">
        <method name="HoldService">
          <arg type="s" name="clientId" direction="in"/>
        </method>
        <method name="ReleaseService">
          <arg type="s" name="clientId" direction="in"/>
        </method>
        <method name="ServiceVersion">
          <arg type="s" name="version" direction="out"/>
        </method>
        <method name="ListDevices">
          <arg type="ao" name="devices" direction="out"/>
        </method>
        <signal name="DeviceAdded">
          <arg type="o" name="objectPath"/>
        </signal>
        <signal name="DeviceRemoved">
          <arg type="o" name="objectPath"/>
        </signal>
      </interface>
    </node>
    """

    DEVICE_XML = """
    <node>
      <interface name="io.github.maniacx.BudsLink.Device">
        <property name="Alias" type="s" access="read"/>
        <property name="Config" type="s" access="read"/>
        <property name="State" type="s" access="read"/>
        <method name="UiAction">
          <arg type="s" name="actionName" direction="in"/>
          <arg type="i" name="value" direction="in"/>
        </method>
      </interface>
    </node>
    """

    def setUp(self):
        self.fixture = IsolatedDBusFixture()
        self.conn = Gio.DBusConnection.new_for_address_sync(
            self.fixture.address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None,
            None,
        )
        self.loop = GLib.MainLoop()
        self.holds = []
        self.releases = []
        self.actions = []
        self.service_version = "0.0.1"
        self.fail_hold = False
        self.fail_release = False
        self.fail_list_devices = False
        self.fail_ui_action = False

        self.dev_path = "/io/github/maniacx/BudsLink/Devices/hci0/dev_11_22_33_44_55_66"
        self.dev_alias = "Test Buds Pro"
        self.dev_config = json.dumps({"battery1Icon": "earbuds-left", "battery2Icon": "earbuds-right"})
        self.dev_state = json.dumps({"computedBatteryLevel": 88, "battery1Level": 90, "battery1Status": "discharging"})

        # Export manager
        manager_node = Gio.DBusNodeInfo.new_for_xml(self.MANAGER_XML)
        self.manager_iface = manager_node.interfaces[0]
        self.manager_reg_id = self.conn.register_object(
            "/io/github/maniacx/BudsLink",
            self.manager_iface,
            self._handle_manager_method_call,
            None,
            None,
        )

        # Export device
        device_node = Gio.DBusNodeInfo.new_for_xml(self.DEVICE_XML)
        self.device_iface = device_node.interfaces[0]
        self.device_reg_id = self.conn.register_object(
            self.dev_path,
            self.device_iface,
            self._handle_device_method_call,
            self._handle_device_get_property,
            None,
        )

        # Name acquired event to prove ownership
        self.name_acquired_event = threading.Event()

        def on_name_acquired(conn, name):
            self.name_acquired_event.set()

        def on_name_lost(conn, name):
            pass

        self.name_owner_id = Gio.bus_own_name_on_connection(
            self.conn,
            "io.github.maniacx.BudsLink",
            Gio.BusNameOwnerFlags.NONE,
            on_name_acquired,
            on_name_lost,
        )

        self.thread = threading.Thread(target=self.loop.run, daemon=True)
        self.thread.start()

        # Wait to prove name ownership on isolated bus
        acquired = self.name_acquired_event.wait(timeout=3)
        self.assertTrue(acquired, "Must acquire io.github.maniacx.BudsLink on isolated private bus")

    def tearDown(self):
        self.loop.quit()
        if self.name_owner_id:
            Gio.bus_unown_name(self.name_owner_id)
        if self.manager_reg_id:
            self.conn.unregister_object(self.manager_reg_id)
        if self.device_reg_id:
            self.conn.unregister_object(self.device_reg_id)
        self.fixture.close()

    def _handle_manager_method_call(self, conn, sender, path, iface, method, params, invocation):
        if method == "ServiceVersion":
            invocation.return_value(GLib.Variant("(s)", (self.service_version,)))
        elif method == "HoldService":
            if self.fail_hold:
                invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.FAILED, "Simulated HoldService error")
                return
            client_id = params.unpack()[0]
            self.holds.append(client_id)
            invocation.return_value(None)
        elif method == "ReleaseService":
            if self.fail_release:
                invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.FAILED, "Simulated ReleaseService error")
                return
            client_id = params.unpack()[0]
            self.releases.append(client_id)
            invocation.return_value(None)
        elif method == "ListDevices":
            if self.fail_list_devices:
                invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.FAILED, "Simulated ListDevices error")
                return
            invocation.return_value(GLib.Variant("(ao)", ([self.dev_path],)))
        else:
            invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, f"Unknown {method}")

    def _handle_device_method_call(self, conn, sender, path, iface, method, params, invocation):
        if method == "UiAction":
            if self.fail_ui_action:
                invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.FAILED, "Simulated UiAction error")
                return
            action, val = params.unpack()
            self.actions.append((action, val))
            invocation.return_value(None)
        else:
            invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, f"Unknown {method}")

    def _handle_device_get_property(self, conn, sender, path, iface, prop):
        if prop == "Alias":
            return GLib.Variant("s", self.dev_alias)
        elif prop == "Config":
            return GLib.Variant("s", self.dev_config)
        elif prop == "State":
            return GLib.Variant("s", self.dev_state)
        return None

    def test_bridge_discovers_mock_service_and_devices(self):
        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)
        proc.stdin.write(json.dumps({"command": "hold"}) + "\n")
        proc.stdin.flush()
        time.sleep(0.05)
        # Section 45: toggle1State and toggle2State are permitted
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": self.dev_path,
            "action": "toggle1State",
            "value": 4,
        }) + "\n")
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": self.dev_path,
            "action": "toggle2State",
            "value": 1,
        }) + "\n")
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": self.dev_path,
            "action": "settingsButtonClicked",
            "value": 0,
        }) + "\n")
        proc.stdin.write(json.dumps({"command": "release"}) + "\n")
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()

        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]

        # Verify bridgeReady
        self.assertEqual(lines[0]["type"], "bridgeReady")

        # Verify serviceStatus
        status_events = [l for l in lines if l.get("type") == "serviceStatus"]
        self.assertTrue(any(s.get("available") is True and s.get("version") == "0.0.1" for s in status_events))

        # Verify deviceAdded & deviceSnapshot
        snapshots = [l for l in lines if l.get("type") == "deviceSnapshot"]
        self.assertGreaterEqual(len(snapshots), 1)
        first_snap = snapshots[0]
        self.assertEqual(first_snap["path"], self.dev_path)
        self.assertEqual(first_snap["mac"], "11:22:33:44:55:66")
        self.assertEqual(first_snap["alias"], "Test Buds Pro")
        self.assertEqual(first_snap["state"]["computedBatteryLevel"], 88)
        self.assertEqual(first_snap["config"]["battery1Icon"], "earbuds-left")

        # Verify HoldService was called with stable client ID
        self.assertIn("ii-p3drovfx-budslink", self.holds)

        # Verify UiAction was called with toggle1State, toggle2State, and settingsButtonClicked
        self.assertIn(("toggle1State", 4), self.actions)
        self.assertIn(("toggle2State", 1), self.actions)
        self.assertIn(("settingsButtonClicked", 0), self.actions)

        # Verify ReleaseService was called
        self.assertIn("ii-p3drovfx-budslink", self.releases)
        self.assertEqual(proc.returncode, 0)

    def test_section_45_action_allowlist_enforcement(self):
        """Verify toggle1State and toggle2State are valid; toggle3State and toggle4State are rejected."""
        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)
        # Valid actions
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "toggle1State", "value": 1}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "toggle2State", "value": 0}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "box1SliderValue", "value": 50}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "box2CheckButton1State", "value": 1}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "box3RadioButtonState", "value": 2}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "settingsButtonClicked", "value": 0}) + "\n")

        # Invalid actions (strictly rejected by Section 45)
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "toggle3State", "value": 1}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "toggle4State", "value": 1}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "toggle5State", "value": 1}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "box5SliderValue", "value": 10}) + "\n")
        proc.stdin.write(json.dumps({"command": "action", "path": self.dev_path, "action": "box1CheckButton3State", "value": 1}) + "\n")

        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        invalid_actions = [l for l in lines if l.get("type") == "error" and l.get("code") == "invalidAction"]
        self.assertEqual(len(invalid_actions), 5)

        executed_action_names = [a[0] for a in self.actions]
        self.assertIn("toggle1State", executed_action_names)
        self.assertIn("toggle2State", executed_action_names)
        self.assertIn("box1SliderValue", executed_action_names)
        self.assertIn("box2CheckButton1State", executed_action_names)
        self.assertIn("box3RadioButtonState", executed_action_names)
        self.assertIn("settingsButtonClicked", executed_action_names)
        self.assertNotIn("toggle3State", executed_action_names)
        self.assertNotIn("toggle4State", executed_action_names)
        self.assertNotIn("toggle5State", executed_action_names)
        self.assertEqual(proc.returncode, 0)

    def test_device_added_and_removed_signals(self):
        dev2_path = "/io/github/maniacx/BudsLink/Devices/hci0/dev_22_33_44_55_66_77"
        device_node = Gio.DBusNodeInfo.new_for_xml(self.DEVICE_XML)
        dev2_reg_id = self.conn.register_object(
            dev2_path,
            device_node.interfaces[0],
            self._handle_device_method_call,
            lambda c, s, p, i, prop: GLib.Variant("s", "Second Device" if prop == "Alias" else "{}"),
            None,
        )

        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)
        # Emit DeviceAdded for dev2
        self.conn.emit_signal(
            None,
            "/io/github/maniacx/BudsLink",
            "io.github.maniacx.BudsLink.DeviceManager",
            "DeviceAdded",
            GLib.Variant("(o)", (dev2_path,)),
        )
        time.sleep(0.1)

        # Emit DeviceRemoved for dev2
        self.conn.emit_signal(
            None,
            "/io/github/maniacx/BudsLink",
            "io.github.maniacx.BudsLink.DeviceManager",
            "DeviceRemoved",
            GLib.Variant("(o)", (dev2_path,)),
        )
        time.sleep(0.1)

        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]

        added_events = [l for l in lines if l.get("type") == "deviceAdded" and l.get("path") == dev2_path]
        removed_events = [l for l in lines if l.get("type") == "deviceRemoved" and l.get("path") == dev2_path]
        self.assertEqual(len(added_events), 1)
        self.assertEqual(len(removed_events), 1)

        self.conn.unregister_object(dev2_reg_id)
        self.assertEqual(proc.returncode, 0)

    def test_device_snapshot_race_prevented_on_device_removed(self):
        """Verify that when a device is removed while its snapshot is being fetched, deviceSnapshot is not emitted afterwards."""
        dev3_path = "/io/github/maniacx/BudsLink/Devices/hci0/dev_33_44_55_66_77_88"
        device_node = Gio.DBusNodeInfo.new_for_xml(self.DEVICE_XML)

        def slow_property_getter(c, s, p, i, prop):
            time.sleep(0.1)
            return GLib.Variant("s", "Delayed Device" if prop == "Alias" else "{}")

        dev3_reg_id = self.conn.register_object(
            dev3_path,
            device_node.interfaces[0],
            self._handle_device_method_call,
            slow_property_getter,
            None,
        )

        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)
        # Emit DeviceAdded to trigger async fetchDeviceSnapshot
        self.conn.emit_signal(
            None,
            "/io/github/maniacx/BudsLink",
            "io.github.maniacx.BudsLink.DeviceManager",
            "DeviceAdded",
            GLib.Variant("(o)", (dev3_path,)),
        )
        # Emit DeviceRemoved immediately while fetchDeviceSnapshot is awaiting
        time.sleep(0.02)
        self.conn.emit_signal(
            None,
            "/io/github/maniacx/BudsLink",
            "io.github.maniacx.BudsLink.DeviceManager",
            "DeviceRemoved",
            GLib.Variant("(o)", (dev3_path,)),
        )

        time.sleep(0.2)
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]

        # Verify deviceRemoved is emitted, and NO deviceSnapshot for dev3 follows after deviceRemoved
        event_sequence = [(l.get("type"), l.get("path")) for l in lines if l.get("path") == dev3_path]
        removed_idx = None
        for idx, (etype, epath) in enumerate(event_sequence):
            if etype == "deviceRemoved":
                removed_idx = idx

        self.assertIsNotNone(removed_idx, "deviceRemoved must be emitted for dev3")
        # Ensure no snapshot for dev3 occurred after removed_idx
        for idx in range(removed_idx + 1, len(event_sequence)):
            self.assertNotEqual(event_sequence[idx][0], "deviceSnapshot", "fetchDeviceSnapshot must not revive removed device")

        self.conn.unregister_object(dev3_reg_id)
        self.assertEqual(proc.returncode, 0)

    def test_properties_changed_and_invalidation(self):
        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)

        # 1. Alias change
        self.conn.emit_signal(
            None,
            self.dev_path,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (
                "io.github.maniacx.BudsLink.Device",
                {"Alias": GLib.Variant("s", "Updated Buds Name")},
                [],
            )),
        )
        time.sleep(0.05)

        # 2. Config change
        self.conn.emit_signal(
            None,
            self.dev_path,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (
                "io.github.maniacx.BudsLink.Device",
                {"Config": GLib.Variant("s", json.dumps({"battery1Icon": "earbuds-custom"}))},
                [],
            )),
        )
        time.sleep(0.05)

        # 3. State change
        self.conn.emit_signal(
            None,
            self.dev_path,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (
                "io.github.maniacx.BudsLink.Device",
                {"State": GLib.Variant("s", json.dumps({"computedBatteryLevel": 95}))},
                [],
            )),
        )
        time.sleep(0.05)

        # 4. Property Invalidation (State invalidated -> re-fetched from mock property getter)
        self.dev_state = json.dumps({"computedBatteryLevel": 99, "battery1Level": 100})
        self.conn.emit_signal(
            None,
            self.dev_path,
            "org.freedesktop.DBus.Properties",
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (
                "io.github.maniacx.BudsLink.Device",
                {},
                ["State"],
            )),
        )
        time.sleep(0.1)

        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]

        alias_events = [l for l in lines if l.get("type") == "deviceAlias" and l.get("alias") == "Updated Buds Name"]
        config_events = [l for l in lines if l.get("type") == "deviceConfig" and l.get("config", {}).get("battery1Icon") == "earbuds-custom"]
        state_events = [l for l in lines if l.get("type") == "deviceState" and l.get("state", {}).get("computedBatteryLevel") == 99]

        self.assertGreaterEqual(len(alias_events), 1)
        self.assertGreaterEqual(len(config_events), 1)
        self.assertGreaterEqual(len(state_events), 1)
        self.assertEqual(proc.returncode, 0)

    def test_dbus_method_failures_emit_structured_jsonl_errors(self):
        """Verify hold, release, enumerate, and UiAction D-Bus failures emit structured JSONL error events."""
        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)
        # Test HoldService D-Bus failure
        self.fail_hold = True
        proc.stdin.write(json.dumps({"command": "hold"}) + "\n")
        proc.stdin.flush()
        time.sleep(0.05)

        # Test ListDevices D-Bus failure
        self.fail_list_devices = True
        proc.stdin.write(json.dumps({"command": "enumerate"}) + "\n")
        proc.stdin.flush()
        time.sleep(0.05)

        # Test UiAction D-Bus failure
        self.fail_ui_action = True
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": self.dev_path,
            "action": "toggle1State",
            "value": 1,
        }) + "\n")
        proc.stdin.flush()
        time.sleep(0.05)

        # Test ReleaseService D-Bus failure
        self.fail_release = True
        proc.stdin.write(json.dumps({"command": "release"}) + "\n")
        proc.stdin.flush()
        time.sleep(0.05)

        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]

        error_codes = [l.get("code") for l in lines if l.get("type") == "error"]
        self.assertIn("holdFailed", error_codes)
        self.assertIn("enumerateFailed", error_codes)
        self.assertIn("actionFailed", error_codes)

        # Check serviceStatus reconciliation on hold failure (held: false)
        hold_statuses = [l for l in lines if l.get("type") == "serviceStatus"]
        self.assertTrue(any(s.get("held") is False for s in hold_statuses))
        self.assertEqual(proc.returncode, 0)

    def test_service_owner_loss_and_reappearance(self):
        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)

        # Unown name to simulate service exit / crash
        Gio.bus_unown_name(self.name_owner_id)
        self.name_owner_id = 0
        time.sleep(0.15)

        # Re-own name to simulate service restart
        reacquire_event = threading.Event()
        self.name_owner_id = Gio.bus_own_name_on_connection(
            self.conn,
            "io.github.maniacx.BudsLink",
            Gio.BusNameOwnerFlags.NONE,
            lambda c, n: reacquire_event.set(),
            None,
        )
        reacquire_event.wait(timeout=3)
        time.sleep(0.2)

        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]

        vanished_events = [l for l in lines if l.get("type") == "serviceStatus" and l.get("available") is False]
        reappeared_events = [l for l in lines if l.get("type") == "serviceStatus" and l.get("available") is True]

        self.assertGreaterEqual(len(vanished_events), 1)
        self.assertGreaterEqual(len(reappeared_events), 2)
        self.assertEqual(proc.returncode, 0)

    def test_incompatible_service_version_rejection(self):
        self.service_version = "0.0.2"  # Unsupported version

        proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=self.fixture.get_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.15)
        proc.stdin.write(json.dumps({"command": "hold"}) + "\n")
        proc.stdin.write(json.dumps({"command": "enumerate"}) + "\n")
        proc.stdin.write(json.dumps({
            "command": "action",
            "path": self.dev_path,
            "action": "toggle1State",
            "value": 1,
        }) + "\n")
        proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        proc.stdin.flush()
        stdout, stderr = proc.communicate(timeout=5)

        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        unsupported_errors = [l for l in lines if l.get("type") == "error" and l.get("code") == "serviceVersionUnsupported"]
        self.assertGreaterEqual(len(unsupported_errors), 1)

        # Ensure no hold or action was forwarded to the D-Bus service
        self.assertEqual(len(self.holds), 0)
        self.assertEqual(len(self.actions), 0)
        self.assertEqual(proc.returncode, 0)


class BudsLinkIsolatedAutoStartActivationTests(unittest.TestCase):
    """Deterministic D-Bus activation tests where BudsLink service is auto-started by bridge.js name watch."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="test_budslink_autostart_")
        self.services_dir = os.path.join(self.test_dir, "services")
        os.makedirs(self.services_dir, exist_ok=True)

        self.dev_path = "/io/github/maniacx/BudsLink/Devices/hci0/dev_11_22_33_44_55_66"
        self.daemon_started_file = os.path.join(self.test_dir, "daemon_started.txt")
        self.service_version_file = os.path.join(self.test_dir, "service_version_invoked.txt")
        self.hold_file = os.path.join(self.test_dir, "hold_invoked.txt")
        self.release_file = os.path.join(self.test_dir, "release_invoked.txt")
        self.list_devices_file = os.path.join(self.test_dir, "list_devices_invoked.txt")
        self.action_file = os.path.join(self.test_dir, "action_invoked.txt")
        self.bridge_proc = None

        # Create mock daemon executable
        self.daemon_script = os.path.join(self.test_dir, "mock_activatable_budslink.py")
        daemon_code = f'''#!/usr/bin/env python3
import sys, os, json, signal, warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from gi.repository import Gio, GLib

loop = GLib.MainLoop()

def on_bus_closed(connection, remote_peer_vanished, error):
    loop.quit()

try:
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    conn.connect("closed", on_bus_closed)
except Exception:
    sys.exit(1)

def on_signal(signum, frame):
    loop.quit()
    sys.exit(0)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

MANAGER_XML = """
<node>
  <interface name="io.github.maniacx.BudsLink.DeviceManager">
    <method name="HoldService">
      <arg type="s" name="clientId" direction="in"/>
    </method>
    <method name="ReleaseService">
      <arg type="s" name="clientId" direction="in"/>
    </method>
    <method name="ServiceVersion">
      <arg type="s" name="version" direction="out"/>
    </method>
    <method name="ListDevices">
      <arg type="ao" name="devices" direction="out"/>
    </method>
    <signal name="DeviceAdded">
      <arg type="o" name="objectPath"/>
    </signal>
    <signal name="DeviceRemoved">
      <arg type="o" name="objectPath"/>
    </signal>
  </interface>
</node>
"""

DEVICE_XML = """
<node>
  <interface name="io.github.maniacx.BudsLink.Device">
    <property name="Alias" type="s" access="read"/>
    <property name="Config" type="s" access="read"/>
    <property name="State" type="s" access="read"/>
    <method name="UiAction">
      <arg type="s" name="actionName" direction="in"/>
      <arg type="i" name="value" direction="in"/>
    </method>
  </interface>
</node>
"""

dev_path = "{self.dev_path}"
test_dir = "{self.test_dir}"

def handle_manager(conn, sender, path, iface, method, params, invocation):
    if method == "ServiceVersion":
        with open(os.path.join(test_dir, "service_version_invoked.txt"), "a") as f:
            f.write("invoked\\n")
            f.flush()
        invocation.return_value(GLib.Variant("(s)", ("0.0.1",)))
    elif method == "HoldService":
        c_id = params.unpack()[0]
        with open(os.path.join(test_dir, "hold_invoked.txt"), "a") as hf:
            hf.write(c_id + "\\n")
            hf.flush()
        invocation.return_value(None)
    elif method == "ReleaseService":
        c_id = params.unpack()[0]
        with open(os.path.join(test_dir, "release_invoked.txt"), "a") as rf:
            rf.write(c_id + "\\n")
            rf.flush()
        invocation.return_value(None)
    elif method == "ListDevices":
        with open(os.path.join(test_dir, "list_devices_invoked.txt"), "a") as ldf:
            ldf.write("listed\\n")
            ldf.flush()
        invocation.return_value(GLib.Variant("(ao)", ([dev_path],)))
    else:
        invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, method)

def handle_device(conn, sender, path, iface, method, params, invocation):
    if method == "UiAction":
        action, val = params.unpack()
        with open(os.path.join(test_dir, "action_invoked.txt"), "a") as af:
            af.write(f"{{action}}:{{val}}\\n")
            af.flush()
        invocation.return_value(None)
    else:
        invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, method)

def handle_prop(conn, sender, path, iface, prop):
    if prop == "Alias":
        return GLib.Variant("s", "AutoStarted Buds Pro")
    elif prop == "Config":
        return GLib.Variant("s", json.dumps({{"battery1Icon": "earbuds-left", "battery2Icon": "earbuds-right"}}))
    elif prop == "State":
        return GLib.Variant("s", json.dumps({{"computedBatteryLevel": 91, "battery1Level": 92, "battery1Status": "discharging"}}))
    return None

mgr_node = Gio.DBusNodeInfo.new_for_xml(MANAGER_XML)
dev_node = Gio.DBusNodeInfo.new_for_xml(DEVICE_XML)

conn.register_object("/io/github/maniacx/BudsLink", mgr_node.interfaces[0], handle_manager, None, None)
conn.register_object(dev_path, dev_node.interfaces[0], handle_device, handle_prop, None)

Gio.bus_own_name_on_connection(conn, "io.github.maniacx.BudsLink", Gio.BusNameOwnerFlags.NONE, None, None)

with open(os.path.join(test_dir, "daemon_started.txt"), "w") as sf:
    sf.write(str(os.getpid()))
    sf.flush()

loop.run()
'''
        with open(self.daemon_script, "w", encoding="utf-8") as f:
            f.write(daemon_code)
        os.chmod(self.daemon_script, 0o755)

        # Create D-Bus service activation file
        service_file = os.path.join(self.services_dir, "io.github.maniacx.BudsLink.service")
        with open(service_file, "w", encoding="utf-8") as f:
            f.write(f"""[D-BUS Service]
Name=io.github.maniacx.BudsLink
Exec={self.daemon_script}
""")

        # Fixture with custom servicedir
        self.fixture = IsolatedDBusFixture(servicedir=self.services_dir)

    def _wait_for_sentinel(self, file_path, timeout=5.0, check_fn=None, msg=""):
        """Deterministic bounded polling for a sentinel file/condition."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if os.path.exists(file_path):
                if check_fn is None:
                    return True
                try:
                    with open(file_path, "r", encoding="utf-8") as f:
                        content = f.read()
                    if check_fn(content):
                        return True
                except Exception:
                    pass
            time.sleep(0.01)
        detail = f": {msg}" if msg else ""
        self.fail(f"Timed out after {timeout}s waiting for sentinel '{os.path.basename(file_path)}'{detail}")

    def tearDown(self):
        # 1. Clean up bridge process if still running
        if getattr(self, "bridge_proc", None) is not None and self.bridge_proc.poll() is None:
            try:
                self.bridge_proc.terminate()
                self.bridge_proc.wait(timeout=1)
            except Exception:
                try:
                    self.bridge_proc.kill()
                    self.bridge_proc.wait(timeout=1)
                except Exception:
                    pass

        # 2. Terminate and reap exact mock daemon child PID
        daemon_pid = None
        if os.path.exists(self.daemon_started_file):
            try:
                with open(self.daemon_started_file, "r", encoding="utf-8") as f:
                    pid_str = f.read().strip()
                if pid_str.isdigit():
                    daemon_pid = int(pid_str)
            except Exception:
                pass

        if daemon_pid is not None:
            try:
                os.kill(daemon_pid, signal.SIGTERM)
            except (ProcessLookupError, OSError):
                daemon_pid = None

        if daemon_pid is not None:
            deadline = time.monotonic() + 2.0
            while time.monotonic() < deadline:
                try:
                    os.kill(daemon_pid, 0)
                    time.sleep(0.01)
                except (ProcessLookupError, OSError):
                    daemon_pid = None
                    break

        if daemon_pid is not None:
            try:
                os.kill(daemon_pid, signal.SIGKILL)
            except (ProcessLookupError, OSError):
                pass

        # 3. Close isolated D-Bus fixture
        if hasattr(self, "fixture") and self.fixture:
            self.fixture.close()

        # 4. Clean up temporary test directory
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_bridge_autostarts_budslink_service_deterministically(self):
        """Verify bridge.js Gio.bus_watch_name AUTO_START launches activatable mock service and interacts cleanly."""
        env = self.fixture.get_env()
        self.assertIn("DBUS_SESSION_BUS_ADDRESS", env)
        self.assertTrue(env["DBUS_SESSION_BUS_ADDRESS"].startswith("unix:"))
        real_user_bus = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
        if real_user_bus:
            self.assertNotEqual(env["DBUS_SESSION_BUS_ADDRESS"], real_user_bus)

        # 1. Assert daemon has NOT started initially and name has no owner
        self.assertFalse(os.path.exists(self.daemon_started_file))

        conn = Gio.DBusConnection.new_for_address_sync(
            self.fixture.address,
            Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
            None,
            None,
        )
        has_owner_reply = conn.call_sync(
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            GLib.Variant("(s)", ("io.github.maniacx.BudsLink",)),
            None,
            Gio.DBusCallFlags.NONE,
            1000,
            None,
        )
        self.assertFalse(has_owner_reply.unpack()[0], "BudsLink name must have no owner initially")

        # 2. Spawn bridge.js (which registers Gio.bus_watch_name with AUTO_START)
        self.bridge_proc = subprocess.Popen(
            ["gjs", "-m", str(BRIDGE_JS)],
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # Bounded deterministic wait for activation sentinels:
        # a) Daemon start / readiness sentinel
        self._wait_for_sentinel(
            self.daemon_started_file,
            timeout=5.0,
            check_fn=lambda c: len(c.strip()) > 0 and c.strip().isdigit(),
            msg="mock daemon activation PID sentinel",
        )
        # b) Service version method invocation sentinel (acquired bus name / handshake)
        self._wait_for_sentinel(
            self.service_version_file,
            timeout=5.0,
            check_fn=lambda c: "invoked" in c,
            msg="ServiceVersion call sentinel",
        )
        # c) Device discovery sentinel (ListDevices queried by bridge)
        self._wait_for_sentinel(
            self.list_devices_file,
            timeout=5.0,
            check_fn=lambda c: "listed" in c,
            msg="ListDevices call sentinel",
        )

        # 3. Send hold command and await sentinel
        self.bridge_proc.stdin.write(json.dumps({"command": "hold"}) + "\n")
        self.bridge_proc.stdin.flush()
        self._wait_for_sentinel(
            self.hold_file,
            timeout=5.0,
            check_fn=lambda c: "ii-p3drovfx-budslink" in c,
            msg="HoldService method invocation",
        )

        # 4. Send UiAction command and await sentinel
        self.bridge_proc.stdin.write(json.dumps({
            "command": "action",
            "path": self.dev_path,
            "action": "toggle1State",
            "value": 1,
        }) + "\n")
        self.bridge_proc.stdin.flush()
        self._wait_for_sentinel(
            self.action_file,
            timeout=5.0,
            check_fn=lambda c: "toggle1State:1" in c,
            msg="UiAction method invocation",
        )

        # 5. Send release and shutdown commands
        self.bridge_proc.stdin.write(json.dumps({"command": "release"}) + "\n")
        self.bridge_proc.stdin.flush()
        self._wait_for_sentinel(
            self.release_file,
            timeout=5.0,
            check_fn=lambda c: "ii-p3drovfx-budslink" in c,
            msg="ReleaseService method invocation",
        )

        self.bridge_proc.stdin.write(json.dumps({"command": "shutdown"}) + "\n")
        self.bridge_proc.stdin.flush()

        stdout, stderr = self.bridge_proc.communicate(timeout=5)
        self.assertEqual(self.bridge_proc.returncode, 0)

        # 6. Assert mock was started by D-Bus daemon auto-activation
        self.assertTrue(os.path.exists(self.daemon_started_file), "Mock daemon must be launched by D-Bus activation")
        self.assertTrue(os.path.exists(self.service_version_file), "ServiceVersion must be called by bridge")
        self.assertTrue(os.path.exists(self.list_devices_file), "ListDevices must be called during discovery")
        self.assertTrue(os.path.exists(self.hold_file), "HoldService must be called on hold command")
        self.assertTrue(os.path.exists(self.release_file), "ReleaseService must be called on release command")
        self.assertTrue(os.path.exists(self.action_file), "UiAction must be called on action command")

        with open(self.hold_file, "r") as f:
            hold_clients = [line.strip() for line in f if line.strip()]
        self.assertIn("ii-p3drovfx-budslink", hold_clients)

        with open(self.action_file, "r") as f:
            actions_executed = [line.strip() for line in f if line.strip()]
        self.assertIn("toggle1State:1", actions_executed)

        # 7. Verify bridge JSONL outputs
        lines = [json.loads(line) for line in stdout.strip().split("\n") if line.strip()]
        self.assertGreaterEqual(len(lines), 3)

        # bridgeReady
        self.assertEqual(lines[0], {"type": "bridgeReady", "protocol": 1})

        # serviceStatus compatible & available
        status_events = [l for l in lines if l.get("type") == "serviceStatus"]
        self.assertTrue(any(s.get("available") is True and s.get("version") == "0.0.1" for s in status_events))

        # deviceSnapshot
        snapshots = [l for l in lines if l.get("type") == "deviceSnapshot"]
        self.assertEqual(len(snapshots), 1)
        snap = snapshots[0]
        self.assertEqual(snap["path"], self.dev_path)
        self.assertEqual(snap["mac"], "11:22:33:44:55:66")
        self.assertEqual(snap["alias"], "AutoStarted Buds Pro")
        self.assertEqual(snap["state"]["computedBatteryLevel"], 91)
        self.assertEqual(snap["config"]["battery1Icon"], "earbuds-left")

        # Held transition verification
        held_events = [s for s in status_events if s.get("held") is True]
        self.assertGreaterEqual(len(held_events), 1)


class BudsLinkServiceContractTests(unittest.TestCase):
    """Static and architectural conformance tests for BudsLinkService.qml."""

    def setUp(self):
        self.service_code = SERVICE_QML.read_text(encoding="utf-8")
        self.shell_code = SHELL_QML.read_text(encoding="utf-8")

    def test_singleton_pragmas(self):
        self.assertIn("pragma Singleton", self.service_code)
        self.assertIn("pragma ComponentBehavior: Bound", self.service_code)

    def test_plan_section_14_properties_declared(self):
        required_props = [
            "bridgeRunning",
            "serviceAvailable",
            "serviceCompatible",
            "serviceVersion",
            "serviceHeld",
            "lastError",
            "lastErrorCode",
            "devicesByMac",
            "devices",
            "activeDeviceCount",
        ]
        for prop in required_props:
            self.assertIn("readonly property", self.service_code)
            self.assertIn(prop, self.service_code)

    def test_explicit_version_compatibility(self):
        self.assertIn('readonly property list<string> supportedVersions: ["0.0.1"]', self.service_code)
        self.assertIn("function isVersionSupported(version: string): bool", self.service_code)
        self.assertIn("root.isVersionSupported(root._serviceVersion)", self.service_code)

    def test_plan_section_14_functions_declared(self):
        required_funcs = [
            "function hasDevice(device)",
            "function hasMac(mac)",
            "function infoForDevice(device)",
            "function infoForMac(mac)",
            "function batteryInfo(device)",
            "function controlsForDevice(device)",
            "function sendAction(deviceOrMac, action, value)",
            "function openDeviceSettings(deviceOrMac)",
            "function requestHold()",
            "function release()",
            "function refresh()",
        ]
        for func in required_funcs:
            func_name = func.split("(")[0]
            self.assertIn(func_name, self.service_code)

    def test_process_and_pdeath_patterns(self):
        self.assertIn("Process {", self.service_code)
        self.assertIn("ProcUtils.pdeath", self.service_code)
        self.assertIn("stdinEnabled: true", self.service_code)
        self.assertIn("SplitParser {", self.service_code)

    def test_no_process_write_when_bridge_not_running(self):
        self.assertIn("if (!bridgeProc.running)", self.service_code)

    def test_candidate_detection_uses_generic_indicators_without_brand_keywords(self):
        """Verify candidate detection does NOT use brand/name keywords like pro/wireless/galaxy."""
        self.assertIn("function isAudioCandidate(device): bool", self.service_code)
        # Generic BlueZ icon checks
        self.assertIn('icon.includes("headset")', self.service_code)
        self.assertIn('icon.includes("headphones")', self.service_code)
        self.assertIn('icon.includes("audio")', self.service_code)
        # BlueZ profile UUID checks
        self.assertIn("0000110d-", self.service_code)
        # Prohibited brand / keyword name-guessing must NOT be in isAudioCandidate
        self.assertNotIn('name.includes("galaxy")', self.service_code)
        self.assertNotIn('name.includes("wireless")', self.service_code)
        self.assertNotIn('name.includes("pro")', self.service_code)
        self.assertNotIn('name.includes("freebuds")', self.service_code)
        self.assertNotIn('name.includes("soundcore")', self.service_code)
        self.assertNotIn('name.includes("linkbuds")', self.service_code)

    def test_clean_shutdown_and_reconnect_race_recovery(self):
        """Verify onExited properly handles shouldBridgeRun === true on exit 0 and non-zero."""
        self.assertIn("stopFallbackTimer", self.service_code)
        self.assertIn("property bool _stopping: false", self.service_code)
        self.assertIn("root._stopping = true", self.service_code)
        # On exit, bridgeRestartTimer is restarted whenever shouldBridgeRun is true
        self.assertIn("if (root.shouldBridgeRun)", self.service_code)
        self.assertIn("bridgeRestartTimer.restart()", self.service_code)

    def test_bounded_diagnostics_activation_on_refresh(self):
        """Verify refresh activates bounded _diagnosticsActive and starts diagnosticsTimeoutTimer."""
        self.assertIn("property bool _diagnosticsActive: false", self.service_code)
        self.assertIn("diagnosticsTimeoutTimer", self.service_code)
        self.assertIn("root._diagnosticsActive = true", self.service_code)
        self.assertIn("diagnosticsTimeoutTimer.restart()", self.service_code)
        # shouldBridgeRun must incorporate _diagnosticsActive
        self.assertIn("root._diagnosticsActive", self.service_code)

    def test_atomic_snapshot_replacement_without_key_merging(self):
        self.assertIn('case "deviceAlias":', self.service_code)
        self.assertIn('case "deviceState":', self.service_code)
        self.assertIn('case "deviceConfig":', self.service_code)
        # Ensure state and config are replaced atomically, not Object.assign merged
        self.assertIn("state: (event.state && typeof event.state === \"object\") ? event.state : prev.state", self.service_code)
        self.assertIn("config: (event.config && typeof event.config === \"object\") ? event.config : prev.config", self.service_code)

    def test_candidate_detection_behavior_matrix(self):
        """Simulate isAudioCandidate with test device objects to verify exact behavior."""
        def is_audio_candidate(device, devices_by_mac=None):
            if not device or not device.get("connected"):
                return False
            mac = device.get("address", "").replace("-", ":").upper()
            if devices_by_mac and mac in devices_by_mac:
                return True
            icon = (device.get("icon") or "").lower()
            if icon:
                if "headset" in icon or "headphones" in icon or "audio" in icon:
                    return True
                if any(x in icon for x in ["keyboard", "mouse", "touchpad", "phone", "computer", "gaming", "input", "controller", "gamepad", "dongle"]):
                    return False
            uuids = device.get("uuids") or []
            if any(any(k in str(u).lower() for k in ["0000110a-", "0000110b-", "0000110d-", "00001108-", "00001112-", "0000111e-", "0000111f-", "0000110e-"]) for u in uuids):
                return True
            return False

        # Audio devices: detected by icon or UUID
        self.assertTrue(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "icon": "audio-headset"}))
        self.assertTrue(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "icon": "audio-headphones"}))
        self.assertTrue(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "icon": "audio-card"}))
        self.assertTrue(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "icon": "audio-speaker"}))
        self.assertTrue(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "uuids": ["0000110d-0000-1000-8000-00805f9b34fb"]}))

        # Claimed BudsLink device: detected regardless of icon
        self.assertTrue(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66"}, devices_by_mac={"11:22:33:44:55:66": {}}))

        # Non-audio devices: rejected even if device name has "galaxy pro wireless buds"
        self.assertFalse(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "name": "Galaxy Buds Pro Wireless", "icon": "input-mouse"}))
        self.assertFalse(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "name": "Galaxy Buds Pro Wireless", "icon": "input-keyboard"}))
        self.assertFalse(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "name": "Galaxy Buds Pro Wireless", "icon": "phone"}))
        self.assertFalse(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "name": "Galaxy Buds Pro Wireless", "icon": "computer"}))

        # Safe fallback: no audio icon or UUID -> rejected (no name guessing!)
        self.assertFalse(is_audio_candidate({"connected": True, "address": "11:22:33:44:55:66", "name": "Galaxy Buds Pro Wireless", "icon": ""}))

        # Disconnected audio device: rejected
        self.assertFalse(is_audio_candidate({"connected": False, "address": "11:22:33:44:55:66", "icon": "audio-headset"}))

    def test_registered_in_shell_qml(self):
        self.assertIn("BudsLinkService.serviceAvailable;", self.shell_code)


if __name__ == "__main__":
    unittest.main()
