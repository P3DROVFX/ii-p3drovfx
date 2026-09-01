import importlib.util
import io
import json
import os
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest import mock
from contextlib import redirect_stdout


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "portwatcher.py"
REPO_ROOT = SCRIPT_PATH.parent.parent
SPEC = importlib.util.spec_from_file_location("portwatcher", SCRIPT_PATH)
portwatcher = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(portwatcher)


class EndpointParsingTests(unittest.TestCase):
    def test_ipv4_endpoint(self):
        self.assertEqual(portwatcher.split_endpoint("127.0.0.1:8080"), ("127.0.0.1", 8080))

    def test_bracketed_ipv6_endpoint(self):
        self.assertEqual(portwatcher.split_endpoint("[::1]:443"), ("::1", 443))

    def test_ipv6_endpoint_with_zone_after_bracket(self):
        self.assertEqual(
            portwatcher.split_endpoint("[fe80::1234]%wlan0:546"),
            ("fe80::1234%wlan0", 546),
        )


class SocketParsingTests(unittest.TestCase):
    def test_loopback_listener_with_process(self):
        parsed = portwatcher.parse_ss_line(
            'tcp LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:(("demo",pid=4242,fd=9))'
        )
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed["kind"], "listener")
        self.assertEqual(parsed["localPort"], 8080)
        self.assertEqual(parsed["process"], "demo")
        self.assertTrue(parsed["loopback"])
        self.assertFalse(parsed["exposed"])

    def test_wildcard_udp_listener_is_exposed(self):
        parsed = portwatcher.parse_ss_line("udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:*")
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed["protocol"], "udp")
        self.assertTrue(parsed["wildcard"])
        self.assertTrue(parsed["exposed"])

    def test_established_socket_is_a_connection(self):
        parsed = portwatcher.parse_ss_line(
            'tcp ESTAB 0 0 127.0.0.1:8080 127.0.0.1:50100 users:(("demo",pid=4242,fd=12))'
        )
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed["kind"], "connection")
        self.assertEqual(parsed["localPort"], 8080)
        self.assertFalse(parsed["exposed"])

    def test_time_wait_socket_is_not_reported_as_active(self):
        parsed = portwatcher.parse_ss_line(
            "tcp TIME-WAIT 0 0 127.0.0.1:50100 127.0.0.1:8080"
        )
        self.assertIsNone(parsed)

    def test_process_details_are_cached_within_a_scan(self):
        details = {"uid": os.getuid(), "command": "demo", "canManage": True, "startTime": "123"}
        cache = {}
        with mock.patch.object(portwatcher, "process_details", return_value=details) as lookup:
            first = portwatcher.parse_ss_line(
                'tcp LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:(("demo",pid=4242,fd=9))',
                cache,
            )
            second = portwatcher.parse_ss_line(
                'tcp LISTEN 0 128 127.0.0.1:8081 0.0.0.0:* users:(("demo",pid=4242,fd=10))',
                cache,
            )
        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertEqual(lookup.call_count, 1)


