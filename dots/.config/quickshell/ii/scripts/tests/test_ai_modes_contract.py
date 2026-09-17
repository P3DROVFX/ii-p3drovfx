#!/usr/bin/env python3
"""Contract tests for the Modes & Routines assistant integration.

Mirrors test_ai_notes_contract.py: the modes agent must be a registered
domain, wired through handlers and cards, scoped per run, and — the rule
that cost the most RAM — invisible to the Modes overlay until the user
actually asks for a generation.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


REGISTRY = read("services/ai/AiToolRegistry.qml")
AI = read("services/Ai.qml")
TOOLS = read("services/ai/AiTools.qml")
BROKER = read("services/ai/AiToolBroker.qml")
ADAPTER = read("services/ai/integrations/AiModesIntegration.qml")
MESSAGE = read("modules/ii/sidebarPolicies/aiChat/AiMessage.qml")
MODES = read("services/Modes.qml")
AGENT = read("modules/ii/modes/ModesAiAgent.qml")
BAR = read("modules/ii/modes/ModeAiBar.qml")
CONTENT = read("modules/ii/modes/ModesContent.qml")
MODES_DIR = ROOT / "modules" / "ii" / "modes"

MODE_TOOLS = (
    "modes_catalogue", "modes_list", "modes_get", "modes_history",
    "modes_create", "modes_update", "modes_start", "modes_stop", "modes_delete",
)


class RegistryTests(unittest.TestCase):
    def test_every_modes_tool_is_registered_in_its_domain(self):
        for tool_id in MODE_TOOLS:
            self.assertIn(f'id: "{tool_id}"', REGISTRY)
        block = REGISTRY[REGISTRY.index('id: "modes_catalogue"'):]
        self.assertEqual(block.count('domain: "modes"'), len(MODE_TOOLS))

    def test_reads_allow_writes_allow_but_delete_asks(self):
        # Authoring runs by itself (definitions are inert and open for
        # review); only the irreversible removal goes through approval.
        for tool_id in ("modes_create", "modes_update", "modes_start", "modes_stop"):
            block = REGISTRY[REGISTRY.index(f'id: "{tool_id}"'):]
            block = block[:block.index("},")]
            self.assertIn('kind: "localWrite"', block)
            self.assertIn('defaultApproval: "allow"', block)
            self.assertIn('requiredServices: ["modes"]', block)
        block = REGISTRY[REGISTRY.index('id: "modes_delete"'):]
        block = block[:block.index("},")]
        self.assertIn('defaultApproval: "ask"', block)

    def test_definitions_pass_through_the_broker_untouched(self):
        # checkArgs strips undeclared keys from objects that declare
        # properties; the definition must be an open object or every
        # per-trigger field is eaten before the handler sees it.
        block = REGISTRY[REGISTRY.index('id: "modes_create"'):]
        block = block[:block.index("},\n        {")]
        self.assertIn("definition: { type: \"object\"", block)


class DomainScopingTests(unittest.TestCase):
    def test_availability_honours_a_domain_filter(self):
        self.assertIn("context?.domains", REGISTRY)
        self.assertIn('"Not offered for this request"', REGISTRY)

    def test_wire_and_dispatch_carry_the_filter(self):
        self.assertIn("function wireTools(format: string, mode: string, domains = null): var {", TOOLS)
        self.assertIn("enabledFor(format: string, domains = null)", TOOLS)
        self.assertIn("function dispatch(call: var, message: var, hostOverride = null, toolDomains = null)", BROKER)
        self.assertIn("{ domains: record.toolDomains }", BROKER)
        # The chat path wires and dispatches with the submission's own domains.
        self.assertIn("root.toolbox.wireTools(model.api_format, toolOverride, pending?.toolDomains ?? null)", AI)
        self.assertIn("}, message, null, root.pendingSubmission?.toolDomains ?? null);", AI)

    def test_submit_accepts_a_task_prompt_and_domains(self):
        self.assertIn("systemPrompt: String(context?.systemPrompt ?? \"\").length > 0 ? String(context.systemPrompt) : root.systemPrompt,", AI)
        self.assertIn("toolDomains: Array.isArray(context?.toolDomains)", AI)


class LazyAiGraphTests(unittest.TestCase):
    """The performance contract: opening any Modes surface constructs no AI."""

    def test_only_the_agent_file_touches_ai(self):
        for path in sorted(MODES_DIR.glob("*.qml")):
            text = path.read_text(encoding="utf-8")
            if path.name == "ModesAiAgent.qml":
                continue
            self.assertNotIn("Ai.", text, f"{path.name} reads the Ai singleton eagerly")

    def test_the_agent_is_born_from_a_latch(self):
        self.assertIn("property bool aiTouched: false", CONTENT)
        self.assertIn("active: content.aiTouched", CONTENT)

    def test_service_availability_is_lazy(self):
        # Getters, not values: an eagerly evaluated map pulled EmailService,
        # NotesService and AiRagService into every construction of Ai.
        block = TOOLS[TOOLS.index("readonly property var serviceAvailability"):TOOLS.index("    })", TOOLS.index("readonly property var serviceAvailability"))]
        for name in ("gmail", "notes", "rag", "memory", "files", "ocr", "modes"):
            self.assertIn(f"get {name}()", block)
        self.assertIn("function isAvailable(): bool {", read("services/ai/integrations/AiGmailIntegration.qml"))
        self.assertIn("function isReady(): bool {", read("services/ai/integrations/AiRagIntegration.qml"))


class HandlerWiringTests(unittest.TestCase):
    def test_ai_wires_every_modes_tool(self):
        for name in ("toolModesCatalogue", "toolModesList", "toolModesGet", "toolModesHistory",
                     "toolModesCreate", "toolModesUpdate", "toolModesStart", "toolModesStop",
                     "toolModesDelete"):
            self.assertIn(name, AI)
        self.assertIn('"modes_delete": pending => root.deleteModesNow', AI)
        self.assertIn("function approveModesDelete", AI)
        self.assertIn("function rejectModesDelete", AI)

    def test_transcript_has_result_and_approval_cards(self):
        self.assertIn('case "modesResult"', MESSAGE)
        self.assertIn("AiModesResultCard", MESSAGE)
        self.assertIn('case "modesDeletePreview"', MESSAGE)
        self.assertIn("AiModesDeleteCard", MESSAGE)
        self.assertIn('"modesResult"', AI[AI.index("readonly property var resultCardKinds"):])
        self.assertIn('"modesDeletePreview"', AI[AI.index("readonly property var approvalCardKinds"):])


class AdapterTests(unittest.TestCase):
    def test_vocabulary_and_prompt_come_from_the_live_engine(self):
        self.assertIn("Modes.actions.registry", ADAPTER)
        self.assertIn("ModeSchema.TRIGGER_TYPES", ADAPTER)
        self.assertIn("function agentPrompt", ADAPTER)
        self.assertIn("modes_catalogue", ADAPTER)

    def test_create_refuses_unknown_types_instead_of_degrading(self):
        self.assertIn("unknown trigger type", ADAPTER)
        self.assertIn("unknown action type", ADAPTER)
        self.assertIn("is not available on this machine", ADAPTER)

    def test_writes_announce_themselves(self):
        self.assertIn("signal created(string kind, string id, string name, string sessionId)", ADAPTER)
        self.assertIn("Modes.addMode(", ADAPTER)
        self.assertIn("Modes.addRoutine(", ADAPTER)

    def test_palette_and_icon_lists_mirror_the_surfaces(self):
        # One truth, mechanically pinned: the catalogue's allowed values must
        # equal what the editor's own pickers offer.
        modeui = read("modules/ii/modes/ModeUi.qml")
        ui_keys = re.search(r"paletteKeys: \[([^\]]*)\]", modeui).group(1)
        adapter_keys = re.search(r"paletteKeys: \[([^\]]*)\]", ADAPTER).group(1)
        norm = lambda s: [x for x in re.findall(r'"[^"]*"', s)]
        self.assertEqual(norm(ui_keys), norm(adapter_keys))
        icon_picker = read("modules/ii/modes/IconPicker.qml")
        picker_shelf = re.search(r"shelf: \[([\s\S]*?)\]", icon_picker).group(1)
        adapter_shelf = re.search(r"iconShelf: \[([\s\S]*?)\]", ADAPTER).group(1)
        self.assertEqual(norm(picker_shelf), norm(adapter_shelf))


class RevealTests(unittest.TestCase):
    def test_engine_offers_the_open_and_reveal_seam(self):
        self.assertIn("function openAndReveal(kind, id)", MODES)
        self.assertIn("signal revealRequested(var request)", MODES)
        self.assertIn("revealRequest", MODES)

    def test_agent_routes_creation_and_verdict_back_to_the_overlay(self):
        self.assertIn("Ai.submit(String(text ?? \"\")", AGENT)
        self.assertIn("toolDomains: [\"modes\"]", AGENT)
        self.assertIn("onRunFinished", AGENT)
        self.assertIn("onCreated", AGENT)
        # The bar never decides its own phase: the overlay owns it.
        self.assertNotIn("root.phase =", BAR)


if __name__ == "__main__":
    unittest.main()
