"""Regression contracts for native Wayland objects created during shell startup."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
APP_STATS = (ROOT / "services/AppStats.qml").read_text(encoding="utf-8")


class NativeStartupContractTests(unittest.TestCase):
    def test_app_stats_waits_for_config_before_enabling_native_objects(self):
        self.assertIn(
            "readonly property bool enabled: Config.ready && (root.opts?.enable ?? true)",
            APP_STATS,
        )
        idle_monitor = APP_STATS.split("IdleMonitor {", 1)[1].split("}", 1)[0]
        self.assertIn("enabled: root.enabled && root.idleTimeout > 0", idle_monitor)


if __name__ == "__main__":
    unittest.main()
