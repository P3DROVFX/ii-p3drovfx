"""Contract tests for the dashboard button's animated icons.

These assert design decisions no linter can see: that every icon is built from
separately addressable parts, that movement — not a pulse — is the primary
animation, and that the settings page fires the same cues production does.
"""

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ICONS = REPO_ROOT / "modules/ii/bar/widgets/dashboard/icons"
BUTTON = REPO_ROOT / "modules/ii/bar/widgets/dashboard/ExpressiveDashboardPanelButton.qml"
CONFIG = REPO_ROOT / "modules/settings/configs/widgets/DashboardButtonConfig.qml"
CUES = REPO_ROOT / "services/DashboardIconCues.qml"

ICON_FILES = {
    "wifi": ICONS / "WifiIcon.qml",
    "bluetooth": ICONS / "BluetoothIcon.qml",
    "volume": ICONS / "VolumeIcon.qml",
    "mic": ICONS / "MicIcon.qml",
    "notification": ICONS / "BellIcon.qml",
    "caffeine": ICONS / "CoffeeIcon.qml",
    "vpn": ICONS / "VpnKeyIcon.qml",
    "tailscale": ICONS / "TailscaleIcon.qml",
    "pomodoro": ICONS / "TimerIcon.qml",
    "stopwatch": ICONS / "StopwatchIcon.qml",
    "easyeffects": ICONS / "EqualizerIcon.qml",
    "dns": ICONS / "EncryptedDnsIcon.qml",
    "warp": ICONS / "CloudLockIcon.qml",
    "gamemode": ICONS / "GamepadIcon.qml",
    "songrec": ICONS / "MusicRecognitionIcon.qml",
    "alarm": ICONS / "AlarmIcon.qml",
    "countdown": ICONS / "HourglassIcon.qml",
}
DRIVER = ICONS / "DashboardIconDriver.qml"
DEFAULT_BUTTONS = [
    REPO_ROOT / "modules/ii/bar/widgets/dashboard/DashboardPanelButton.qml",
    REPO_ROOT / "modules/ii/bar/widgets/dashboard/VerticalDashboardPanelButton.qml",
]


