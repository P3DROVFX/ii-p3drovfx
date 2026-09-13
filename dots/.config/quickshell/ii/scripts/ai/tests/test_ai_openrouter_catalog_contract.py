#!/usr/bin/env python3
"""Contracts for the OpenRouter model catalogue and picker import flow."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SERVICE = (ROOT / "services" / "ai" / "OpenRouterModels.qml").read_text(encoding="utf-8")
PAGE = (ROOT / "services" / "ai" / "blocks" / "AiOpenRouterModelsPage.qml").read_text(encoding="utf-8")
PICKER = (ROOT / "services" / "ai" / "blocks" / "AiModelPickerPopover.qml").read_text(encoding="utf-8")
CONTROL_BAR = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "ChatControlBar.qml").read_text(encoding="utf-8")


class OpenRouterCatalogueTests(unittest.TestCase):
    def test_service_uses_popular_text_catalogue_and_normalizes_capabilities(self):
        self.assertIn("/api/v1/models?output_modalities=text&sort=most-popular", SERVICE)
        for field in ("context_length", "input_modalities", "output_modalities", "supported_parameters", "pricing"):
            self.assertIn(field, SERVICE)
        for capability in ("supportsVision", "supportsFiles", "supportsTools", "supportsReasoning", "supportsSampling"):
            self.assertIn(capability, SERVICE)
        self.assertIn("providerIcon", SERVICE)
        self.assertIn("providerIconIsRemote", SERVICE)
        self.assertIn("firstIconValue", SERVICE)
        self.assertIn('typeof value === "string"', SERVICE)
        self.assertIn("requestTimeoutMs", SERVICE)
        self.assertIn("requestTimeout.restart()", SERVICE)
        self.assertIn("sort=most-popular", SERVICE)

    def test_provider_icon_fallbacks_are_resolvable_and_remote_ready(self):
        provider_assets = {
            "deepseek": "DeepSeek.png",
            "google": "GoogleGemini.svg",
            "minimax": "MiniMax.png",
            "moonshotai": "MoonshotAI.png",
            "nvidia": "Nvidia.jpg",
            "openai": "OpenAI.svg",
            "qwen": "Qwen.png",
            "tencent": "Tencent.png",
            "x-ai": "SpaceXAI.png",
            "xiaomi": "Xioami.png",
            "z-ai": "Zai.png",
        }
        for provider_id, icon_name in provider_assets.items():
            provider_key = provider_id if "-" not in provider_id else f'"{provider_id}"'
            self.assertIn(f'{provider_key}: "{icon_name}"', SERVICE)
            self.assertTrue((ROOT / "assets" / "icons" / icon_name).is_file(), icon_name)
        self.assertIn("function providerIdFor", SERVICE)
        self.assertIn('replace(/^~/, "")', SERVICE)
        self.assertIn("providerIconUsesNaturalColors", SERVICE)
        self.assertIn("import qs.modules.common.functions", PAGE)
        self.assertEqual(PAGE.count('source: visible ? modelCard.modelData.providerIcon : ""'), 2)
        self.assertIn("colorize: !modelCard.modelData.providerIconUsesNaturalColors", PAGE)
        for icon_name in (
            "bootstrap_claude.svg",
            "deepseek-symbolic.svg",
            "mistral-symbolic.svg",
            "ollama-symbolic.svg",
            "openai-symbolic.svg",
        ):
            self.assertTrue((ROOT / "assets" / "icons" / icon_name).is_file(), icon_name)

    def test_service_does_not_persist_or_log_the_api_key(self):
        self.assertIn('xhr.setRequestHeader("Authorization", "Bearer " + apiKey)', SERVICE)
        self.assertIn("Ai.onlineAllowed", SERVICE)
        self.assertNotIn("Config.options.ai.customModels =", SERVICE)
        self.assertNotIn("console.log(apiKey", SERVICE)
        self.assertNotIn("console.log(root.activeRequest", SERVICE)

    def test_page_searches_and_shows_both_price_directions(self):
        self.assertIn("root.visibleModels", PAGE)
        self.assertIn("model.title", PAGE)
        self.assertIn("model.id", PAGE)
        self.assertIn('formatPriceWithFree(Translation.tr("Input")', PAGE)
        self.assertIn('formatPriceWithFree(Translation.tr("Output")', PAGE)

    def test_page_keeps_capability_tooltips_hover_only_and_cards_compact(self):
        self.assertIn("alternativeVisibleCondition: badgeMouseArea.containsMouse", PAGE)
        self.assertIn("extraVisibleCondition: false", PAGE)
        self.assertIn("Layout.minimumWidth: 0", PAGE)
        self.assertIn("providerIconIsRemote", PAGE)
        self.assertNotIn("text: modelCard.modelData.description", PAGE)

    def test_catalogue_uses_the_host_header_and_vertical_card_metadata(self):
        self.assertIn("property bool hostOwnsCatalogueHeader", PICKER)
        self.assertIn("showHeader: !root.hostOwnsCatalogueHeader", PICKER)
        self.assertIn("function closeOpenRouterModels()", PICKER)
        self.assertIn("function refreshOpenRouterModels()", PICKER)
        self.assertIn("property bool showHeader", PAGE)
        self.assertIn("id: modelDetailsColumn", PAGE)
        self.assertIn("id: modelMetadataColumn", PAGE)
        self.assertIn("id: addModelButton", PAGE)
        self.assertIn("readonly property bool modelCatalogueOpen", CONTROL_BAR)
        self.assertIn("modelCatalogueTitle", CONTROL_BAR)
        self.assertIn("picker.closeModelCatalogue()", CONTROL_BAR)
        self.assertIn("picker.refreshModelCatalogue()", CONTROL_BAR)

    def test_catalogue_fills_the_canvas_list_area_without_affecting_compact_hosts(self):
        self.assertIn("property bool fillAvailableHeight", PAGE)
        self.assertIn("Layout.fillHeight: root.fillAvailableHeight", PAGE)
        self.assertIn("property bool fillOpenRouterAvailableHeight", PICKER)
        self.assertIn("fillAvailableHeight: root.fillOpenRouterAvailableHeight", PICKER)
        self.assertIn("fillOpenRouterAvailableHeight: true", CONTROL_BAR)

    def test_import_uses_existing_openrouter_provider_and_config_shape(self):
        self.assertIn('provider: "openrouter"', PAGE)
        self.assertIn("Config.options.ai.customModels", PAGE)
        self.assertIn('capabilitySource: "detected"', PAGE)
        self.assertIn('entry?.provider === "openrouter"', PAGE)
        entry = PAGE.split("list.push({", 1)[1].split("});", 1)[0]
        self.assertNotIn("apiKey", entry)
        self.assertNotIn("Authorization", entry)
        self.assertIn('kind: "openrouter-catalog"', PICKER)
        self.assertIn('root.openRouterModelsOpen = true', PICKER)


if __name__ == "__main__":
    unittest.main()
