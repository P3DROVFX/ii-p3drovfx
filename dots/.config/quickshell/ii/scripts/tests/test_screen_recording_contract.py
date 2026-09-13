"""Contracts for the wf-recorder and region-selector integration.

These tests intentionally inspect the command boundary rather than starting a
Wayland capture.  They keep the regression coverage safe for headless CI and
avoid touching the user's active Quickshell session.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
RECORD = (ROOT / "scripts/videos/record.sh").read_text()
SCREENSHOT_ACTION = (ROOT / "modules/common/utils/ScreenshotAction.qml").read_text()
REGION_SELECTION = (ROOT / "modules/ii/regionSelector/RegionSelection.qml").read_text()
WAFFLE_REGION_SELECTION = (ROOT / "modules/waffle/screenSnip/WRegionSelectionPanel.qml").read_text()
QUALITY_JS = (ROOT / "modules/common/functions/recordingQuality.js").read_text()
KEYPRESS_MONITOR = (ROOT / "scripts/videos/keypress_monitor.py").read_text()


class ScreenRecordingContractTests(unittest.TestCase):
    def test_audio_prefers_the_default_sink_monitor(self):
        body = RECORD.split("getaudiooutput() {", 1)[1].split("\n}\ngetactivemonitor", 1)[0]
        self.assertIn("pactl get-default-sink", body)
        self.assertIn('default_monitor="${default_sink}.monitor"', body)
        self.assertIn("pactl list short sources", body)
        self.assertLess(body.index("default_monitor"), body.index("$2 ~ /\\.monitor$/"))

    def test_region_command_has_a_logical_global_geometry_channel(self):
        self.assertIn("recordGeometry = null", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.x : x", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.y : y", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.width : width", SCREENSHOT_ACTION)
        self.assertIn("recordGeometry ? recordGeometry.height : height", SCREENSHOT_ACTION)
        self.assertIn("x: rx + root.monitorOffsetX", REGION_SELECTION)
        self.assertIn("y: ry + root.monitorOffsetY", REGION_SELECTION)
        self.assertIn("x: dragArea.selectionX + root.monitorOffsetX", WAFFLE_REGION_SELECTION)
        self.assertIn("y: dragArea.selectionY + root.monitorOffsetY", WAFFLE_REGION_SELECTION)

    def test_region_recording_does_not_force_the_focused_output(self):
        region_body = RECORD.split("# If a manual region was provided", 1)[1]
        region_body = region_body.split("# Post recording action", 1)[0]
        self.assertNotIn('wf-recorder -o "$(getactivemonitor)"', region_body)

    def test_constant_frame_rate_is_the_only_thing_that_passes_r(self):
        """`-r` *is* wf-recorder's CFR switch, so the variable mode must omit it
        entirely rather than pass a rate nobody honours."""
        body = RECORD.split("CODEC_OPTS=(\"-c\" \"$CODEC\")", 1)[1].split("apply_quality", 1)[0]
        self.assertIn('if [[ "$REC_FRAME_SYNC" != "vfr" ]]; then', body)
        self.assertIn('CODEC_OPTS+=("-r" "$REC_FRAMERATE")', body)
        self.assertNotIn('CODEC_OPTS=("-c" "$CODEC" "-r"', RECORD)

    def test_vaapi_scales_with_the_vaapi_scaler(self):
        """VAAPI frames are on the GPU by the time the filter runs; the CPU
        `scale` filter would never see them."""
        body = RECORD.split("apply_quality() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn('if [[ "$codec" == *_vaapi ]]', body)
        self.assertIn("scale_vaapi=w=${box_w}:h=${box_h}", body)
        self.assertIn("scale=${box_w}:${box_h}", body)
        self.assertIn("force_original_aspect_ratio=decrease", body)
        self.assertIn("force_divisible_by=2", body)
        # A smaller source must be left alone rather than blown up to the box.
        self.assertIn("(( src_w > box_w || src_h > box_h ))", body)

    def test_bitrate_is_derived_and_never_asked_for(self):
        self.assertNotIn("screenRecord.bitrate", RECORD)
        self.assertIn('jq -r ".screenRecord.quality"', RECORD)
        self.assertIn('jq -r ".screenRecord.resolution"', RECORD)
        self.assertIn('jq -r ".screenRecord.frameSync"', RECORD)

    def test_quality_constants_match_between_the_script_and_the_settings_page(self):
        """The settings page shows the bitrate the script will pick, so the two
        copies of the formula have to agree."""
        for name, value in (
            ("QUALITY_BPP_LOW", "0.05"),
            ("QUALITY_BPP_BALANCED", "0.09"),
            ("QUALITY_BPP_HIGH", "0.15"),
            ("BITRATE_FLOOR_MBPS", "1.5"),
            ("BITRATE_CEILING_MBPS", "80"),
        ):
            self.assertIn(f'{name}="{value}"', RECORD, f"{name} missing from record.sh")
            self.assertIn(f"var {name} = {value};", QUALITY_JS, f"{name} missing from recordingQuality.js")

        for preset, box in (
            ("2160p", "3840 2160"),
            ("1440p", "2560 1440"),
            ("1080p", "1920 1080"),
            ("720p", "1280 720"),
            ("480p", "854 480"),
        ):
            self.assertIn(f'{preset}) echo "{box}" ;;', RECORD)
            self.assertIn(f'"{preset}": [{box.replace(" ", ", ")}]', QUALITY_JS)

    def test_keypress_monitor_never_persists_what_it_reads(self):
        """The reader is a keylogger by construction; it may only ever write to
        the pipe the shell holds open."""
        self.assertNotIn("open(", KEYPRESS_MONITOR.replace("os.open(", ""))
        self.assertIn("def emit(", KEYPRESS_MONITOR)
        self.assertIn("print(json.dumps(payload", KEYPRESS_MONITOR)

    def test_keypress_monitor_translates_through_the_active_layout(self):
        """evdev reports physical keys, so a US table would mislabel every
        letter on an AZERTY keyboard."""
        self.assertIn("keymap_new_from_names", KEYPRESS_MONITOR)
        self.assertIn("--layout", KEYPRESS_MONITOR)
        # +8 is the offset between an evdev keycode and an xkb one.
        self.assertIn("code + 8", KEYPRESS_MONITOR)

    def test_recording_does_not_open_the_screenshot_overlay(self):
        snip_body = REGION_SELECTION.split("function snip()", 1)[1]
        overlay_body = snip_body.split("// Trigger screenshot overlay", 1)[1]
        overlay_body = overlay_body.split("root.dismiss();", 1)[0]
        self.assertIn("const isRecording", REGION_SELECTION)
        self.assertIn("if (!isRecording &&", overlay_body)


if __name__ == "__main__":
    unittest.main()
