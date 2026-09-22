import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock
from contextlib import redirect_stdout


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "privacy_probe.py"
REPO_ROOT = SCRIPT_PATH.parent.parent
SPEC = importlib.util.spec_from_file_location("privacy_probe", SCRIPT_PATH)
privacy_probe = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(privacy_probe)


def pw_node(media_class, state="running", **props):
    base = {"media.class": media_class}
    base.update(props)
    return {"info": {"state": state, "props": base}}


def pw_dump(nodes):
    return SimpleNamespace(returncode=0, stdout=json.dumps(nodes), stderr="")


class PipewireClassificationTests(unittest.TestCase):
    def streams_for(self, nodes):
        with mock.patch.object(privacy_probe.subprocess, "run", return_value=pw_dump(nodes)):
            return privacy_probe.pipewire_streams()

    def test_audio_input_stream_is_a_microphone(self):
        streams = self.streams_for([
            pw_node("Stream/Input/Audio", **{"application.name": "Firefox"}),
        ])
        self.assertEqual(len(streams), 1)
        self.assertEqual(streams[0]["kind"], "microphone")
        self.assertEqual(streams[0]["app"], "Firefox")

    def test_video_input_with_the_screen_role_is_a_screen_capture(self):
        streams = self.streams_for([
            pw_node("Stream/Input/Video", **{"media.role": "Screen", "application.name": "obs"}),
        ])
        self.assertEqual(streams[0]["kind"], "screen")

    def test_video_input_without_the_screen_role_is_a_camera(self):
        streams = self.streams_for([
            pw_node("Stream/Input/Video", **{"application.name": "Cheese"}),
        ])
        self.assertEqual(streams[0]["kind"], "camera")

    def test_idle_streams_are_not_reported(self):
        self.assertEqual(
            self.streams_for([
                pw_node("Stream/Input/Audio", state="idle", **{"application.name": "Firefox"}),
            ]),
            [],
        )

    def test_output_streams_are_not_reported(self):
        self.assertEqual(
            self.streams_for([
                pw_node("Stream/Output/Audio", **{"application.name": "mpv"}),
            ]),
            [],
        )

    def test_the_shell_does_not_report_itself(self):
        self.assertEqual(
            self.streams_for([
                pw_node("Stream/Input/Audio", **{"application.name": "cava"}),
                pw_node("Stream/Input/Audio", **{"application.process.binary": "qs"}),
            ]),
            [],
        )

    def test_a_broken_pw_dump_is_survivable(self):
        with mock.patch.object(
            privacy_probe.subprocess,
            "run",
            return_value=SimpleNamespace(returncode=0, stdout="not json", stderr=""),
        ):
            self.assertEqual(privacy_probe.pipewire_streams(), [])

    def test_a_missing_pw_dump_is_survivable(self):
        with mock.patch.object(
            privacy_probe.subprocess, "run", side_effect=FileNotFoundError()
        ):
            self.assertEqual(privacy_probe.pipewire_streams(), [])


class CameraNodeTests(unittest.TestCase):
    """A temp file stands in for a capture node: the fd scan is the same code path,
    and unlike /dev/null nothing else in the process already holds it open."""

    def setUp(self):
        handle, self.node = tempfile.mkstemp(prefix="privacy-probe-node-")
        os.close(handle)
        self.addCleanup(os.unlink, self.node)

    def mine(self):
        users = privacy_probe.camera_users({self.node: "Fake webcam"})
        return [item for item in users if item["pid"] == os.getpid()]

    def test_an_open_handle_names_the_holding_process(self):
        handle = os.open(self.node, os.O_RDONLY)
        try:
            mine = self.mine()
        finally:
            os.close(handle)

        self.assertEqual(len(mine), 1)
        self.assertEqual(mine[0]["kind"], "camera")
        self.assertEqual(mine[0]["detail"], "Fake webcam")
        self.assertTrue(mine[0]["app"])

    def test_a_closed_handle_reports_nothing(self):
        self.assertEqual(self.mine(), [])

    def test_no_capture_nodes_means_no_proc_walk(self):
        self.assertEqual(privacy_probe.camera_users({}), [])


