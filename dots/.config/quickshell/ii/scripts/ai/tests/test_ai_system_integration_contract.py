#!/usr/bin/env python3
"""Read-only system tools must stay bounded and sourced from shell services."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
SYSTEM = (ROOT / "services/ai/integrations/AiSystemIntegration.qml").read_text(encoding="utf-8")
RESOURCES = (ROOT / "services/ResourceUsage.qml").read_text(encoding="utf-8")
MPRIS = (ROOT / "services/MprisController.qml").read_text(encoding="utf-8")


class AiSystemIntegrationContractTests(unittest.TestCase):
    def test_registry_exposes_the_planned_read_only_system_tools(self):
        for tool in (
            'id: "system_get_status"',
            'id: "system_health"',
            'id: "keybinds_search"',
        ):
            with self.subTest(tool=tool):
                self.assertIn(tool, REGISTRY)
                block = REGISTRY.split(tool, 1)[1].split('\n        },', 1)[0]
                self.assertIn('kind: "localRead"', block)
                self.assertIn('network: "never"', block)

    def test_adapter_uses_services_not_shell_or_network(self):
        for token in (
            "Battery.available",
            "Network.wifiStatus",
            "Audio.muted",
            "Notifications.effectiveSilent",
            "MprisController.isPlaying",
            "ResourceUsage.topProcesses",
            "HyprlandKeybinds.defaultKeybinds",
            "HyprlandKeybinds.userKeybinds",
            "function status()",
            "function health()",
            "function keybinds(",
        ):
            with self.subTest(token=token):
                self.assertIn(token, SYSTEM)
        for forbidden in ("\n    Process {", "execDetached", "XMLHttpRequest", "hyprctl", "Network.networkName", "Network.ipAddress"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, SYSTEM)

    def test_process_sampling_is_bounded_before_the_adapter_reads_it(self):
        self.assertIn("property list<var> topProcesses: []", RESOURCES)
        # `comm` only (no argv), the caller's own processes, and the parser
        # stops after five rows before anything is published.
        self.assertIn(r'command: ["bash", "-c", "ps -u \"$(id -u)\" -o pid=,comm=,pcpu=,pmem= --sort=-pcpu"]', RESOURCES)
        self.assertIn("if (processes.length >= 5)\n                break;", RESOURCES)
        self.assertIn(".slice(0, root.maximumTopProcesses)", SYSTEM)
        self.assertIn("readonly property int maximumTopProcesses: 5", SYSTEM)

    def test_ai_routes_each_tool_to_the_read_only_adapter(self):
        for token in (
            "readonly property AiSystemIntegration systemIntegration",
            '"system_get_status": call => root.toolSystemGetStatus(call)',
            '"system_health": call => root.toolSystemHealth(call)',
            '"keybinds_search": call => root.toolKeybindsSearch(call)',
            "root.systemIntegration.status()",
            "root.systemIntegration.health()",
            "root.systemIntegration.keybinds(",
        ):
            with self.subTest(token=token):
                self.assertIn(token, AI)

    def test_media_service_tolerates_a_transient_null_player(self):
        self.assertIn("applicationPlayers.find(player => player && player.isPlaying)", MPRIS)


if __name__ == "__main__":
    unittest.main()
