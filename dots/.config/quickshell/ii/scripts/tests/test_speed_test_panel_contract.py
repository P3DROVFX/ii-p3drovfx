"""Contracts for the Internet Speed Test search panel in Quickshell."""

import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(relpath: str) -> str:
    return (ROOT / relpath).read_text(encoding="utf-8")


class SpeedTestPanelContractTests(unittest.TestCase):
    def test_search_panel_registry_registers_speed_test(self):
        """SearchPanelRegistry must declare speedTest with inputOwner: 'panel' and hosted: true."""
        registry = source("modules/common/SearchPanelRegistry.qml")
        self.assertIn('id: "speedTest"', registry)
        self.assertIn('source: "SpeedTestPanel.qml"', registry)
        self.assertIn('prefixKey: "speedTest"', registry)
        self.assertIn('inputOwner: "panel"', registry)
        self.assertIn("hosted: true", registry)
        self.assertIn('"speedtest"', registry)
        self.assertIn('"velocidade"', registry)
        self.assertIn('"network velocity"', registry)

        launcher = source("services/LauncherSearch.qml")
        self.assertIn('"network velocity"', launcher)
        self.assertIn('"speedTest"', launcher)

    def test_config_declares_speed_test_prefix_and_module(self):
        """Config.qml must include speedTest prefix '%', module flag, and default options."""
        config = source("modules/common/Config.qml")
        self.assertIn('property string speedTest: "%"', config)
        self.assertIn("property JsonObject speedTest: JsonObject {", config)
        self.assertIn('"search.speedTest.mode": ["both", "download", "upload"]', config)
        self.assertIn('"search.speedTest.unit": ["mbps", "mBps"]', config)

        modules_config = source("modules/settings/configs/widgets/LauncherModulesConfig.qml")
        self.assertIn("Config.options.search.modules.speedTest.enable", modules_config)
        self.assertIn('"Speed test"', modules_config)

    def test_speed_test_service_contract(self):
        """SpeedTestService.qml must expose singleton state, lifecycle functions, and format helpers."""
        service = source("services/SpeedTestService.qml")
        self.assertIn("pragma Singleton", service)
        self.assertIn("function startTest(", service)
        self.assertIn("function cancelTest(", service)
        self.assertIn("function formatSpeed(", service)
        self.assertIn("property var downloadSamples", service)
        self.assertIn("property var uploadSamples", service)
        self.assertIn("property var lastResult", service)
        self.assertIn("property string errorType", service)

    def test_speed_test_panel_contract(self):
        """SpeedTestPanel.qml must implement focusInput, handleEscape, keybinds, and Canvas chart."""
        panel = source("modules/ii/overview/SpeedTestPanel.qml")
        self.assertIn("function focusInput()", panel)
        self.assertIn("function handleEscape()", panel)
        self.assertIn("function handleKeyPress(", panel)
        self.assertIn("id: inputSink", panel)
        self.assertIn("SearchPanelScaffold {", panel)
        self.assertIn("Canvas {", panel)
        self.assertIn("Keys.onPressed:", panel)
        self.assertIn("Qt.Key_Space", panel)
        self.assertIn("Qt.Key_R", panel)
        self.assertIn("Qt.Key_C", panel)
        self.assertIn("Qt.Key_M", panel)
        self.assertIn("Qt.Key_U", panel)
        self.assertIn("No Internet Connection", panel)

        search_bar = source("modules/ii/overview/SearchBar.qml")
        self.assertIn("handleKeyPress", search_bar)

        widget = source("modules/ii/overview/SearchWidget.qml")
        self.assertIn("handleKeyPress", widget)

    def test_speed_test_runner_execution(self):
        """speedtest_runner.py must execute cleanly and emit valid NDJSON."""
        script_path = ROOT / "scripts/speedtest/speedtest_runner.py"
        self.assertTrue(script_path.exists())
        self.assertTrue(script_path.stat().st_mode & 0o111)

        cmd = ["python3", str(script_path), "--duration", "1", "--mode", "download"]
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
        self.assertEqual(proc.returncode, 0, f"Runner failed with error: {proc.stderr}")

        lines = [json.loads(line) for line in proc.stdout.strip().split("\n") if line.strip()]
        self.assertTrue(any(item.get("type") == "init" for item in lines))
        self.assertTrue(any(item.get("type") == "complete" for item in lines))


if __name__ == "__main__":
    unittest.main()