class LocationTests(unittest.TestCase):
    def busctl(self, stdout, returncode=0):
        return SimpleNamespace(returncode=returncode, stdout=stdout, stderr="")

    def test_in_use_reports_location_without_an_app(self):
        with mock.patch.object(privacy_probe.subprocess, "run", return_value=self.busctl("b true\n")):
            items = privacy_probe.location_in_use()
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["kind"], "location")
        self.assertEqual(items[0]["app"], "")

    def test_not_in_use_reports_nothing(self):
        with mock.patch.object(privacy_probe.subprocess, "run", return_value=self.busctl("b false\n")):
            self.assertEqual(privacy_probe.location_in_use(), [])

    def test_a_missing_geoclue_reports_nothing(self):
        with mock.patch.object(privacy_probe.subprocess, "run", return_value=self.busctl("", 1)):
            self.assertEqual(privacy_probe.location_in_use(), [])


class CollectTests(unittest.TestCase):
    def test_unwatched_kinds_never_reach_the_output(self):
        with mock.patch.object(privacy_probe, "pipewire_streams", return_value=[
            {"kind": "microphone", "app": "Firefox", "pid": 1, "detail": ""},
            {"kind": "screen", "app": "obs", "pid": 2, "detail": ""},
        ]):
            items = privacy_probe.collect({"microphone"}, {})
        self.assertEqual([item["kind"] for item in items], ["microphone"])

    def test_the_same_app_on_the_same_kind_is_reported_once(self):
        duplicate = {"kind": "camera", "app": "Firefox", "pid": 7, "detail": "webcam"}
        with mock.patch.object(privacy_probe, "pipewire_streams", return_value=[duplicate]):
            with mock.patch.object(privacy_probe, "camera_users", return_value=[dict(duplicate)]):
                items = privacy_probe.collect({"camera"}, {"/dev/video0": "webcam"})
        self.assertEqual(len(items), 1)

    def test_location_is_only_probed_when_watched(self):
        with mock.patch.object(privacy_probe, "pipewire_streams", return_value=[]):
            with mock.patch.object(privacy_probe, "location_in_use") as probe:
                privacy_probe.collect({"camera"}, {})
        probe.assert_not_called()


class PipewireMonitorTests(unittest.TestCase):
    """The monitor mirrors nodes from `pw-dump --monitor` output, fed here by hand."""

    @staticmethod
    def dump(objects):
        # pw-dump prints each array pretty, closing with "]" at column 0.
        return (json.dumps(objects, indent=2) + "\n").encode()

    @staticmethod
    def node(node_id, media_class, state="running", **props):
        obj = pw_node(media_class, state, **props)
        obj.update({"id": node_id, "type": "PipeWire:Interface:Node"})
        return obj

    def test_a_running_input_stream_is_reported_once_the_dump_is_read(self):
        monitor = privacy_probe.PipewireMonitor()
        payload = self.dump([self.node(5, "Stream/Input/Audio", **{"application.name": "Firefox"})])
        # Split mid-array: a partial array must not be parsed early.
        self.assertFalse(monitor._feed(payload[:20]))
        self.assertFalse(monitor.ready)
        self.assertTrue(monitor._feed(payload[20:]))
        self.assertTrue(monitor.ready)
        self.assertEqual([item["app"] for item in monitor.streams()], ["Firefox"])

    def test_an_update_replaces_the_node_and_a_removal_drops_it(self):
        monitor = privacy_probe.PipewireMonitor()
        monitor._feed(self.dump([self.node(5, "Stream/Input/Audio", **{"application.name": "obs"})]))
        monitor._feed(self.dump([self.node(5, "Stream/Input/Audio", state="suspended",
                                           **{"application.name": "obs"})]))
        self.assertEqual(monitor.streams(), [])
        monitor._feed(self.dump([self.node(5, "Stream/Input/Audio", **{"application.name": "obs"})]))
        self.assertEqual(len(monitor.streams()), 1)
        self.assertTrue(monitor._feed(self.dump([{"id": 5, "info": None}])))
        self.assertEqual(monitor.streams(), [])

    def test_non_node_objects_are_not_mirrored(self):
        monitor = privacy_probe.PipewireMonitor()
        monitor._feed(self.dump([
            {"id": 9, "type": "PipeWire:Interface:Port", "info": {"props": {}}},
            {"id": 38, "type": "PipeWire:Interface:Metadata", "metadata": []},
        ]))
        self.assertEqual(monitor.nodes, {})
        # A metadata change arrives with info null but keeps its type: not a removal.
        self.assertFalse(monitor._feed(self.dump([{"id": 38, "type": "PipeWire:Interface:Metadata",
                                                   "info": None}])))


