"""Contracts for the first remediation wave of the AI Settings audit."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
AI_SETTINGS = ROOT / "modules/settings/configs/AiAssistantConfig.qml"
AI_PAGES = ROOT / "modules/settings/configs/ai"
CONFIG = ROOT / "modules/common/Config.qml"
ENTRY_BUTTON = ROOT / "modules/common/widgets/SubPageEntryButton.qml"
ADVANCED = ROOT / "modules/settings/configs/ai/AdvancedAiConfig.qml"
POPOVER = ROOT / "services/ai/blocks/AiToolsPopover.qml"
PERMISSION_LIST = ROOT / "services/ai/blocks/AiToolPermissionList.qml"


def ai_page(name: str) -> str:
    """One of the AI sub-pages the main page routes to via Qt.resolvedUrl."""
    return (AI_PAGES / name).read_text(encoding="utf-8")


class SubPageEntryButtonTests(unittest.TestCase):
    def test_ai_entries_use_the_shared_navigation_component(self):
        source = AI_SETTINGS.read_text(encoding="utf-8")

        # One entry per subject, each a compact ConfigSubpageRow that opens a
        # route under ai/. The settings regroup replaced SubPageEntryButton on
        # this page and split every section into its own sub-page.
        self.assertEqual(source.count("ConfigSubpageRow {"), 11)
        self.assertEqual(source.count('Qt.resolvedUrl("ai/'), 11)
        self.assertNotIn("SubPageEntryButton {", source)
        self.assertNotIn("component ConfigSubpageRow:", source)
        self.assertNotIn("component SubPageEntryButton:", source)

    def test_shared_entry_is_neutral_and_keeps_colour_on_its_icon(self):
        source = ENTRY_BUTTON.read_text(encoding="utf-8")

        self.assertIn("colBackground: Appearance.colors.colSurfaceContainerHigh", source)
        self.assertIn("colBackgroundHover: Appearance.colors.colSurfaceContainerHighest", source)
        self.assertIn("color: root.entryAccent", source)
        self.assertNotIn("colTertiaryContainer", source)


class ToolPermissionGroupingTests(unittest.TestCase):
    def test_both_surfaces_use_the_same_grouped_permission_list(self):
        advanced = ADVANCED.read_text(encoding="utf-8")
        popover = POPOVER.read_text(encoding="utf-8")

        self.assertIn("AiToolPermissionList {", advanced)
        self.assertIn("AiToolPermissionList {", popover)
        self.assertNotIn("component PermissionSegments:", popover)

    def test_permission_list_groups_registry_domains_and_supports_batch_changes(self):
        source = PERMISSION_LIST.read_text(encoding="utf-8")

        self.assertIn("AiToolRegistry.domains", source)
        self.assertIn("function toolsForDomain", source)
        self.assertIn("function setDomainPermission", source)
        self.assertIn("Ai.toolbox.setPermission", source)
        self.assertIn("collapsible: true", source)
        self.assertIn("Ai.toolbox.unavailableReason", source)

    def test_permission_accordions_keep_a_compact_group_spacing(self):
        source = PERMISSION_LIST.read_text(encoding="utf-8")

        self.assertIn("Appearance.rounding.unsharpenmore", source)
        self.assertNotIn('spacing: root.density === "compact" ? Appearance.rounding.small : Appearance.rounding.normal', source)

    def test_permission_accordion_state_does_not_write_back_unchanged_values(self):
        source = PERMISSION_LIST.read_text(encoding="utf-8")

        self.assertIn("if (root.expandedFor(domain) === expanded)", source)
        self.assertIn("return;", source)


class ContextAndNotificationSettingsTests(unittest.TestCase):
    def test_settings_expose_the_existing_context_controls(self):
        main = AI_SETTINGS.read_text(encoding="utf-8")
        source = ai_page("AiContextMemoryConfig.qml")

        self.assertIn('Qt.resolvedUrl("ai/AiContextMemoryConfig.qml")', main)
        for setting in (
            "Config.options.ai.context.manage",
            "Config.options.ai.context.summarise",
            "Config.options.ai.context.reserveTokens",
            "Config.options.ai.extractDocuments",
            "Config.options.ai.memory.limit",
        ):
            self.assertIn(setting, source)


class TrashRetentionTests(unittest.TestCase):
    def test_retention_is_persisted_and_the_session_store_enforces_it(self):
        config = CONFIG.read_text(encoding="utf-8")
        sessions = (ROOT / "services/ai/AiSessions.qml").read_text(encoding="utf-8")

        self.assertIn("property int retentionDays: 30", config)
        self.assertIn("Config.options.ai.sessions.retentionDays", sessions)
        self.assertIn('"purge-expired", root.dir, String(root.retentionDays)', sessions)


class RetryRecoveryTests(unittest.TestCase):
    def test_retry_notice_is_bound_to_its_answer_with_cancel_and_model_change(self):
        ai = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
        message = (ROOT / "modules/ii/sidebarPolicies/aiChat/AiMessage.qml").read_text(encoding="utf-8")

        self.assertIn("property string retryMessageId", ai)
        self.assertIn("root.retryMessageId = root.messageIDs.find", ai)
        self.assertIn("readonly property bool retrying", message)
        self.assertIn("text: Ai.retryNotice", message)
        self.assertIn("onClicked: Ai.stopGeneration()", message)
        self.assertIn("root.modelPickerRequested();", message)

    def test_settings_expose_the_existing_notification_controls(self):
        main = AI_SETTINGS.read_text(encoding="utf-8")
        source = ai_page("AiNotificationsConfig.qml")

        self.assertIn('Qt.resolvedUrl("ai/AiNotificationsConfig.qml")', main)
        for setting in (
            "Config.options.ai.notify.whenDone",
            "Config.options.ai.notify.onlyWhenAway",
            "Config.options.ai.notify.minimumSeconds",
        ):
                self.assertIn(setting, source)


class WaveTwoSettingsOrganizationTests(unittest.TestCase):
    def test_configuration_routes_are_split_by_concern(self):
        source = AI_SETTINGS.read_text(encoding="utf-8")
        for label in (
            "Models & Keys",
            "Tools & Permissions",
            "Files, Vision & Voice",
            "Local Retrieval (RAG)",
            "Request Limits",
        ):
            with self.subTest(label=label):
                self.assertIn(label, source)

        for file_name in (
            "AiModelsKeysConfig.qml",
            "AiToolsPermissionsConfig.qml",
            "AiFilesVisionVoiceConfig.qml",
            "AiRequestLimitsConfig.qml",
            "AiUsageCostConfig.qml",
        ):
            self.assertTrue((AI_PAGES / file_name).exists())

        # The usage dashboard sat inline on the main page for a while; the
        # settings regroup gave it a route of its own like every other section.
        self.assertIn('title: Translation.tr("Usage & Cost")', source)
        self.assertIn('Qt.resolvedUrl("ai/AiUsageCostConfig.qml")', source)
        self.assertIn("AiUsageDashboard {", ai_page("AiUsageCostConfig.qml"))

    def test_chat_preferences_are_exposed_in_settings(self):
        main = AI_SETTINGS.read_text(encoding="utf-8")
        conversation = ai_page("AiConversationAppearanceConfig.qml")

        # Everyday choices stay on the main page; the rest live behind the
        # Conversation & Formatting route.
        self.assertIn('Qt.resolvedUrl("ai/AiConversationAppearanceConfig.qml")', main)
        for setting, source in (
            ("Config.options.ai.autoTitle", conversation),
            ("Config.options.ai.ephemeralInterfaceMessages", conversation),
            ("Config.options.ai.sessions.retentionDays", conversation),
            ("Config.options.sidebar.ai.thinkingDefault", conversation),
            ("Config.options.sidebar.ai.density", main),
            ("Config.options.sidebar.ai.activityDefault", conversation),
            ("Config.options.sidebar.ai.sendKey", main),
            ("Config.options.sidebar.ai.barKeys", conversation),
            ("Config.options.sidebar.ai.greeting", conversation),
        ):
            with self.subTest(setting=setting):
                self.assertIn(setting, source)


if __name__ == "__main__":
    unittest.main()
