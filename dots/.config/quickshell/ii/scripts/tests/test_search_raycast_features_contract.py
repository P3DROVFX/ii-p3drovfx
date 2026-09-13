"""Contracts for the Raycast-parity Search features (2026-09).

File content search, force quit, the calculator's conversions and history, GIF
search, grammar fixing, font browsing and sending files to a phone. Each test
pins the part that fails silently when it drifts: a flag, a guard, a key.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class RaycastFeatureContracts(unittest.TestCase):
    def setUp(self):
        self.launcher = source("services/LauncherSearch.qml")
        self.config = source("modules/common/Config.qml")
        self.registry = source("modules/common/SearchPanelRegistry.qml")

    def test_new_panels_are_registered_hosted_and_toggleable(self):
        for panel_id, file_name, module in (
            ("gifs", "GifsPanel.qml", "gifs"),
            ("grammar", "GrammarPanel.qml", "grammar"),
            ("fonts", "FontsPanel.qml", "fonts"),
        ):
            self.assertIn(f'{{ id: "{panel_id}", source: "{file_name}"', self.registry)
            self.assertTrue((ROOT / "modules/ii/overview" / file_name).exists())
            self.assertIn(f"property JsonObject {module}: JsonObject", self.config)
            self.assertIn(f"Config.options.search.modules.{module}.enable = checked",
                          source("modules/settings/configs/widgets/LauncherModulesConfig.qml"))
        # Grammar spends tokens; it must disappear with the AI policy.
        self.assertIn("(Config.options.search.modules.grammar?.enable ?? true) && Ai.enabled", self.registry)

    def test_content_search_is_prefix_only_streamed_and_capped(self):
        self.assertIn('property string fileContent: "\'"', self.config)
        self.assertIn("if (modules.fileContent) values.push(prefixes.fileContent);", self.launcher)
        # Streamed, stopped at the cap, and a query can never become a flag.
        self.assertIn("stdout: SplitParser {", self.launcher)
        self.assertIn("contentProc.running = false;\n                if (!contentPublishTimer.running)", self.launcher)
        self.assertIn('command.push("--", text, Config.options.search.fileSearchDirectory);', self.launcher)
        self.assertIn('"--fixed-strings"', self.launcher)
        # ":" is legal in paths; the unit separator is not.
        self.assertIn('"--field-match-separator", contentProc.fieldSeparator', self.launcher)
        self.assertIn('readonly property string fieldSeparator: "\x1f"', self.launcher)
        self.assertEqual(self.launcher.count("onContentResultsChanged: _scheduleResultsUpdate()"), 1)
        self.assertIn("return root.contentResults.map(match => root.createContentResult(match));", self.launcher)
        self.assertIn("/^(file:|fsearch:|fcontent:)/", source("modules/ii/overview/SearchWidget.qml"))

    def test_force_quit_confirms_and_kills_per_pid(self):
        self.assertIn("function forceQuitResults(queryText: string): var", self.launcher)
        self.assertIn('key = "process:app:" + app.pid', self.launcher.replace("const key", "key"))
        # Enter arms first; only the second press sends SIGKILL.
        start = self.launcher.index("function createForceQuitResult(app: var): var")
        body = self.launcher[start:start + 2500]
        self.assertLess(body.index("root.processConfirmKey = key;"), body.index('["kill", "-KILL", String(app.pid)]'))
        self.assertIn("keepOverviewOpen: !confirming", body)
        self.assertIn('name: Translation.tr("Force quit app")', self.launcher)

    def test_calculator_normalizes_converts_and_remembers(self):
        self.assertIn("function normalizeMathExpression(expr: string): string", self.launcher)
        # Without the "-" qalc answers "3 mi + 188 yd + 0.19 ft".
        self.assertIn('${namedFormat ? conversion[2] : "-"}${target}', self.launcher)
        self.assertIn('"$1% * "', self.launcher)
        # Rates are refreshed at most once a day, never on every keystroke.
        self.assertIn('command.push("-e");', self.launcher)
        self.assertIn("ratesAge > 24 * 60 * 60 * 1000", self.launcher)
        # "10 things to do" parses as a derived unit; it must not be shown.
        self.assertIn("if (!namesTarget)\n                        return;", self.launcher)
        self.assertIn("root.recordCalculation(root.mathExpression, root.mathResult);", self.launcher)
        persistent = source("modules/common/Persistent.qml")
        self.assertIn("property list<var> calculatorHistory: []", persistent)
        self.assertIn("property real exchangeRatesUpdatedAt: 0", persistent)
        self.assertIn("return root.calculatorHistoryResults();", self.launcher)

    def test_gif_panel_uses_klipy_and_keeps_the_key_out_of_config(self):
        panel = source("modules/ii/overview/GifsPanel.qml")
        self.assertIn("https://api.klipy.com/api/v1/${encodeURIComponent(root.apiKey)}/gifs/${endpoint}", panel)
        self.assertIn("KeyringStorage.keyringData?.apiKeys?.klipy", panel)
        self.assertIn('KeyringStorage.setNestedField(["apiKeys", "klipy"], key);', panel)
        # The pasted key must leave the field before it reaches search history.
        self.assertIn('LauncherSearch.query = "";', panel)
        self.assertIn("serial !== root.requestSerial", panel)
        self.assertIn('item.type !== "gif"', panel)
        gifs_start = self.config.index("property JsonObject gifs: JsonObject")
        gifs_block = self.config[gifs_start:self.config.index("property JsonObject grammar: JsonObject")]
        self.assertNotIn("apiKey", gifs_block)
        self.assertNotIn("tenor.googleapis.com", panel)

    def test_grammar_panel_is_single_turn_and_cancellable(self):
        panel = source("modules/ii/overview/GrammarPanel.qml")
        self.assertIn("AiTextTask {", panel)
        self.assertIn('scriptName: "search_grammar"', panel)
        self.assertIn("wl-paste --primary --no-newline --type text", panel)
        self.assertIn("task.cancel();", panel)
        self.assertNotIn("Ai.sendUserMessage", panel)

    def test_fonts_panel_lists_once_per_open(self):
        panel = source("modules/ii/overview/FontsPanel.qml")
        self.assertIn('command: ["fc-list", "--format", "%{family[0]}\\t%{style[0]}\\t%{file}\\n"]', panel)
        self.assertIn("font.family: fontRow.modelData.family", panel)

    def test_phone_share_actions_skip_folders_and_reach_the_dashboard(self):
        self.assertIn("function phoneShareActions(path: string, isDirectory: bool): var", self.launcher)
        self.assertIn("if (isDirectory || !(Config.options.search.modules.phoneShare?.enable ?? true))", self.launcher)
        self.assertIn("KdeConnectService.shareUrl(device.id, url);", self.launcher)
        self.assertIn("GlobalStates.localSendDialogPending = true;", self.launcher)
        self.assertIn("].concat(root.phoneShareActions(path, isDirectory))", self.launcher)
        dashboard = source("modules/ii/sidebarDashboard/SidebarDashboardContent.qml")
        self.assertIn("function consumeLocalSendRequest(): void", dashboard)
        # A second Component.onCompleted makes the whole panel family fail to load.
        self.assertEqual(dashboard.count("Component.onCompleted"), 1)
        self.assertIn("property bool localSendDialogPending: false", source("GlobalStates.qml"))


if __name__ == "__main__":
    unittest.main()