class NodeWatchTests(unittest.TestCase):
    """Real inotify on a temp file standing in for a capture node."""

    def setUp(self):
        handle, self.node = tempfile.mkstemp(prefix="privacy-probe-node-")
        os.close(handle)
        self.addCleanup(os.unlink, self.node)
        self.watch = privacy_probe.NodeWatch()
        if self.watch.fd is None:
            self.skipTest("inotify unavailable")
        self.addCleanup(os.close, self.watch.fd)
        self.watch.watch({self.node: "Fake webcam"})
        self.watch.mark_walked()

    def test_every_node_watched_means_no_polling_fallback(self):
        self.assertTrue(self.watch.complete)
        self.watch.watch({self.node: "Fake webcam", "/nonexistent/video9": "gone"})
        self.assertFalse(self.watch.complete)

    def test_open_then_close_is_enumeration_not_use(self):
        os.close(os.open(self.node, os.O_RDONLY))
        self.assertTrue(self.watch.drain())
        self.assertFalse(self.watch.moved())

    def test_a_node_kept_open_moves_the_count_and_its_close_moves_it_back(self):
        handle = os.open(self.node, os.O_RDONLY)
        try:
            self.watch.drain()
            self.assertTrue(self.watch.moved())
            self.watch.mark_walked()
            self.assertFalse(self.watch.moved())
        finally:
            os.close(handle)
        self.watch.drain()
        self.assertTrue(self.watch.moved())

    def test_a_lost_event_queue_forces_a_walk(self):
        self.watch._count(privacy_probe.NodeWatch.EVENT.pack(-1, privacy_probe.NodeWatch.IN_Q_OVERFLOW, 0, 0))
        self.assertTrue(self.watch.moved())
        self.watch.mark_walked()
        self.assertFalse(self.watch.moved())


class OutputTests(unittest.TestCase):
    def test_once_emits_a_single_payload(self):
        output = io.StringIO()
        with mock.patch.object(privacy_probe, "video_capture_nodes", return_value={}):
            with mock.patch.object(privacy_probe, "collect", return_value=[]):
                with redirect_stdout(output):
                    exit_code = privacy_probe.main(["--once", "--kinds", "camera"])
        self.assertEqual(exit_code, 0)
        self.assertEqual(json.loads(output.getvalue()), {"ok": True, "items": []})


