#!/usr/bin/env python3
"""One declaration per tool, read by everything.

The schema sent to the model, the Tools page, the approval card and the
dispatcher used to each carry their own idea of what a tool is, and they could
disagree — `risk` was declared by hand next to a `kind` that implied a
different one, and "which tools may run" was re-derived in three places. These
tests pin the registry as the only place any of that is written down.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
TOOLS = (ROOT / "services" / "ai" / "AiTools.qml").read_text(encoding="utf-8")
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
POPOVER = (ROOT / "services" / "ai" / "blocks" / "AiToolsPopover.qml").read_text(encoding="utf-8")
ADVANCED = (ROOT / "modules" / "settings" / "configs" / "ai" / "AdvancedAiConfig.qml").read_text(encoding="utf-8")
PERMISSION_LIST = (ROOT / "services" / "ai" / "blocks" / "AiToolPermissionList.qml").read_text(encoding="utf-8")

KINDS = {"localRead", "explicitContextRead", "navigation", "externalRead",
         "localWrite", "externalWrite", "dangerous"}
NETWORKS = {"never", "optional", "required"}
SENSITIVITIES = {"none", "device", "personal", "secret"}
WRITING = {"localWrite", "externalWrite", "dangerous"}


def tool_blocks() -> dict:
    """Each raw definition, keyed by id, as its source text."""
    raw = REGISTRY.split("readonly property var rawDefinitions: [", 1)[1]
    raw = raw.split("\n    ]\n", 1)[0]
    blocks = {}
    for match in re.finditer(r'id: "([a-z_]+)",', raw):
        start = raw.rfind("{", 0, match.start())
        depth, i = 0, start
        while i < len(raw):
            if raw[i] == "{":
                depth += 1
            elif raw[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        blocks[match.group(1)] = raw[start:i + 1]
    return blocks


def field(block: str, name: str) -> str | None:
    match = re.search(rf"^\s*{name}:\s*(.+?),?$", block, re.M)
    return match.group(1).rstrip(",").strip() if match else None


BLOCKS = tool_blocks()


class DeclarationTests(unittest.TestCase):
    def test_every_tool_is_found(self):
        # If the parser above stops matching the file, every other test in
        # here would pass vacuously.
        self.assertGreaterEqual(len(BLOCKS), 9)
        for expected in ("settings_find", "set_shell_config", "web_search",
                         "fetch_url", "run_shell_command", "remember_fact"):
            self.assertIn(expected, BLOCKS)

    def test_each_tool_declares_the_metadata_the_broker_needs(self):
        required = ("version", "domain", "title", "summary", "icon", "kind",
                    "network", "sensitivity", "defaultApproval", "description",
                    "formats", "maxResultTokens")
        for tool_id, block in BLOCKS.items():
            for name in required:
                with self.subTest(tool=tool_id, field=name):
                    self.assertIsNotNone(field(block, name))

    def test_vocabularies_are_respected(self):
        for tool_id, block in BLOCKS.items():
            with self.subTest(tool=tool_id):
                self.assertIn(field(block, "kind").strip('"'), KINDS)
                self.assertIn(field(block, "network").strip('"'), NETWORKS)
                self.assertIn(field(block, "sensitivity").strip('"'), SENSITIVITIES)

    def test_risk_is_derived_never_declared(self):
        # Two classifications of the same thing is how they end up disagreeing.
        for tool_id, block in BLOCKS.items():
            with self.subTest(tool=tool_id):
                self.assertIsNone(field(block, "risk"))
        self.assertIn("function riskFor(kind: string)", REGISTRY)

    def test_ids_are_unique(self):
        declared = re.findall(r'id: "([a-z_]+)",', REGISTRY.split("rawDefinitions", 1)[1])
        self.assertEqual(len(declared), len(set(declared)))

    def test_a_duplicate_would_be_dropped_and_reported(self):
        built = REGISTRY.split("readonly property var definitions: {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("duplicate tool id ignored", built)

    def test_writing_tools_ask_first_by_default(self):
        for tool_id, block in BLOCKS.items():
            if field(block, "kind").strip('"') in WRITING:
                with self.subTest(tool=tool_id):
                    self.assertEqual(field(block, "defaultApproval"), '"ask"')

    def test_a_shell_can_never_be_granted_standing_permission(self):
        self.assertEqual(field(BLOCKS["run_shell_command"], "neverAutoApprove"), "true")
        self.assertEqual(field(BLOCKS["run_shell_command"], "kind"), '"dangerous"')

    def test_content_written_by_strangers_is_marked(self):
        # What the model reads back from a page or a command is data. The flag
        # is what later lets the broker wrap it as such.
        for tool_id in ("fetch_url", "run_shell_command"):
            with self.subTest(tool=tool_id):
                self.assertEqual(field(BLOCKS[tool_id], "untrusted"), "true")

    def test_the_retired_dump_is_declared_as_retired(self):
        block = BLOCKS["get_shell_config"]
        self.assertEqual(field(block, "formats"), "[]")
        self.assertIn("settings_search", field(block, "deprecatedBy"))

    def test_every_tool_has_a_token_budget(self):
        for tool_id, block in BLOCKS.items():
            with self.subTest(tool=tool_id):
                self.assertGreater(int(field(block, "maxResultTokens")), 0)


class SingleSourceTests(unittest.TestCase):
    def test_the_registry_is_a_singleton_and_runs_nothing(self):
        self.assertTrue(REGISTRY.startswith("pragma Singleton"))
        for forbidden in ("Process", "execDetached", "XMLHttpRequest"):
            with self.subTest(token=forbidden):
                self.assertNotIn(forbidden, REGISTRY)

    def test_the_per_chat_view_holds_no_definitions_of_its_own(self):
        self.assertNotIn("rawDefinitions", TOOLS)
        self.assertIn("readonly property var definitions: AiToolRegistry.definitions", TOOLS)
        # Schema generation lives in one place too.
        self.assertIn("AiToolRegistry.functionSchema", TOOLS)

    def test_availability_is_asked_not_re_derived(self):
        enabled = TOOLS.split("function enabledFor(format: string)", 1)[1].split("function functionSchema", 1)[0]
        self.assertIn("AiToolRegistry.availability(", enabled)
        # The old chain of hard-coded ids must be gone.
        for gone in ('def.id === "run_shell_command"', 'def.id === "web_search"', 'def.id === "fetch_url"'):
            with self.subTest(token=gone):
                self.assertNotIn(gone, TOOLS)

    def test_the_chat_supplies_its_real_situation(self):
        toolbox = AI_QML.split("readonly property AiTools toolbox: AiTools {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("online: root.onlineAllowed", toolbox)
        self.assertIn("modelCapabilities:", toolbox)

    def test_network_and_danger_are_separate_questions(self):
        # One flag used to mean both "reaches the network" and "is a shell",
        # which is why a local-only policy blocked a local command.
        availability = REGISTRY.split("function availability(", 1)[1].split("function defaultApprovalFor", 1)[0]
        self.assertIn('def.network === "required"', availability)
        self.assertIn('def.kind === "dangerous"', availability)


class UserFacingTests(unittest.TestCase):
    def test_the_tools_page_says_why_a_tool_is_unavailable(self):
        self.assertIn("AiToolPermissionList {", POPOVER)
        self.assertIn("Ai.toolbox.unavailableReason(", PERMISSION_LIST)
        self.assertIn("unavailableReason", PERMISSION_LIST)

    def test_neither_settings_surface_offers_always_for_a_shell(self):
        self.assertIn("AiToolPermissionList {", POPOVER)
        self.assertIn("AiToolPermissionList {", ADVANCED)
        self.assertIn("Ai.toolbox.permissionValuesFor(", PERMISSION_LIST)

    def test_a_stored_always_is_clamped_for_such_a_tool(self):
        # Config written before the rule existed must not keep granting it.
        permission = TOOLS.split("function permission(id: string)", 1)[1].split("function setPermission", 1)[0]
        self.assertIn("neverAutoApprove", permission)


if __name__ == "__main__":
    unittest.main()


class WebModePropertyBindingTests(unittest.TestCase):
    """`AiTools.webMode` has to exist for `Ai.qml`'s own binding to it.

    `AiToolRegistry.availability()` reads `context?.webMode` to gate
    `web_search`/`fetch_url`, and `Ai.qml` assigns `webMode: root.webMode`
    onto the `AiTools` it instantiates. The property itself was missing on
    `AiTools`, which is not a lint warning — it is "Cannot assign to
    non-existent property webMode" at runtime, and it took the whole `Ai`
    singleton down with it, exactly like the QtObject-default-property bugs
    elsewhere in this file's neighbours.
    """

    AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")

    def test_ai_tools_declares_the_property_ai_qml_assigns(self):
        self.assertIn("webMode: root.webMode", self.AI_QML)
        self.assertIn("property string webMode:", TOOLS)

    def test_the_context_the_registry_reads_actually_carries_it(self):
        context = TOOLS.split("readonly property var availabilityContext: ({", 1)[1].split("})", 1)[0]
        self.assertIn("webMode: root.webMode", context)


class ConversationPermissionScopeTests(unittest.TestCase):
    def test_tool_permissions_can_be_scoped_to_the_open_conversation(self):
        self.assertIn("property bool perConversationScope", TOOLS)
        self.assertIn("function permissionsForScope", TOOLS)
        self.assertIn("conversationPermissionsCommitted", TOOLS)
        self.assertIn("scopePerConversation", AI_QML)
        self.assertIn("sessionToolPermissions", AI_QML)
        self.assertIn('"toolPermissions": root.sessionToolPermissions', AI_QML)
        self.assertIn("scopePerConversation", ADVANCED)