class IconStructureTests(unittest.TestCase):
    def test_every_icon_exists_and_extends_the_shared_base(self):
        self.assertTrue((ICONS / "AnimatedIcon.qml").is_file())
        for channel, path in ICON_FILES.items():
            self.assertTrue(path.is_file(), channel)
            self.assertIn("AnimatedIcon {", path.read_text(), channel)

    def test_icons_are_built_from_separately_addressable_parts(self):
        """Part-level movement is only possible if the parts are separate items."""
        minimum_parts = {"wifi": 4, "bluetooth": 5, "volume": 4, "mic": 3, "notification": 3,
                         "caffeine": 4, "vpn": 2, "tailscale": 1,
                         "pomodoro": 3, "stopwatch": 4, "easyeffects": 1,
                         "dns": 3, "warp": 2, "gamemode": 1, "songrec": 3,
                         "alarm": 4, "countdown": 6}
        for channel, path in ICON_FILES.items():
            body = path.read_text()
            parts = len(re.findall(r"^\s{4}(?:Shape|\w+) \{\s*$", body, re.M))
            parts += len(re.findall(r"^\s+id: \w+\n\s+(?:rest|tipY|cx):", body, re.M))
            self.assertGreaterEqual(parts, minimum_parts[channel], f"{channel}: {parts} parts")

    def test_every_icon_answers_the_cue_bus(self):
        for channel, path in ICON_FILES.items():
            body = path.read_text()
            self.assertIn(f'cueChannel: "{channel}"', body)
            self.assertIn("function play(cue: string): void", body)

    def test_the_base_routes_the_bus_to_play(self):
        base = (ICONS / "AnimatedIcon.qml").read_text()
        self.assertIn("target: DashboardIconCues", base)
        self.assertIn("root.play(name)", base)

    def test_movement_is_the_primary_animation(self):
        """Each icon must animate real geometry, not only opacity and scale."""
        moved = {
            "wifi": ["radius", "lift"],
            "bluetooth": ["rotation", "cx", "slashProgress"],
            "volume": ["radius", "x", "slashProgress"],
            "mic": ["capsuleDrop", "slashProgress"],
            "notification": ["hoodAngle", "clapperAngle", "clapperDrop"],
            "caffeine": ["liquidTop", "cupLift"],
            "vpn": ["keyShift", "keyTurn"],
            "tailscale": ["lean"],
            "pomodoro": ["handAngle", "crownDrop"],
            "stopwatch": ["handAngle", "knobPress", "crownDrop"],
            "easyeffects": ["half", "offset"],
            "dns": ["shackleLift", "slashProgress"],
            "warp": ["shackleLift", "cloudDrift"],
            "gamemode": ["push"],
            "songrec": ["waveTravel", "noteBob"],
            "alarm": ["bodyRock", "bellSwing", "handJolt", "legDrop"],
            "countdown": ["topSandAmount", "bottomSandAmount", "grainY", "bodyTurn"],
        }
        for channel, properties in moved.items():
            body = ICON_FILES[channel].read_text()
            for prop in properties:
                self.assertIn(f'property: "{prop}"', body, f"{channel}.{prop}")

    def test_no_icon_animates_by_scale_alone(self):
        for channel, path in ICON_FILES.items():
            body = path.read_text()
            animated = set(re.findall(r'property: "(\w+)"', body))
            self.assertTrue(
                animated - {"scale", "opacity"},
                f"{channel} animates nothing but scale/opacity",
            )

    def test_repeater_items_are_not_bound_as_animation_targets(self):
        """itemAt() returns null while a Repeater is still constructing.

        A NumberAnimation target binding cannot observe that imperative lookup,
        so it remains null and the animation silently does nothing.  Repeater
        items may be reached later from a Timer/ScriptAction, but declarative
        animation targets must be stable ids.
        """
        for channel in ("easyeffects", "gamemode"):
            body = ICON_FILES[channel].read_text()
            self.assertNotRegex(
                body,
                r"target:\s*root\.\w+At\(",
                f"{channel} binds an animation to an itemAt() lookup",
            )


class RestStateTests(unittest.TestCase):
    """Icons must draw the current state correctly without an animation running,
    otherwise a bar that starts up muted looks unmuted until something changes."""

    def test_state_properties_feed_apply_rest(self):
        # property declaration -> a token applyRest() must mention to prove the
        # resting picture is derived from it (directly or through a helper).
        expected = {
            "bluetooth": [("property bool connected", "root.connected"),
                          ("property bool poweredOff", "root.poweredOff")],
            "caffeine": [("property bool active", "root.active")],
            "vpn": [("property bool connected", "root.connected")],
            "tailscale": [("property bool connected", "root.connected")],
            "easyeffects": [("property bool active", "root.active")],
            "dns": [("property bool active", "root.active")],
            "warp": [("property bool connected", "root.connected")],
            "gamemode": [("property bool active", "root.active")],
            "songrec": [("property bool listening", "root.listening")],
            "alarm": [("property bool scheduled", "root.scheduled"),
                      ("property bool ringing", "root.ringing")],
            "countdown": [("property bool running", "root.running"),
                          ("property bool paused", "root.paused"),
                          ("property bool finished", "root.finished")],
            "mic": [("property bool muted", "root.muted")],
            "notification": [("property bool silent", "root.silent")],
            "wifi": [("property int bars", "root.restOpacity")],
            "volume": [("property int waves", "root.waves")],
        }
        for channel, pairs in expected.items():
            body = ICON_FILES[channel].read_text()
            self.assertIn("function applyRest(): void", body, channel)
            rest_body = body.split("function applyRest")[1].split("\n    }")[0]
            for declaration, token in pairs:
                self.assertIn(declaration, body, channel)
                self.assertIn(token, rest_body, f"{channel}: {token}")

    def test_muting_dims_the_glyph(self):
        """The user asked for the bluetooth treatment everywhere: mute and
        silence drop the glyph's opacity, they do not only add a slash."""
        for channel in ("bluetooth", "mic", "notification"):
            body = ICON_FILES[channel].read_text()
            self.assertIn("readonly property real dimmed", body, channel)
            self.assertIn('property: "opacity"', body, channel)

    def test_the_bar_binds_every_rest_state(self):
        body = BUTTON.read_text()
        for binding in ("connected: BluetoothStatus.connected",
                        "poweredOff: !BluetoothStatus.enabled",
                        "muted: iconDriver.sourceMuted",
                        "silent: Notifications.silent"):
            self.assertIn(binding, body)