class QmlIntegrationContractTests(unittest.TestCase):
    def test_widget_is_registered(self):
        registry = (REPO_ROOT / "modules/common/BarComponentRegistry.qml").read_text()
        bar_component = (REPO_ROOT / "modules/ii/bar/BarComponent.qml").read_text()
        settings_registry = (REPO_ROOT / "modules/common/SettingsPageRegistry.qml").read_text()

        self.assertIn('id: "privacy_pill"', registry)
        self.assertIn('configPage: "PrivacyPillConfig.qml"', registry)
        self.assertIn('case "privacy_pill":', bar_component)
        self.assertIn("PrivacyPill {", bar_component)
        self.assertIn('"widgets/PrivacyPillConfig.qml"', settings_registry)

    def test_the_widget_has_a_single_design(self):
        widget_registry = (REPO_ROOT / "modules/ii/bar/registry/BarWidgetRegistry.qml").read_text()
        registry = (REPO_ROOT / "modules/common/BarComponentRegistry.qml").read_text()
        # No style key and no case in getStyle: one design, as asked.
        self.assertNotIn("privacy_pill", widget_registry)
        start = registry.index('id: "privacy_pill"')
        end = registry.index("}", registry.index("configPage", start))
        self.assertNotIn("styleConfigKey", registry[start:end])

    def test_pill_uses_the_tertiary_family_and_no_hover_state(self):
        widget = (REPO_ROOT / "modules/ii/bar/widgets/privacy/PrivacyPill.qml").read_text()
        self.assertIn("Appearance.colors.colTertiary", widget)
        self.assertIn("Appearance.colors.colOnTertiary", widget)
        # A privacy indicator must not react to the pointer.
        self.assertNotIn("containsMouse", widget)
        self.assertNotIn("hovered", widget.replace("hoverEnabled", "").replace("hoverTarget", ""))

    def test_pill_animates_size_from_a_single_driver(self):
        """Two Behaviors on the same geometry is what made it jump then settle."""
        widget = (REPO_ROOT / "modules/ii/bar/widgets/privacy/PrivacyPill.qml").read_text()
        self.assertIn("Behavior on progress", widget)
        self.assertIn("root.pillLength", widget)
        self.assertIn("root.pillThickness", widget)
        self.assertIn("root.dotSize", widget)
        self.assertEqual(widget.count("Behavior on implicitWidth"), 0)
        self.assertEqual(widget.count("Behavior on implicitHeight"), 0)
        # The icon still fades and scales in; that is appearance, not geometry.
        self.assertIn("Behavior on scale", widget)
        self.assertIn("Behavior on opacity", widget)

    def test_expanded_pill_matches_the_other_bar_widgets(self):
        widget = (REPO_ROOT / "modules/ii/bar/widgets/privacy/PrivacyPill.qml").read_text()
        self.assertIn("Appearance.sizes.verticalBarWidth - 8", widget)
        self.assertIn("Appearance.sizes.baseBarHeight - 8", widget)

    def test_pill_supports_the_vertical_bar(self):
        widget = (REPO_ROOT / "modules/ii/bar/widgets/privacy/PrivacyPill.qml").read_text()
        self.assertIn("property bool vertical", widget)
        self.assertIn("Appearance.sizes.verticalBarWidth", widget)

    def test_feature_surfaces_do_not_define_borders(self):
        qml_paths = [
            REPO_ROOT / "modules/ii/bar/widgets/privacy/PrivacyPill.qml",
            REPO_ROOT / "modules/ii/bar/popups/privacy/PrivacyPopup.qml",
            REPO_ROOT / "modules/settings/configs/widgets/PrivacyPillConfig.qml",
        ]
        combined = "\n".join(path.read_text() for path in qml_paths)
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)

    def test_settings_page_owns_every_trigger(self):
        page = (REPO_ROOT / "modules/settings/configs/widgets/PrivacyPillConfig.qml").read_text()
        for option in ("watchCamera", "watchMicrophone", "watchScreen", "watchLocation",
                       "expandDuration", "collapseToDot", "ignoreApps", "pollInterval"):
            self.assertIn(f"privacyPill.{option}", page)

    def test_location_stays_opt_in(self):
        config = (REPO_ROOT / "modules/common/Config.qml").read_text()
        self.assertIn("property bool watchLocation: false", config)


if __name__ == "__main__":
    unittest.main()