class CollapseTests(unittest.TestCase):
    def parse(self, *lines):
        cache = {}
        details = {"uid": os.getuid(), "command": "demo --serve", "canManage": True, "startTime": "123"}
        with mock.patch.object(portwatcher, "process_details", return_value=details):
            return [
                parsed
                for parsed in (portwatcher.parse_ss_line(line, cache) for line in lines)
                if parsed is not None
            ]

    def test_dual_stack_listener_becomes_one_entry(self):
        records = self.parse(
            'tcp LISTEN 0 511 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=4242,fd=9))',
            'tcp LISTEN 0 511 [::]:3000 [::]:* users:(("node",pid=4242,fd=10))',
        )
        ports, truncated = portwatcher.collapse_ports(records)
        self.assertFalse(truncated)
        self.assertEqual(len(ports), 1)
        self.assertEqual(ports[0]["port"], 3000)
        self.assertEqual(ports[0]["process"], "node")
        self.assertTrue(ports[0]["exposed"])
        self.assertEqual(len(ports[0]["addresses"]), 2)

    def test_same_port_from_two_processes_stays_separate(self):
        records = self.parse(
            'tcp LISTEN 0 511 127.0.0.1:8000 0.0.0.0:* users:(("node",pid=1,fd=9))',
            'tcp LISTEN 0 511 127.0.0.2:8000 0.0.0.0:* users:(("python3",pid=2,fd=9))',
        )
        ports, _ = portwatcher.collapse_ports(records)
        self.assertEqual(len(ports), 2)

    def test_live_connections_are_counted_against_their_listener(self):
        records = self.parse(
            'tcp LISTEN 0 511 0.0.0.0:3000 0.0.0.0:* users:(("node",pid=4242,fd=9))',
            'tcp ESTAB 0 0 192.168.0.10:3000 192.168.0.55:51000 users:(("node",pid=4242,fd=20))',
            'tcp ESTAB 0 0 192.168.0.10:3000 192.168.0.56:51001 users:(("node",pid=4242,fd=21))',
        )
        ports, _ = portwatcher.collapse_ports(records)
        self.assertEqual(len(ports), 1)
        self.assertEqual(ports[0]["connections"], 2)
        self.assertEqual(len(ports[0]["peers"]), 2)

    def test_a_loopback_only_listener_is_not_exposed(self):
        records = self.parse(
            'tcp LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=4242,fd=9))',
        )
        ports, _ = portwatcher.collapse_ports(records)
        self.assertTrue(ports[0]["loopback"])
        self.assertFalse(ports[0]["exposed"])
        self.assertEqual(ports[0]["category"], "web")

    def test_unowned_listener_is_labelled_system(self):
        records = [
            portwatcher.parse_ss_line("udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:*")
        ]
        ports, _ = portwatcher.collapse_ports(records)
        self.assertFalse(ports[0]["owned"])
        self.assertEqual(ports[0]["category"], "system")
        self.assertEqual(ports[0]["process"], "System")


class ScanTests(unittest.TestCase):
    def run_scan_with(self, completed):
        output = io.StringIO()
        with mock.patch.object(portwatcher.shutil, "which", return_value="/usr/bin/ss"):
            with mock.patch.object(portwatcher.subprocess, "run", return_value=completed):
                with redirect_stdout(output):
                    exit_code = portwatcher.scan()
        return exit_code, json.loads(output.getvalue())

    def test_scan_has_a_bounded_payload(self):
        lines = [
            f"tcp LISTEN 0 128 0.0.0.0:{10000 + index} 0.0.0.0:*"
            for index in range(portwatcher.MAX_PORTS + 5)
        ]
        exit_code, payload = self.run_scan_with(
            SimpleNamespace(returncode=0, stdout="\n".join(lines), stderr="")
        )
        self.assertEqual(exit_code, 0)
        self.assertEqual(len(payload["ports"]), portwatcher.MAX_PORTS)
        self.assertTrue(payload["truncated"])
        self.assertEqual(payload["limit"], portwatcher.MAX_PORTS)

    def test_scan_reports_a_nonzero_ss_failure(self):
        exit_code, payload = self.run_scan_with(
            SimpleNamespace(returncode=2, stdout="", stderr="permission denied")
        )
        self.assertEqual(exit_code, 1)
        self.assertFalse(payload["ok"])
        self.assertIn("permission denied", payload["error"])

    def test_scan_reports_timeout(self):
        output = io.StringIO()
        with mock.patch.object(portwatcher.shutil, "which", return_value="/usr/bin/ss"):
            with mock.patch.object(
                portwatcher.subprocess,
                "run",
                side_effect=portwatcher.subprocess.TimeoutExpired(["ss"], 5),
            ):
                with redirect_stdout(output):
                    exit_code = portwatcher.scan()
        payload = json.loads(output.getvalue())
        self.assertEqual(exit_code, 1)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["ports"], [])


