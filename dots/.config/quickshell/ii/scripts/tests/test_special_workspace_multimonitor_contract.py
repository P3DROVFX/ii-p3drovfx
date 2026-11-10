"""Contract tests ensuring special workspace (scratchpad) effects are scoped per-monitor.

Prevents regression where opening a special workspace on one monitor causes
the background overview / zoom / blur effect to jump to other monitors when
the cursor moves between displays.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
GLOBAL_STATES = (ROOT / "GlobalStates.qml").read_text()
BG_ROOT = (ROOT / "modules/ii/background/BackgroundRoot.qml").read_text()


class SpecialWorkspaceMultiMonitorContractTests(unittest.TestCase):
    def test_global_overview_background_active_excludes_scratchpad(self):
        """Global overviewBackgroundActive must not trigger for scratchpadOpen.

        Scratchpad is per-monitor; global overviewBackgroundActive is combined
        with isMonitorFocused and would cause effects to bleed across screens.
        """
        self.assertNotIn("root.scratchpadOpen", GLOBAL_STATES.split("overviewBackgroundActive:")[1].split("}")[0])

    def test_background_root_scopes_scratchpad_to_own_monitor(self):
        """BackgroundRoot must evaluate special workspace presence for its own monitor."""
        self.assertIn("scratchpadOpenOnMonitor", BG_ROOT)
        self.assertIn("thisMonitorData?.specialWorkspace", BG_ROOT)
        self.assertIn("bgRoot.scratchpadOpenOnMonitor", BG_ROOT)


if __name__ == "__main__":
    unittest.main()