class GlyphFidelityTests(unittest.TestCase):
    """The silhouette has to stay recognisably the Material Symbol."""

    def test_wifi_arcs_are_spread_apart(self):
        body = ICON_FILES["wifi"].read_text()
        # Only the three instantiated arcs, not the component's own default.
        radii = [float(m) for m in re.findall(r"SignalArc \{\s*id: arc\d\s*rest: ([\d.]+)", body)]
        self.assertEqual(len(radii), 3, radii)
        gaps = [round(b - a, 2) for a, b in zip(radii, radii[1:])]
        stroke = float(re.search(r"stroke: ([\d.]+)", body).group(1))
        for gap in gaps:
            # Visual gap is the radius step minus the stroke sitting in it.
            self.assertGreater(gap - stroke, 2.0, f"arcs {gap - stroke:.2f} apart")

    def test_wifi_never_drops_an_arc_entirely(self):
        """Unlit arcs stay as ghosts; a fan missing prongs is a different icon."""
        body = ICON_FILES["wifi"].read_text()
        self.assertIn("readonly property real ghost", body)
        self.assertNotIn('property: "opacity"; to: 0;', body)
        for block in ("disconnectAnim", "disableAnim"):
            section = body.split(f"id: {block}")[1].split("ScriptAction")[0]
            self.assertNotIn('property: "opacity"; to: 0 ', section)
            self.assertIn("root.ghost", section)

    def test_wifi_searching_repeats_connected_motion_with_opacity_wave(self):
        """Searching must move every arc, not read as an opacity-only pulse."""
        body = ICON_FILES["wifi"].read_text()
        searching = body.split("id: searchAnim")[1].split("// ── Connected")[0]

        for arc in ("arc1", "arc2", "arc3"):
            self.assertIn(f'target: {arc}; property: "radius"', searching)
            self.assertIn(f'target: {arc}; property: "lift"', searching)
            self.assertIn(f'target: {arc}; property: "opacity"', searching)

        self.assertIn('target: dot; property: "lift"', searching)
        self.assertGreaterEqual(searching.count("Easing.OutBack"), 4)

    def test_volume_near_wave_matches_the_material_segment(self):
        """Material draws a circular segment 2.5 wide by 7.95 tall — a full
        half-disc there is twice as wide and reads as a blob."""
        import math
        body = ICON_FILES["volume"].read_text()
        near = body.split("component NearWave")[1].split("component FarWave")[0]
        self.assertIn("fillColor: root.color", near)
        self.assertIn('strokeColor: "transparent"', near)
        radius = float(re.search(r"property real rest: ([\d.]+)", near).group(1))
        half_sweep = float(re.search(r"sweepAngle: (\d+)", near).group(1)) / 2
        self.assertLess(half_sweep, 90, "a 180° sweep is a half-disc, not a segment")
        width = radius - radius * math.cos(math.radians(half_sweep))
        height = 2 * radius * math.sin(math.radians(half_sweep))
        self.assertLess(width / height, 0.40, f"segment ratio {width / height:.2f}")

    def test_volume_far_wave_stands_taller_than_the_cone(self):
        """The proportion the Material glyph uses; small waves read as marks."""
        import math
        body = ICON_FILES["volume"].read_text()
        far = body.split("component FarWave")[1]
        far_r = float(re.search(r"property real rest: ([\d.]+)", far).group(1))
        far_stroke = float(re.search(r"strokeWidth: ([\d.]+)", far).group(1))
        half_sweep = float(re.search(r"sweepAngle: (\d+)", far).group(1)) / 2
        far_height = 2 * far_r * math.sin(math.radians(half_sweep)) + far_stroke
        cone = re.search(r'path: "M [\d.]+ [\d.]+ H [\d.]+ L [\d.]+ ([\d.]+) V ([\d.]+)', body)
        cone_stroke = float(re.search(r"strokeWidth: ([\d.]+)", body.split("id: body")[1]).group(1))
        cone_height = float(cone.group(2)) - float(cone.group(1)) + cone_stroke
        self.assertGreater(far_height, cone_height, f"{far_height:.1f} vs cone {cone_height:.1f}")

    def test_volume_waves_clear_the_cone_and_each_other(self):
        """A sub-pixel gap is not a gap: antialiasing fuses the shapes together
        and the icon reads as one lumpy blob."""
        import math
        body = ICON_FILES["volume"].read_text()
        near = body.split("component NearWave")[1].split("component FarWave")[0]
        far = body.split("component FarWave")[1].split("readonly property bool muted")[0]

        def num(pattern, text):
            return float(re.search(pattern, text).group(1))

        n_cx = num(r"property real centerX: ([\d.]+)", near)
        n_r = num(r"property real rest: ([\d.]+)", near)
        n_half = num(r"sweepAngle: (\d+)", near) / 2
        f_cx = num(r"property real centerX: ([\d.]+)", far)
        f_r = num(r"property real rest: ([\d.]+)", far)
        f_w = num(r"strokeWidth: ([\d.]+)", far)
        cone_right = num(r'path: "M [\d.]+ [\d.]+ H [\d.]+ L ([\d.]+)', body)
        cone_stroke = num(r"strokeWidth: ([\d.]+)", body.split("id: body")[1])

        chord = n_cx + n_r * math.cos(math.radians(n_half))
        self.assertGreater(chord - (cone_right + cone_stroke / 2), 1.5, "cone to near wave")
        self.assertGreater((f_cx + f_r - f_w / 2) - (n_cx + n_r), 1.5, "near wave to far wave")
        self.assertLess(f_cx + f_r + f_w / 2, 23, "far wave runs off the grid")

    def test_volume_body_recoils_horizontally(self):
        """The cone gives against the waves, the way the Wi-Fi dot does."""
        body = ICON_FILES["volume"].read_text()
        for cue in ("upAnim", "downAnim", "muteAnim", "unmuteAnim"):
            section = body.split(f"id: {cue}")[1].split("SequentialAnimation {\n        id:")[0]
            self.assertIn('target: body; property: "x"', section, cue)

    def test_volume_mute_only_shrinks_and_dims(self):
        """Mute pulls the waves in and quiets the glyph; it must not fling them
        outward, and the slash has to stay at full strength."""
        body = ICON_FILES["volume"].read_text()
        mute = body.split("id: muteAnim")[1].split("// ── Unmute")[0]
        self.assertIn("to: wave1.shrunk", mute)
        self.assertIn("to: wave2.shrunk", mute)
        self.assertNotIn("rest +", mute)
        for part in ("body", "wave1", "wave2"):
            self.assertIn(f'target: {part}; property: "opacity"; to: root.dimmed', mute)
        self.assertNotIn('property: "slashProgress"; to: root.dimmed', mute)

    def test_no_animation_ends_by_teleporting_a_part(self):
        """A ScriptAction that snaps geometry home is a visible jump, not a rest."""
        body = ICON_FILES["wifi"].read_text()
        self.assertNotIn("ScriptAction", body)

    def test_tailscale_uses_the_brand_dot_grid(self):
        body = ICON_FILES["tailscale"].read_text()
        self.assertIn("model: 9", body)
        self.assertIn("solidDots", body)

    def test_easyeffects_moves_bar_centres_not_only_their_heights(self):
        """A richer equalizer cue needs vertical travel through the row;
        changing only line length still reads as a static resize."""
        body = ICON_FILES["easyeffects"].read_text()
        self.assertIn("property real offset", body)
        for cue in ("onAnim", "offAnim"):
            section = body.split(f"id: {cue}")[1]
            self.assertGreaterEqual(
                section.count('property: "offset"'),
                5,
                f"{cue} does not move every bar centre",
            )

    def test_music_cast_keeps_note_and_broadcast_parts_separate(self):
        body = ICON_FILES["songrec"].read_text()
        for part in ("id: noteHead", "id: noteStem", "id: nearWave", "id: farWave"):
            self.assertIn(part, body)
        self.assertIn("property real waveTravel", body)
        self.assertIn('property: "waveTravel"', body)

    def test_music_listening_moves_the_note_as_well_as_the_broadcasts(self):
        """Listening should feel alive through articulated glyph motion, not
        only through fading/travelling effects around a static note."""
        body = ICON_FILES["songrec"].read_text()
        listening = body.split("id: listenAnim")[1].split("// ── Found")[0]
        self.assertIn("property real noteSway", body)
        self.assertIn('target: root; property: "noteSway"', listening)
        self.assertGreaterEqual(body.count("root.noteSway"), 3)

    def test_gamepad_arms_do_not_stack_translucent_fills_at_the_centre(self):
        """Overlapping arms compound alpha while dimmed and expose their
        internal strokes, making the off glyph look like a bright border."""
        body = ICON_FILES["gamemode"].read_text()
        self.assertIn("id: center", body)
        self.assertNotIn("strokeColor: root.color", body)
        self.assertIn('strokeColor: "transparent"', body)

    def test_alarm_uses_a_filled_body_and_filled_feet(self):
        body = ICON_FILES["alarm"].read_text()
        dial = body.split("id: dial")[1].split("id: hands")[0]
        foot = body.split("component Foot")[1].split("function applyRest")[0]
        self.assertIn("fillColor: root.color", dial)
        self.assertIn('strokeColor: "transparent"', dial)
        self.assertNotIn("strokeWidth:", dial)
        self.assertIn("fillColor: root.color", foot)
        self.assertIn('strokeColor: "transparent"', foot)
        self.assertNotIn("strokeWidth:", foot)

    def test_countdown_hourglass_has_separate_filled_frame_and_sand(self):
        body = ICON_FILES["countdown"].read_text()
        for part in ("id: topCap", "id: bottomCap", "id: leftRail", "id: rightRail",
                     "id: topSand", "id: bottomSand", "id: fallingGrain"):
            self.assertIn(part, body)
        self.assertGreaterEqual(body.count("fillColor: root.color"), 7)
        self.assertNotIn("strokeColor: root.color", body)

    def test_countdown_one_shots_resume_flow_when_another_timer_is_running(self):
        body = ICON_FILES["countdown"].read_text()
        for animation, next_animation in (("pauseAnim", "resumeAnim"),
                                          ("completeAnim", "removedAnim"),
                                          ("removedAnim", None)):
            section = body.split(f"id: {animation}")[1]
            if next_animation is not None:
                section = section.split(f"id: {next_animation}")[0]
            self.assertIn("root.beginFlow()", section, animation)

    def test_warp_shackle_motion_reaches_the_drawn_shackle(self):
        body = ICON_FILES["warp"].read_text()
        self.assertRegex(
            body,
            re.compile(r"id: shackle.*?transform: Translate \{ y: -root\.shackleLift", re.S),
        )