class ActionGuardTests(unittest.TestCase):
    def test_current_test_process_is_owned(self):
        allowed, error, process_name = portwatcher.owned_process(os.getpid())
        self.assertTrue(allowed)
        self.assertEqual(error, "")
        self.assertTrue(process_name)

    def test_pid_one_is_never_manageable(self):
        allowed, error, _ = portwatcher.owned_process(1)
        self.assertFalse(allowed)
        self.assertIn("Invalid", error)

    def test_snapshot_identity_mismatch_is_rejected(self):
        identity = {
            "uid": os.getuid(),
            "name": "replacement",
            "command": "replacement",
            "startTime": "222",
        }
        with mock.patch.object(portwatcher, "read_process_identity", return_value=identity):
            allowed, error, _ = portwatcher.owned_process(
                4242,
                expected_start_time="111",
                expected_name="original",
            )
        self.assertFalse(allowed)
        self.assertIn("changed", error.lower())

    def test_protected_process_name_is_rejected(self):
        identity = {
            "uid": os.getuid(),
            "name": "quickshell",
            "command": "quickshell",
            "startTime": "123",
        }
        with mock.patch.object(portwatcher, "read_process_identity", return_value=identity):
            allowed, error, _ = portwatcher.owned_process(
                4242,
                expected_start_time="123",
                expected_name="quickshell",
            )
        self.assertFalse(allowed)
        self.assertIn("protected", error.lower())

    def test_foreign_uid_is_rejected(self):
        identity = {
            "uid": os.getuid() + 1,
            "name": "foreign",
            "command": "foreign",
            "startTime": "123",
        }
        with mock.patch.object(portwatcher, "read_process_identity", return_value=identity):
            allowed, error, _ = portwatcher.owned_process(
                4242,
                expected_start_time="123",
                expected_name="foreign",
            )
        self.assertFalse(allowed)
        self.assertIn("current user", error.lower())

    def test_identity_failure_never_sends_a_signal(self):
        output = io.StringIO()
        with mock.patch.object(portwatcher.os, "pidfd_open", return_value=77):
            with mock.patch.object(portwatcher, "owned_process", return_value=(False, "changed", "replacement")):
                with mock.patch.object(portwatcher.signal, "pidfd_send_signal") as send_signal:
                    with mock.patch.object(portwatcher.os, "close"):
                        with redirect_stdout(output):
                            exit_code = portwatcher.stop_process(4242, False, "111", "original")
        self.assertEqual(exit_code, 1)
        self.assertFalse(json.loads(output.getvalue())["ok"])
        send_signal.assert_not_called()

    def test_verified_process_uses_pidfd_signal(self):
        output = io.StringIO()
        with mock.patch.object(portwatcher.os, "pidfd_open", return_value=77):
            with mock.patch.object(portwatcher, "owned_process", return_value=(True, "", "demo")):
                with mock.patch.object(portwatcher.signal, "pidfd_send_signal") as send_signal:
                    with mock.patch.object(portwatcher.os, "close") as close_fd:
                        with redirect_stdout(output):
                            exit_code = portwatcher.stop_process(4242, False, "111", "demo")
        self.assertEqual(exit_code, 0)
        self.assertTrue(json.loads(output.getvalue())["ok"])
        send_signal.assert_called_once_with(77, portwatcher.signal.SIGTERM, None, 0)
        close_fd.assert_called_once_with(77)

    def test_force_stop_uses_sigkill(self):
        output = io.StringIO()
        with mock.patch.object(portwatcher.os, "pidfd_open", return_value=77):
            with mock.patch.object(portwatcher, "owned_process", return_value=(True, "", "demo")):
                with mock.patch.object(portwatcher.signal, "pidfd_send_signal") as send_signal:
                    with mock.patch.object(portwatcher.os, "close"):
                        with redirect_stdout(output):
                            portwatcher.stop_process(4242, True, "111", "demo")
        send_signal.assert_called_once_with(77, portwatcher.signal.SIGKILL, None, 0)

    def test_stop_without_an_identity_snapshot_is_refused(self):
        output = io.StringIO()
        with redirect_stdout(output):
            exit_code = portwatcher.stop_process(4242, False, "", "")
        self.assertEqual(exit_code, 1)
        self.assertFalse(json.loads(output.getvalue())["ok"])


