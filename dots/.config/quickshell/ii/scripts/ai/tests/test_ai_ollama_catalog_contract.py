"""Contracts for local Ollama catalogue pulls in the AI sidebar."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
SERVICE = (ROOT / "services/ai/OllamaCatalog.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
PAGE = (ROOT / "services/ai/blocks/AiOllamaModelsPage.qml").read_text(encoding="utf-8")
PICKER = (ROOT / "services/ai/blocks/AiModelPickerPopover.qml").read_text(encoding="utf-8")
CONTROL_BAR = (ROOT / "modules/ii/sidebarPolicies/aiChat/ChatControlBar.qml").read_text(encoding="utf-8")
AI_CHAT = (ROOT / "modules/ii/sidebarPolicies/AiChat.qml").read_text(encoding="utf-8")


class OllamaPullServiceTests(unittest.TestCase):
    def test_service_imports_the_quickshell_singleton_type(self):
        self.assertIn("\nimport Quickshell\n", SERVICE)

    def test_service_imports_the_translation_singleton_used_by_suggestions(self):
        self.assertIn("\nimport qs.services\n", SERVICE)

    def test_catalogue_is_curated_but_accepts_any_valid_library_tag(self):
        self.assertIn("readonly property var models", SERVICE)
        self.assertIn('name: "qwen3.5:9b"', SERVICE)
        self.assertIn('provider: Translation.tr("Ollama")', SERVICE)
        self.assertIn("function normalizeModelName(modelName): string", SERVICE)
        self.assertIn("if (!/^[A-Za-z0-9]", SERVICE)
        self.assertIn('segment === "." || segment === ".."', SERVICE)

    def test_community_gguf_catalogue_is_bounded_and_paged(self):
        for token in (
            'communityEndpoint: "https://huggingface.co/api/models"',
            "communityPageSize: 12",
            '"?filter=gguf"',
            "function loadCommunityModels(searchTerm = \"\")",
            "function loadMoreCommunityModels()",
            'getResponseHeader("Link")',
            '"hf.co/" + repositoryId',
            'provider: Translation.tr("Hugging Face")',
        ):
            with self.subTest(token=token):
                self.assertIn(token, SERVICE)

    def test_pull_is_one_local_streamed_operation_with_no_shell_interpolation(self):
        self.assertIn('endpoint: "http://127.0.0.1:11434/api/pull"', SERVICE)
        self.assertIn('"curl", "--no-buffer", "--silent", "--show-error"', SERVICE)
        self.assertIn('"--data-binary", "@-"', SERVICE)
        self.assertIn('pullProc.write(JSON.stringify({ model: normalized, stream: true })', SERVICE)
        self.assertIn("stdinEnabled = false;", SERVICE)
        self.assertIn("stdout: SplitParser", SERVICE)
        self.assertNotIn("bash", SERVICE)

    def test_pull_tracks_progress_and_can_be_cancelled(self):
        for token in (
            "property real pullProgress: -1",
            "function cancelPull()",
            "root.pullState = \"cancelled\"",
            "completed / total",
            "status.toLowerCase() === \"success\"",
            "signal pullSucceeded(string modelName)",
        ):
            with self.subTest(token=token):
                self.assertIn(token, SERVICE)

    def test_pull_replaces_one_system_notification_as_progress_changes(self):
        for token in (
            "function queueDownloadNotification",
            "function dispatchDownloadNotification",
            '"notify-send"',
            '"--print-id"',
            '"--replace-id=" + String(root.downloadNotificationId)',
            '"--hint=int:value:" + String(percent)',
        ):
            with self.subTest(token=token):
                self.assertIn(token, SERVICE)

        self.assertIn("function findTrackedNotification", (ROOT / "services/Notifications.qml").read_text(encoding="utf-8"))

    def test_success_refreshes_models_used_by_the_chat_and_rag_picker(self):
        self.assertIn("function refreshOllamaModels()", AI)
        self.assertIn("AiRagService.refreshInstalledModels();", AI)
        self.assertIn("root.ollamaRefreshPending = true;", AI)
        self.assertIn("Qt.callLater(root.refreshOllamaModels);", AI)


class OllamaSidebarCatalogueTests(unittest.TestCase):
    def test_ollama_catalogue_is_reachable_from_its_provider_group(self):
        self.assertIn('kind: "ollama-catalog"', PICKER)
        self.assertIn("root.ollamaModelsOpen = true", PICKER)
        self.assertIn("AiOllamaModelsPage", PICKER)
        self.assertIn("function closeModelCatalogue()", PICKER)
        self.assertIn("function refreshModelCatalogue()", PICKER)
        self.assertIn('providerIds[i] === "ollama"', PICKER)
        self.assertIn("models.length === 0 && !hasCatalogueEntry", PICKER)

    def test_page_makes_download_explicit_and_shows_live_state(self):
        self.assertIn("Pulling downloads through your local Ollama daemon.", PAGE)
        self.assertIn("OllamaCatalog.pull(modelName)", PAGE)
        self.assertIn("OllamaCatalog.cancelPull()", PAGE)
        self.assertIn("OllamaCatalog.pullProgress", PAGE)
        self.assertIn("Ai.refreshOllamaModels();", PAGE)

    def test_search_has_one_download_action_per_model_and_compact_cards(self):
        self.assertNotIn("id: customPullButton", PAGE)
        self.assertIn("Keys.onReturnPressed: root.pull(text)", PAGE)
        self.assertIn("anchors.rightMargin: Appearance.rounding.large", PAGE)

        model_delegate = PAGE.split("id: modelRow", 1)[1].split("id: modelPullButton", 1)[0]
        self.assertIn("implicitHeight: root.downloadActionExtent", model_delegate)
        self.assertIn("Layout.preferredHeight: root.downloadActionExtent", model_delegate)
        self.assertIn("Layout.maximumHeight: root.downloadActionExtent", model_delegate)
        self.assertIn("font.pixelSize: Appearance.font.pixelSize.large", model_delegate)
        self.assertIn("text: modelRow.modelData.provider", model_delegate)
        self.assertIn("elide: Text.ElideRight", model_delegate)
        self.assertNotIn("Layout.maximumWidth: parent.width", model_delegate)
        self.assertNotIn("modelRow.modelData.description", model_delegate)
        self.assertNotIn("wrapMode: Text.Wrap", model_delegate)

        details = model_delegate.split("id: details", 1)[1]
        self.assertNotIn("RowLayout {", details)

        pull_button = PAGE.split("id: modelPullButton", 1)[1].split("Accessible.name", 1)[0]
        self.assertIn("implicitWidth: root.downloadActionExtent", pull_button)
        self.assertIn("implicitHeight: root.downloadActionExtent", pull_button)

    def test_page_searches_and_loads_only_one_community_page_at_a_time(self):
        for token in (
            "OllamaCatalog.loadCommunityModels(root.query)",
            "OllamaCatalog.loadMoreCommunityModels()",
            "OllamaCatalog.communityLoading",
            "OllamaCatalog.communityNextUrl",
        ):
            with self.subTest(token=token):
                self.assertIn(token, PAGE)

    def test_canvas_header_navigates_both_catalogue_pages(self):
        self.assertIn("readonly property bool modelCatalogueOpen", CONTROL_BAR)
        self.assertIn("modelCatalogueTitle", CONTROL_BAR)
        self.assertIn("picker.closeModelCatalogue()", CONTROL_BAR)

    def test_sidebar_does_not_steal_unaccepted_input_keys_from_a_canvas_field(self):
        keys_handler = AI_CHAT.split("Keys.onPressed: event => {", 1)[1].split("// ── References", 1)[0]
        self.assertIn("if (root.canvasViewOpen)", keys_handler)
        self.assertLess(keys_handler.index("if (root.canvasViewOpen)"), keys_handler.index("messageInputField.forceActiveFocus()"))

    def test_more_controls_can_open_the_ollama_catalogue_directly(self):
        self.assertIn('root.activePopover === "ollamaModels"', CONTROL_BAR)
        self.assertIn("id: ollamaModelsComponent", CONTROL_BAR)
        self.assertIn('root.openView("ollamaModels", "more")', CONTROL_BAR)


if __name__ == "__main__":
    unittest.main()