class BluetoothShapeTests(unittest.TestCase):
    def test_turning_off_does_not_pull_the_rune_apart(self):
        """Rotating the wings far enough to separate them reads as the glyph
        breaking, not as bluetooth switching off."""
        body = ICON_FILES["bluetooth"].read_text()
        disable = body.split("id: disableAnim")[1].split("SequentialAnimation {\n        id:")[0]
        self.assertNotIn('property: "rotation"', disable)

    def test_connected_dots_survive_the_animation(self):
        """They are the indicator Material draws, not a one-off flourish."""
        body = ICON_FILES["bluetooth"].read_text()
        connect = body.split("id: connectAnim")[1].split("// ── Disconnected")[0]
        self.assertIn("to: 24 - root.dotRestX", connect)
        self.assertIn("to: root.dotRestX", connect)
        self.assertNotIn('property: "opacity"; to: 0', connect)


class CueCatalogTests(unittest.TestCase):
    def setUp(self):
        self.catalog = CUES.read_text()

    def test_the_catalog_covers_every_channel(self):
        for channel in ICON_FILES:
            self.assertIn(f'channel: "{channel}"', self.catalog)

    def test_every_advertised_cue_is_handled_by_its_icon(self):
        blocks = re.findall(r'channel: "(\w+)",.*?cues: \[(.*?)\]', self.catalog, re.S)
        self.assertEqual(len(blocks), len(ICON_FILES))
        for channel, block in blocks:
            body = ICON_FILES[channel].read_text()
            for name in re.findall(r'name: "(\w+)"', block):
                self.assertIn(f'case "{name}":', body, f"{channel} cannot play {name}")


