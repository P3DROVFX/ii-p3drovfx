#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Contract tests for AI Keybinding Categorizer."""

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TestKeybindsAiCategorizeContract(unittest.TestCase):
    def test_ai_categorize_script_exists_and_builds_prompt(self):
        script_path = ROOT / "scripts/keybinds/ai_categorize.py"
        self.assertTrue(script_path.exists())
        
        # Test prompt builder and language metadata
        import importlib.util
        spec = importlib.util.spec_from_file_location("ai_categorize", script_path)
        ai_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ai_module)

        sample_kbs = [
            {"keys": "Ctrl + Right", "description": "Copilot: aceitar sugestão", "category": "Custom mappings"},
            {"keys": "Ctrl + E", "description": "Custom mapping", "category": "Custom mappings"},
        ]

        # Test English prompt
        meta_en = ai_module.get_language_meta("en_US")
        prompt_en = ai_module.build_categorization_prompt("Neovim · local config", "Neovim", sample_kbs, meta_en)
        self.assertIn("Neovim", prompt_en)
        self.assertIn("Ctrl + Right", prompt_en)
        self.assertIn("Ctrl + E", prompt_en)
        self.assertIn("Navigation & Motion", prompt_en)
        self.assertIn("AI & Completion", prompt_en)

        # Test Portuguese prompt
        meta_pt = ai_module.get_language_meta("pt_BR")
        prompt_pt = ai_module.build_categorization_prompt("Neovim · local config", "Neovim", sample_kbs, meta_pt)
        self.assertIn("Navegação & Movimentação", prompt_pt)
        self.assertIn("IA & Autocompletar", prompt_pt)

    def test_directories_and_service_wiring(self):
        directories = (ROOT / "modules/common/Directories.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        page = (ROOT / "modules/ii/cheatsheet/CheatsheetCustomKeybindsPage.qml").read_text(encoding="utf-8")

        # Directories contract
        self.assertIn("keybindAiCategorizerPath", directories)
        self.assertIn("ai_categorize.py", directories)

        # Service contract
        self.assertIn("aiCategorizerPath", service)
        self.assertIn("aiCategorizing", service)
        self.assertIn("aiCategorizingPageId", service)
        self.assertIn("function aiCategorizePage", service)
        self.assertIn("function setPageKeybinds", service)
        self.assertIn("aiCategorizeProcess", service)

        # Page UI contract
        self.assertIn("id: aiCategorizeButton", page)
        self.assertIn("KeybindsService.aiCategorizePage", page)
        self.assertIn('"auto_awesome"', page)
        self.assertIn('"progress_activity"', page)
        self.assertIn('"check"', page)
        self.assertIn("aiSuccess", page)
        self.assertIn("activeAiModelName", page)


if __name__ == "__main__":
    unittest.main()
