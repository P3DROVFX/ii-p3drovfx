#!/usr/bin/env python3
"""Contract tests for System Health.

The helper and the shell meet at scripts/health/PROTOCOL.md; the assistant meets the
shell at the `health` tool domain. These pin the seams that break silently: a message
type the service never reads, a tool without a handler, a tool that could hand a crash
dump to a model, an island activity whose toggle cannot save, and an app folder the
module scanner never registers.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOTS = ROOT.parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


PROTOCOL = read("scripts/health/PROTOCOL.md")
SERVICE = read("services/HealthService.qml")
REGISTRY = read("services/ai/AiToolRegistry.qml")
AI = read("services/Ai.qml")
TOOLS = read("services/ai/AiTools.qml")
INTEGRATION = read("services/ai/integrations/AiHealthIntegration.qml")
ASSISTANT = read("modules/ii/health/components/HealthAssistant.qml")
CONFIG = read("modules/common/Config.qml")
FAMILY = read("panelFamilies/IllogicalImpulseFamily.qml")
ISLAND_REGISTRY = read("modules/ii/dynamicIsland/core/IslandRegistry.qml")
ISLAND_SOURCES = read("modules/ii/dynamicIsland/core/sources/IslandSources.qml")
HELPERS = read("scripts/rust-helpers.sh")

HEALTH_TOOLS = (
    "health_overview", "health_finding", "health_unit_log", "health_crash_trace",
    "health_journal_search", "health_package", "health_propose_fix",
)


class ProtocolTests(unittest.TestCase):
    def test_service_reads_every_stdout_message(self):
        stdout = PROTOCOL.split("## stdin")[0]
        kinds = set(re.findall(r'\{"t":"([a-z]+)"', stdout))
        self.assertTrue({"ready", "finding", "crashes", "reply"} <= kinds, kinds)
        for kind in kinds:
            self.assertIn(f'case "{kind}":', SERVICE, f"HealthService ignores '{kind}'")

    def test_state_dir_is_a_plain_path(self):
        self.assertRegex(SERVICE, r"stateDir: FileUtils\.trimFileProtocol\(")

    def test_no_request_returns_dump_bytes(self):
        self.assertIn("Nothing on stdin can return the bytes of a core dump", PROTOCOL)


class AssistantTests(unittest.TestCase):
    def test_every_tool_is_registered_and_handled(self):
        for tool in HEALTH_TOOLS:
            self.assertRegex(REGISTRY, rf'id: "{tool}",\s*\n\s*version: 1,\s*\n\s*domain: "health"', tool)
            self.assertIn(f'"{tool}": call =>', AI, f"no handler for {tool}")

    def test_tools_read_only_and_never_ask(self):
        for block in re.findall(r'\{\s*id: "health_[a-z_]+".*?needsSearch: false', REGISTRY, re.S):
            self.assertIn('kind: "localRead"', block)
            self.assertIn('network: "never"', block)
            self.assertIn('requiredServices: ["health"]', block)

    def test_health_service_availability_is_declared(self):
        self.assertIn("get health()", TOOLS)

    def test_crash_tool_drops_the_dump_path(self):
        self.assertIn("delete fields.COREDUMP_FILENAME", INTEGRATION)

    def test_proposals_run_only_from_a_click(self):
        # proposeFix only emits; runProposal is the single place that acts.
        propose = INTEGRATION.split("function proposeFix")[1].split("function runProposal")[0]
        for verb in ("HealthService.act(", "HealthService.cleanup(", "runInTerminal("):
            self.assertNotIn(verb, propose)
        self.assertIn("activeKey.length === 0", propose)

    def test_agent_is_lazy_and_scoped(self):
        self.assertRegex(ASSISTANT, r"Loader \{\s*id: taskLoader\s*active: false")
        self.assertIn('toolDomains: ["health"]', ASSISTANT)
        self.assertIn("HealthService.redactText", ASSISTANT)

    def test_assistant_obeys_its_switch_and_the_ai_policy(self):
        self.assertIn("health?.assistant?.enable", ASSISTANT)
        self.assertIn("SearchPanelRegistry.aiPolicyEnabled", ASSISTANT)


class WiringTests(unittest.TestCase):
    def test_app_folder_is_imported_so_the_scanner_registers_it(self):
        self.assertIn("import qs.modules.ii.health\n", FAMILY)
        self.assertIn('"../modules/ii/health/HealthApp.qml"', FAMILY)

    def test_island_activity_can_be_turned_off(self):
        self.assertIn('id: "health",', ISLAND_REGISTRY)
        self.assertIn("readonly property HealthSource health: HealthSource {}", ISLAND_SOURCES)
        self.assertIn("property bool disableHealth: false", CONFIG)
        self.assertRegex(CONFIG, r"property JsonObject health: JsonObject \{\s*property bool enable: true\s*\}")

    def test_helper_is_known_to_the_build_script(self):
        self.assertIn('"health_watch:health"', HELPERS)

    def test_keybind_and_window_rules(self):
        keybinds = (DOTS / "hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
        rules = (DOTS / "hypr/hyprland/rules.lua").read_text(encoding="utf-8")
        self.assertIn('"SUPER + CTRL + H", hl.dsp.global("quickshell:healthToggle")', keybinds)
        self.assertEqual(rules.count('"^(ii System Health)$"'), 2)


HEALTH_TEXT = read("services/HealthText.qml")
HEALTH_STYLE = read("modules/ii/health/components/HealthStyle.qml")
SHEET = read("modules/ii/health/components/FindingSheet.qml")
SETTINGS = read("modules/ii/health/tabs/HealthSettingsPage.qml")
HELPER_MAIN = read("scripts/health/health_watch_src/src/main.rs")
GUARD = ROOT / "scripts/quickshell-guard"
LAUNCHER = read("services/LauncherSearch.qml")

# Every finding kind the helper or the shell can raise.
KINDS = (
    "unit", "appLaunch", "restartLoop", "crash", "journal", "disk", "drive", "firmware", "security", "reboot",
    "deletedLibs", "pacnew", "timesync", "pressure", "thermal",
    "rebuild", "shellHelper", "shellMemory", "shellErrors", "slowBoot", "config",
    "battery", "peripheralBattery", "mce", "gpu", "oom", "edac", "radioFw", "usb", "aer", "overheat", "fan",
)


class FindingKindTests(unittest.TestCase):
    """A kind the app has no words, icon or page for shows up as "Something needs attention"."""

    def test_every_kind_is_documented(self):
        for kind in KINDS:
            if kind == "config":  # made by the shell, not the helper
                continue
            self.assertRegex(PROTOCOL, rf"`{kind}`", f"{kind} missing from PROTOCOL.md")

    def test_every_kind_has_a_title_and_a_detail(self):
        title = HEALTH_TEXT.split("function title(f)")[1].split("function seconds(")[0]
        detail = HEALTH_TEXT.split("function detail(f, now)")[1].split("function driveProblems(")[0]
        for kind in KINDS:
            self.assertIn(f'case "{kind}"', title, f"{kind}: no title")
            self.assertIn(f'case "{kind}"', detail, f"{kind}: no detail")

    def test_every_kind_has_an_icon(self):
        icons = HEALTH_STYLE.split("function severitySymbol(kind)")[1].split("default:")[0]
        for kind in KINDS:
            self.assertIn(f'case "{kind}":', icons, f"{kind}: no icon")

    def test_every_kind_opens_on_a_page(self):
        tabs = SERVICE.split("function openFinding(id)")[1].split("GlobalStates.openHealthApp")[0]
        hardware = re.search(r"hardwareKinds: \[([^\]]*)\]", SERVICE).group(1)
        for kind in KINDS:
            # Their own pages open them by kind; pressure and throttling live in the
            # Overview's vitals, so the Overview is their page.
            if kind in ("unit", "appLaunch", "restartLoop", "crash", "journal", "pressure", "thermal"):
                continue
            self.assertTrue(f'"{kind}"' in tabs or f'"{kind}"' in hardware, f"{kind}: openFinding falls back to the Overview")

    def test_new_kinds_have_sheet_rows(self):
        rows = SHEET.split("readonly property var rows:")[1].split("// ── Snooze")[0]
        for kind in KINDS[15:]:
            self.assertIn(f'case "{kind}"', rows, f"{kind}: its sheet has no facts")


class SourceTests(unittest.TestCase):
    """A source must exist in the helper, the service's launch list, Config and Settings."""

    def helper_sources(self):
        block = re.search(r"const ALL_SOURCES: \[&str; (\d+)\] = \[(.*?)\];", HELPER_MAIN, re.S)
        names = re.findall(r'"([a-zA-Z]+)"', block.group(2))
        self.assertEqual(len(names), int(block.group(1)))
        return names + ["shellLog"]

    def test_sources_line_up(self):
        launch = SERVICE.split("readonly property var launchArgs:")[1].split("return [")[0]
        config = CONFIG.split("property JsonObject sources: JsonObject {")[1].split("}")[0]
        for src in self.helper_sources():
            self.assertIn(f'"{src}"', launch, f"service never passes {src}")
            self.assertRegex(config, rf"property bool {src}: (true|false)", f"Config has no sources.{src}")
            self.assertIn(f'key: "{src}"', SETTINGS, f"Settings cannot switch {src}")
        self.assertRegex(config, r"property bool shellLog: false", "shellLog must be off by default")

    def test_every_flag_the_service_passes_is_parsed(self):
        args = SERVICE.split("readonly property var launchArgs:")[1].split("readonly property string launchKey")[0]
        for flag in re.findall(r'"(--[a-z-]+)"', args):
            self.assertIn(f'"{flag}"', HELPER_MAIN, f"the helper ignores {flag}")

    def test_new_messages_and_commands(self):
        stdin = PROTOCOL.split("## stdin")[1]
        for cmd in ("snooze", "unsnooze"):
            self.assertIn(f'"t":"{cmd}"', stdin)
            self.assertIn(f'"{cmd}"', HELPER_MAIN)
        self.assertIn('t: "snooze"', SERVICE)
        self.assertIn('t: "unsnooze"', SERVICE)