class WiringTests(unittest.TestCase):
    def test_the_bar_button_uses_the_animated_icons(self):
        body = BUTTON.read_text()
        self.assertIn("import qs.modules.ii.bar.widgets.dashboard.icons", body)
        for component in ("VolumeIcon {", "MicIcon {", "WifiIcon {", "BluetoothIcon {", "BellWithBadge {"):
            self.assertIn(component, body)

    def test_the_driver_waits_before_playing_anything(self):
        """Otherwise every binding's first evaluation plays an animation at boot."""
        body = DRIVER.read_text()
        self.assertIn("property bool driverReady: false", body)
        self.assertIn("root.driverReady = true", body)
        self.assertIn("root.refreshCountdownState(false)", body)
        for handler in ("onWifiCueChanged", "onBluetoothCueChanged", "onSinkMutedChanged",
                        "onSinkVolumeChanged", "onSourceMutedChanged",
                        "onNotificationsSilentChanged", "onUnreadCountChanged"):
            self.assertIn(handler, body)
        # Every handler that can play a cue must be gated by it.
        for handler in re.findall(r"on\w+Changed: \{(.*?)\n    \}", body, re.S):
            if ".play(" in handler:
                self.assertIn("driverReady", handler, handler[:80])

    def test_all_three_dashboard_buttons_use_the_animated_icons(self):
        """The default and vertical buttons were still on MaterialSymbol."""
        for path in DEFAULT_BUTTONS + [BUTTON]:
            body = path.read_text()
            self.assertIn("import qs.modules.ii.bar.widgets.dashboard.icons", body, path.name)
            self.assertIn("DashboardIconDriver {", body, path.name)
            # These seven exist on every button; the quick-toggle indicators
            # (pomodoro, stopwatch, EasyEffects, DNS, game mode, SongRec) are
            # expressive-only, so they are not asserted here.
            for component in ("WifiIcon {", "BluetoothIcon {", "VolumeIcon {",
                              "MicIcon {", "CoffeeIcon {", "VpnKeyIcon {", "TailscaleIcon {",
                              "HourglassIcon {"):
                self.assertIn(component, body, f"{path.name}: {component}")

    def test_quick_toggle_indicators_reach_the_expressive_button(self):
        body = BUTTON.read_text()
        for component in ("TimerIcon {", "StopwatchIcon {", "EqualizerIcon {",
                          "EncryptedDnsIcon {", "GamepadIcon {", "MusicRecognitionIcon {"):
            self.assertIn(component, body, component)
        driver = DRIVER.read_text()
        for state in ("TimerService.pomodoroRunning", "TimerService.stopwatchRunning",
                      "EasyEffects.active", "DnsOverTls.active", "SongRec.running"):
            self.assertIn(state, driver, state)

    def test_alarm_state_reaches_all_dashboard_buttons(self):
        driver = DRIVER.read_text()
        # Persistent/GlobalStates are already alive in every shell generation.
        # Lazily instantiating AlarmService from three incubating bar buttons
        # raced singleton finalization during hot reload in Quickshell 0.3.
        self.assertIn("Persistent.states.alarms", driver)
        self.assertIn("GlobalStates.alarmRinging", driver)
        self.assertNotIn("AlarmService.", driver)
        self.assertIn("id: alarmHideTimer", driver)
        for cue in ('play("open")', 'play("ringing")', 'play("stopped")',
                    'play("removed")'):
            self.assertIn(cue, driver)
        for path in DEFAULT_BUTTONS + [BUTTON]:
            body = path.read_text()
            self.assertIn("AlarmIcon {", body, path.name)
            self.assertIn("alarmIcon: alarmIcon", body, path.name)
            self.assertIn("iconDriver.alarmVisible", body, path.name)

    def test_countdown_state_reaches_all_dashboard_buttons(self):
        driver = DRIVER.read_text()
        self.assertIn("TimerService.countdowns", driver)
        self.assertIn("id: countdownHideTimer", driver)
        for cue in ('play("start")', 'play("pause")', 'play("resume")',
                    'play("complete")', 'play("removed")'):
            self.assertIn(cue, driver)
        for path in DEFAULT_BUTTONS + [BUTTON]:
            body = path.read_text()
            self.assertIn("HourglassIcon {", body, path.name)
            self.assertIn("countdownIcon: countdownIcon", body, path.name)
            self.assertIn("iconDriver.countdownVisible", body, path.name)
            self.assertIn("Config.options.bar.dashboardButton.showCountdowns", body, path.name)

        settings = CONFIG.read_text()
        self.assertIn("Config.options.bar.dashboardButton.showCountdowns", settings)
        self.assertIn("return countdownPreview", settings)

    def test_no_dashboard_button_reimplements_the_driver(self):
        """One mapping from state to cue, shared by all three buttons."""
        for path in DEFAULT_BUTTONS + [BUTTON]:
            body = path.read_text()
            self.assertNotIn("driverReady", body, path.name)

    def test_settings_page_fires_the_same_bus(self):
        body = CONFIG.read_text()
        self.assertIn("model: DashboardIconCues.catalog", body)
        self.assertIn("DashboardIconCues.play(", body)
        # The preview uses the production components, not a copy.
        self.assertIn("import qs.modules.ii.bar.widgets.dashboard.icons", body)

    def test_settings_catalog_repeaters_only_model_integer_counts(self):
        """VariantMap/List model roles collide in this Qt/Quickshell build."""
        body = CONFIG.read_text()
        self.assertNotIn("required property var modelData", body)
        self.assertIn("model: DashboardIconCues.catalog.length", body)
        self.assertIn("model: cueRow.cueGroup.cues.length", body)
        self.assertIn("DashboardIconCues.catalog[cueRow.index]", body)
        self.assertIn("cueRow.cueGroup.cues[cueButton.index]", body)

    def test_feature_surfaces_do_not_define_borders(self):
        combined = "\n".join(
            path.read_text()
            for path in list(ICON_FILES.values()) + [ICONS / "AnimatedIcon.qml", DRIVER, CONFIG]
        )
        self.assertNotIn("border.width", combined)
        self.assertNotIn("border.color", combined)


if __name__ == "__main__":
    unittest.main()
