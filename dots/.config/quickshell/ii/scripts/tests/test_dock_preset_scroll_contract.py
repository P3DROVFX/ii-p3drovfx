"""Contract test for switching dock presets via mouse scroll and smooth transition animations."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DOCK_PRESETS_SERVICE = (ROOT / "services/DockPresets.qml").read_text(encoding="utf-8")
DOCK_PRESETS_MANAGER = (ROOT / "modules/settings/configs/widgets/DockPresetsManager.qml").read_text(encoding="utf-8")
DOCK_CONFIG = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
DOCK_CONTENT = (ROOT / "modules/ii/dock/DockContent.qml").read_text(encoding="utf-8")
DOCK = (ROOT / "modules/ii/dock/Dock.qml").read_text(encoding="utf-8")
LOCAL_PREFERENCES = (ROOT / "modules/common/LocalPreferences.qml").read_text(encoding="utf-8")
PRESETS_HELPER = (ROOT / "scripts/presets_helper.py").read_text(encoding="utf-8")


class DockPresetScrollContractTests(unittest.TestCase):
    def test_dock_presets_service_contract(self):
        """DockPresets singleton manages presets list, wheel scroll, and transition animations."""
        self.assertIn("pragma Singleton", DOCK_PRESETS_SERVICE)
        self.assertIn("canSwitchPresets", DOCK_PRESETS_SERVICE)
        self.assertIn("presetsList", DOCK_PRESETS_SERVICE)
        self.assertIn("handleWheelScroll", DOCK_PRESETS_SERVICE)
        self.assertIn("cyclePreset", DOCK_PRESETS_SERVICE)
        self.assertIn("applyPreset", DOCK_PRESETS_SERVICE)
        self.assertIn("saveCurrentAsPreset", DOCK_PRESETS_SERVICE)
        self.assertIn("deletePreset", DOCK_PRESETS_SERVICE)
        # Condition: only switch if > 1 presets exist and enabled
        self.assertIn("presetsList.length > 1", DOCK_PRESETS_SERVICE)

    def test_dock_presets_animation_and_magnification_suspension(self):
        """DockPresets manages dipProgress, isSwitchingPreset, and magnificationSuspended."""
        self.assertIn("property bool isSwitchingPreset: false", DOCK_PRESETS_SERVICE)
        self.assertIn("property bool magnificationSuspended: false", DOCK_PRESETS_SERVICE)
        self.assertIn("property real dipProgress: 0.0", DOCK_PRESETS_SERVICE)
        self.assertIn("SequentialAnimation", DOCK_PRESETS_SERVICE)
        self.assertIn("dipProgress", DOCK_PRESETS_SERVICE)
        self.assertIn("magResumeTimer", DOCK_PRESETS_SERVICE)
        self.assertIn("animationSafetyTimer", DOCK_PRESETS_SERVICE)

    def test_config_dock_switch_presets_option(self):
        """Config.options.dock has switchPresetsOnScroll boolean property."""
        self.assertIn("property bool switchPresetsOnScroll: true", DOCK_CONFIG)

    def test_dock_presets_manager_has_toggle_switch(self):
        """DockPresetsManager has ConfigSwitch to toggle scroll preset switching."""
        self.assertIn("ConfigSwitch", DOCK_PRESETS_MANAGER)
        self.assertIn("switchPresetsOnScroll", DOCK_PRESETS_MANAGER)

    def test_dock_content_intercepts_wheel_for_preset_switching(self):
        """DockContent passes wheel scroll to DockPresets when canSwitchPresets is true."""
        self.assertIn("DockPresets.canSwitchPresets", DOCK_CONTENT)
        self.assertIn("DockPresets.handleWheelScroll", DOCK_CONTENT)

    def test_dock_content_suspends_magnification_cleanly(self):
        """DockContent suspends magnification during preset switch and provides immediate reset."""
        self.assertIn("!DockPresets.magnificationSuspended", DOCK_CONTENT)
        self.assertIn("function resetMagnificationImmediate()", DOCK_CONTENT)
        self.assertIn("magnificationStrength = 0", DOCK_CONTENT)
        self.assertIn("_lensSettled = true", DOCK_CONTENT)

    def test_dock_background_has_wheel_handler_and_dip_animation(self):
        """Dock.qml applies dipOffset, suspends hover, and disables margin behaviors during animation."""
        self.assertIn("dockWheelPresetSwitcher", DOCK)
        self.assertIn("DockPresets.canSwitchPresets", DOCK)
        self.assertIn("DockPresets.handleWheelScroll", DOCK)
        self.assertIn("dipOffset", DOCK)
        self.assertIn("DockPresets.dipProgress", DOCK)
        self.assertIn("enabled: !DockPresets.isSwitchingPreset", DOCK)
        self.assertIn("enabled: !DockPresets.magnificationSuspended", DOCK)
        self.assertIn("resetMagnificationImmediate()", DOCK)
        self.assertIn("DockPresets.isSwitchingPreset", DOCK)

    def test_local_preferences_and_blacklist_protection(self):
        """switchPresetsOnScroll is protected from being wiped by global theme presets."""
        self.assertIn('"dock.switchPresetsOnScroll"', LOCAL_PREFERENCES)
        self.assertIn('"switchPresetsOnScroll"', PRESETS_HELPER)


if __name__ == "__main__":
    unittest.main()