class QmlIntegrationContractTests(unittest.TestCase):
    def test_widget_offers_both_bar_styles(self):
        registry = (REPO_ROOT / "modules/common/BarComponentRegistry.qml").read_text()
        widget_registry = (REPO_ROOT / "modules/ii/bar/registry/BarWidgetRegistry.qml").read_text()
        bar_component = (REPO_ROOT / "modules/ii/bar/BarComponent.qml").read_text()
        config = (REPO_ROOT / "modules/common/Config.qml").read_text()

        self.assertIn('id: "port_watcher"', registry)
        self.assertIn('styleConfigKey: "portWatcher"', registry)
        self.assertIn('configPage: "PortWatcherConfig.qml"', registry)
        self.assertIn('case "port_watcher":           return s.portWatcher  ?? "default";', widget_registry)
        self.assertIn('property string portWatcher: "expressive"', config)
        self.assertIn('case "port_watcher":', bar_component)
        self.assertIn("PortWatcherWidget {", bar_component)
        self.assertIn("ExpressivePortWatcher {", bar_component)

    def test_both_widget_variants_exist(self):
        widget_dir = REPO_ROOT / "modules/ii/bar/widgets/portWatcher"
        self.assertTrue((widget_dir / "PortWatcherWidget.qml").is_file())
        self.assertTrue((widget_dir / "ExpressivePortWatcher.qml").is_file())

    def test_settings_page_is_search_indexed(self):
        settings_registry = (REPO_ROOT / "modules/common/SettingsPageRegistry.qml").read_text()
        self.assertIn('"widgets/PortWatcherConfig.qml"', settings_registry)

    def test_feature_surfaces_do_not_define_borders(self):
        qml_paths = [
            REPO_ROOT / "modules/ii/bar/widgets/portWatcher/PortWatcherWidget.qml",
            REPO_ROOT / "modules/ii/bar/widgets/portWatcher/ExpressivePortWatcher.qml",
            REPO_ROOT / "modules/ii/bar/popups/portWatcher/PortWatcherPopup.qml",
            REPO_ROOT / "modules/ii/bar/popups/portWatcher/PortRow.qml",
        ]
        combined = "\n".join(path.read_text() for path in qml_paths)
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)

    def test_settings_page_owns_the_filter_surface(self):
        page = (REPO_ROOT / "modules/settings/configs/widgets/PortWatcherConfig.qml").read_text()
        for option in ("watchPorts", "ignorePorts", "ignoreProcesses", "minPort", "maxPort", "sortMode"):
            self.assertIn(f"portWatcher.{option}", page)

    def test_popup_keeps_the_shared_hover_contract(self):
        popup = (REPO_ROOT / "modules/ii/bar/popups/portWatcher/PortWatcherPopup.qml").read_text()
        self.assertIn("stickyHover: true", popup)
        # The popup carries no text input, so it must not grab the keyboard.
        self.assertNotIn("keyboardFocus", popup)

    def test_row_follows_the_dialog_slide_grammar(self):
        """The row must stay the two-page slide the Wi-Fi/Bluetooth dialogs use."""
        row = (REPO_ROOT / "modules/ii/bar/popups/portWatcher/PortRow.qml").read_text()
        self.assertIn("contentWidth: flick.width * 2 + 8", row)
        self.assertIn("interactive: false", row)
        self.assertIn("Easing.OutExpo", row)
        self.assertIn("topLeftRadius: root.topRadius", row)
        # No accordion: the row height never grows to make room for actions.
        self.assertIn("implicitHeight: 56", row)

    def test_no_hover_scale_on_popup_items(self):
        """Hover may recolour a row; it must never resize an icon or a shape."""
        for name in ("PortRow.qml", "PortWatcherPopup.qml"):
            body = (REPO_ROOT / "modules/ii/bar/popups/portWatcher" / name).read_text()
            for line in body.splitlines():
                stripped = line.strip()
                if stripped.startswith("scale:"):
                    self.assertNotIn("Mouse", stripped, f"{name}: {stripped}")

    def test_bar_widgets_avoid_error_tokens(self):
        for name in ("PortWatcherWidget.qml", "ExpressivePortWatcher.qml"):
            body = (REPO_ROOT / "modules/ii/bar/widgets/portWatcher" / name).read_text()
            self.assertNotIn("colError", body, name)

    def test_hero_card_stays_in_one_colour_family(self):
        popup = (REPO_ROOT / "modules/ii/bar/popups/portWatcher/PortWatcherPopup.qml").read_text()
        start = popup.index("HeroCard {")
        end = popup.index("// ── The list")
        self.assertNotIn("colError", popup[start:end])


if __name__ == "__main__":
    unittest.main()