class GuardTests(unittest.TestCase):
    def test_scripts_exist_and_hook_paths_match(self):
        for name in ("qs-guard.sh", "qs-rebuild.sh", "quickshell-qt-check.sh", "install-hook.sh", "ii-quickshell-qt.hook"):
            self.assertTrue((GUARD / name).is_file(), name)
        hook = (GUARD / "ii-quickshell-qt.hook").read_text()
        installer = (GUARD / "install-hook.sh").read_text()
        exec_path = re.search(r"Exec = (\S+)", hook).group(1)
        self.assertIn(f"CHECK={exec_path}", installer)
        self.assertIn("quickshell-qt-check.sh", installer)
        # Root runs it: it must be installed root-owned, never run from the home dir.
        self.assertIn("-o root -g root", installer)
        for target in ("qt6-base", "qt6-declarative", "quickshell"):
            self.assertIn(f"Target = {target}\n", hook)

    def test_shell_starts_through_the_guard_everywhere(self):
        execs = (DOTS / "hypr/hyprland/execs.lua").read_text(encoding="utf-8")
        keybinds = (DOTS / "hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
        self.assertIn("quickshell-guard/qs-guard.sh", execs)
        self.assertIn("quickshell-guard/qs-guard.sh", keybinds)
        # The repository's setup script; a deployed config has none.
        setup = DOTS.parents[1] / "setup-ii-p3drovfx.sh"
        if setup.exists():
            self.assertIn("scripts/quickshell-guard/qs-guard.sh", setup.read_text(encoding="utf-8"))
        # With the guard missing, the plain start is still there.
        self.assertIn("exec qs -c $qsConfig", execs)

    def test_guard_settings_exist(self):
        self.assertRegex(CONFIG, r"property JsonObject guard: JsonObject \{\s*(//[^\n]*\s*)*property bool enable: true")
        self.assertIn("openTerminal", CONFIG)
        guard = (GUARD / "qs-guard.sh").read_text()
        self.assertIn(".health.guard.enable", guard)
        self.assertIn(".health.guard.openTerminal", guard)

    def test_hook_is_offered_once_the_app_is_installed(self):
        # Recommended on the Overview, whichever way the helper was built, and before
        # the dump access: one offer at a time.
        self.assertRegex(SERVICE, r"offerQtHook: root\.running\s*&& \(root\.qtHookStatus === \"missing\"")
        self.assertIn("&& !root.offerQtHook", SERVICE.split("offerDumpAccess:")[1].split("\n\n")[0])
        self.assertIn("property bool qtHookAsked: false", read("modules/common/Persistent.qml"))
        overview = read("modules/ii/health/tabs/OverviewTab.qml")
        self.assertIn("visible: HealthService.offerQtHook", overview)
        self.assertEqual(overview.count("QtHookOffer {"), 2)
        self.assertIn('Translation.tr("Recommended")', overview)
        # Settings shares the service's state rather than probing on its own.
        settings = read("modules/ii/health/tabs/HealthSettingsPage.qml")
        self.assertIn("HealthService.setQtHook(", settings)
        self.assertNotIn("install-hook.sh", settings)


class SurfaceTests(unittest.TestCase):
    def test_report_is_always_redacted(self):
        report = SERVICE.split("function buildReport()")[1].split("function copyReport(")[0]
        self.assertRegex(report, r"return root\.redactText\(L\.join")

    def test_launcher_and_keys_are_wired(self):
        self.assertIn("root.healthMatches(root.query)", LAUNCHER)
        app = read("modules/ii/health/HealthAppContent.qml")
        self.assertIn("handleNavKey", app)
        for page in ("OverviewTab", "ServicesTab"):
            self.assertIn("function handleNavKey(event)", read(f"modules/ii/health/tabs/{page}.qml"))

    def test_every_component_is_used(self):
        components = ROOT / "modules/ii/health/components"
        everything = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "modules/ii/health").rglob("*.qml"))
        for qml in components.glob("Health*.qml"):
            name = qml.stem
            if "pragma Singleton" in qml.read_text(encoding="utf-8"):
                continue
            uses = len(re.findall(rf"\b{name}\s*\{{", everything))
            self.assertGreater(uses, 0, f"{name} is never instantiated")

    def test_tooltips_show_in_the_app(self):
        # StyledToolTip stays hidden unless a listed overlay is open; testers found
        # every tooltip in the app missing while it was not on the list.
        tooltip = read("modules/common/widgets/StyledToolTip.qml")
        self.assertIn("GlobalStates.healthAppOpen", tooltip.split("readonly property bool sidebarOpen:")[1].split("\n")[0])

    def test_tooltips_on_plain_items_wait_for_hover(self):
        # StyledToolTip reads a parent without `hovered`/`containsMouse` as always
        # hovered: on a mark or a line it stayed on screen for good.
        for rel in ("modules/ii/health/tabs/CrashesTab.qml", "modules/ii/health/components/HealthAnswerMark.qml"):
            for block in read(rel).split("StyledToolTip {")[1:]:
                self.assertIn("extraVisibleCondition:", block.split("}")[0], rel)

    def test_lists_that_refresh_on_their_own_keep_their_rows(self):
        # A JS array model makes a Repeater rebuild every row, replaying the entrance
        # animation: the flicker testers saw. These lists change while on screen.
        for rel, key in (
            ("modules/ii/health/tabs/SystemTab.qml", "symbol"),
            ("modules/ii/health/components/HealthHardwareSection.qml", "key"),
            ("modules/ii/health/tabs/StorageTab.qml", "mount"),
            ("modules/ii/health/tabs/OverviewTab.qml", "id"),
            ("modules/ii/health/tabs/ServicesTab.qml", "id"),
            ("modules/ii/health/tabs/JournalTab.qml", "fp"),
            ("modules/ii/health/tabs/CrashesTab.qml", "exe"),
        ):
            self.assertIn(f'objectProp: "{key}"', read(rel), rel)

    def test_prebuilt_packages_get_their_libraries_installed(self):
        script = ROOT / "scripts/health/install-missing-libs.sh"
        self.assertTrue(script.is_file())
        text = script.read_text(encoding="utf-8")
        self.assertIn("pacman -Fy", text)
        self.assertIn("pacman -S --needed", text)
        self.assertIn("install-missing-libs.sh", SERVICE)

    def test_rebuild_cache_notices_a_rebuild_with_the_same_version(self):
        rebuild = read("scripts/health/health_watch_src/src/rebuild.rs")
        self.assertRegex(rebuild, r'cache_key = format!\("\{key\}@\{\}", install_ms\(&key\)\)')


class PlainWordsTests(unittest.TestCase):
    TEXT = read("services/HealthText.qml")

    @staticmethod
    def cases(body):
        return set(re.findall(r'case "([A-Za-z]+)":', body))

    def test_every_finding_kind_is_explained(self):
        titles = self.TEXT.split("function title(f)")[1].split("function verbLabel(")[0]
        explain = self.TEXT.split("function explain(f)")[1].split("function explainCrash(")[0]
        missing = self.cases(titles) - self.cases(explain)
        self.assertFalse(missing, f"kinds with a title but no plain-words explanation: {sorted(missing)}")

    def test_explanations_are_shown_where_findings_open(self):
        self.assertIn("HealthText.explain(root.f)", read("modules/ii/health/components/FindingSheet.qml"))
        self.assertIn("HealthText.explainCrash(stage.g)", read("modules/ii/health/tabs/CrashesTab.qml"))
        self.assertIn("HealthText.explainJournal(root.group)", read("modules/ii/health/tabs/JournalGroupSheet.qml"))


if __name__ == "__main__":
    unittest.main()
