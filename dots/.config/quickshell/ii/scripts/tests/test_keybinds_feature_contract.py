import json
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[2]


class KeybindFeatureContractTests(unittest.TestCase):
    def test_store_is_atomic_guarded_and_external_to_presets(self):
        directories = (ROOT / "modules/common/Directories.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        self.assertIn("${Directories.state}/user/keybinds.json", directories)
        self.assertIn("atomicWrites: true", service)
        self.assertIn("watchChanges: true", service)
        self.assertIn("onFileChanged:", service)
        self.assertIn("onSaved:", service)
        self.assertIn("onSaveFailed:", service)
        self.assertNotIn("onAdapterUpdated:", service)
        self.assertIn("lastSavedText", service)
        self.assertIn("recoveringAfterSaveFailure", service)
        self.assertIn("saveRecoveryTimer", service)
        self.assertIn("missingFileGracePeriod: 2000", service)
        self.assertIn("keybinds.json could not be loaded safely and was left untouched", service)
        self.assertIn("diskVersion > root.schemaVersion", service)

    def test_schema_requires_key_and_description(self):
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        self.assertIn("if (!keys || !description)", service)
        self.assertIn("source.keybind ?? source.shortcut ?? source.key", service)
        self.assertIn("source.description ?? source.comment ?? source.label", service)
        self.assertIn("source.icon ?? source.symbol ?? source.materialIcon ?? source.iconName", service)

    def test_ui_keeps_hyprland_and_personal_pages_separate(self):
        host = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybinds.qml").read_text(encoding="utf-8")
        custom = (ROOT / "modules/ii/cheatsheet/CheatsheetCustomKeybindsPage.qml").read_text(encoding="utf-8")
        self.assertIn("CheatsheetHyprlandKeybinds", host)
        self.assertIn("KeybindsService.pages", host)
        self.assertIn("KeybindsService.openExportDialog", custom)
        self.assertIn("CheatsheetKeybindEditorSidebar", custom)
        editor = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybindEditorSidebar.qml").read_text(encoding="utf-8")
        self.assertIn("requiredField: true", editor)
        self.assertIn("component FilledTextField", editor)
        self.assertNotIn("MaterialTextField", editor)

    def test_page_creation_is_full_screen_and_sidebar_is_collapsible(self):
        host = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybinds.qml").read_text(encoding="utf-8")
        form = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybindsPageForm.qml").read_text(encoding="utf-8")
        persistent = (ROOT / "modules/common/Persistent.qml").read_text(encoding="utf-8")

        self.assertIn("keybindSidebarVisible", persistent)
        self.assertIn("root.sidebarVisible ? root.sidebarWidth : 0", host)
        self.assertIn("root.sidebarVisible ? 0 : 44", host)
        self.assertIn("CheatsheetKeybindsPageForm", host)
        self.assertIn("pageForm.isOpen || pageForm.isAnimating", host)
        self.assertIn("Item { Layout.fillWidth: true }", form)
        self.assertIn("width: root.width", form)
        self.assertIn("height: root.height", form)
        self.assertNotIn("colScrim", form)
        self.assertNotIn("CheatsheetKeybindsPageDialog", host)

        self.assertIn("selectedIcon", form)
        self.assertIn("availableIconChoices", form)
        self.assertIn('"developer_mode"', form)
        self.assertIn('"calendar_month"', form)
        self.assertNotIn("id: iconField", form)
        self.assertNotIn('placeholderText: Translation.tr("Material icon · optional")', form)

    def test_related_program_picker_uses_desktop_entries_and_can_drive_page_icon(self):
        form = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybindsPageForm.qml").read_text(encoding="utf-8")
        host = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybinds.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        combo = (ROOT / "modules/common/widgets/StyledComboBox.qml").read_text(encoding="utf-8")

        self.assertIn("AppSearch.list", form)
        self.assertIn("programChoices", form)
        self.assertIn('id: programSelector', form)
        self.assertIn('iconSourceRole: "iconSource"', form)
        self.assertIn("selectedProgramIcon", form)
        self.assertIn("selectedProgramId", form)
        self.assertIn("AppSearch.iconExists(iconCandidate)", form)
        self.assertIn("useProgramIcon", form)
        self.assertIn("Use app icon in sidebar", form)
        self.assertIn("useProgramIcon: Boolean(source.useProgramIcon)", service)
        self.assertIn("programId: root.oneLine(source.programId", service)
        self.assertIn("pages[index].useProgramIcon", service)
        self.assertIn("pageProgramIcon", host)
        self.assertIn("pageProgramId", host)
        self.assertIn("pageUseProgramIcon: Boolean(modelData.useProgramIcon)", host)
        self.assertIn("IconImage", host)
        self.assertIn("iconSourceRole", combo)
        self.assertIn("Quickshell.iconPath", combo)

    def test_sidebar_page_tabs_use_tonal_hover_without_scale_clipping(self):
        host = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybinds.qml").read_text(encoding="utf-8")
        page_button = host.split("component PageButton", 1)[1].split("component RailSectionHeader", 1)[0]
        collapsed_button = host.split("component CollapsedPageButton", 1)[1].split("Rectangle {", 1)[0]

        self.assertIn("scale: 1", page_button)
        self.assertIn("colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHighest, 1)", page_button)
        self.assertIn("colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover", page_button)
        self.assertIn("colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive", page_button)
        self.assertGreaterEqual(page_button.count("Behavior on color"), 4)
        self.assertIn("scale: 1", collapsed_button)
        self.assertIn("colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover", collapsed_button)
        self.assertIn("Behavior on color", collapsed_button)

    def test_collapsed_rail_import_and_personal_page_layout_contract(self):
        host = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybinds.qml").read_text(encoding="utf-8")
        custom = (ROOT / "modules/ii/cheatsheet/CheatsheetCustomKeybindsPage.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")

        self.assertIn("CollapsedPageButton", host)
        self.assertIn("RailSectionHeader", host)
        self.assertIn("personalShortcutCount", host)
        self.assertIn("Generated keymap · read only", host)
        self.assertIn("pageSubtitle", host)
        self.assertIn('pageId: ""', host)
        self.assertIn('pageIcon: "desktop_windows"', host)
        self.assertIn("collapsedPagesList", host)
        self.assertIn("importPickerProcess", service)
        self.assertIn("kdialog --getopenfilename", service)
        self.assertIn("importFile.path = selectedPath", service)
        self.assertIn('placeholderText: focus ? Translation.tr("Filter shortcuts") : Translation.tr("Hit \\"/\\" to filter")', custom)
        self.assertIn("anchors.bottom: parent.bottom", custom)
        self.assertIn("groupRepeater", custom)
        self.assertIn("groupOrderModel", custom)
        self.assertIn("ListModel", custom)
        self.assertIn("layoutTimer", custom)
        self.assertIn("Behavior on x", custom)
        self.assertIn("Behavior on y", custom)
        self.assertIn("totalContentHeight", custom)
        self.assertIn("getColumnIndex", custom)
        self.assertNotIn("groupsFlow", custom)
        self.assertIn("tabActive: root.isTabActive", host)
        self.assertIn('mainText: Translation.tr("New page")', host)
        self.assertIn("id: pageExitAnimation", host)
        self.assertIn("id: pageEnterAnimation", host)
        self.assertIn("displayedPageId", host)
        self.assertIn("minimumCardWidth", custom)
        self.assertIn("emptyColumnHeights", custom)

    def test_installed_app_sources_use_script_model_for_object_delegates(self):
        form = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybindsPageForm.qml").read_text(encoding="utf-8")
        detected_section = form.split("id: detectedList", 1)[1].split("PagePlaceholder", 1)[0]
        self.assertIn("model: ScriptModel", detected_section)

    def test_installed_app_source_role_is_declared_on_list_delegate(self):
        form = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybindsPageForm.qml").read_text(encoding="utf-8")
        detected_section = form.split("id: detectedList", 1)[1].split("PagePlaceholder", 1)[0]
        delegate_head = detected_section.split("delegate: Item", 1)[1].split("RippleButton", 1)[0]
        button_head = detected_section.split("RippleButton", 1)[1].split("contentItem", 1)[0]

        self.assertIn("required property var modelData", delegate_head)
        self.assertNotIn("required property var modelData", button_head)

    def test_personal_keybind_editor_uses_right_rail_and_shared_bottom_actions(self):
        custom = (ROOT / "modules/ii/cheatsheet/CheatsheetCustomKeybindsPage.qml").read_text(encoding="utf-8")
        editor = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybindEditorSidebar.qml").read_text(encoding="utf-8")

        self.assertNotIn("Quick add", custom)
        self.assertNotIn("quickAdd", custom)
        self.assertIn("id: bottomActions", custom)
        self.assertIn('mainText: Translation.tr("Add keybind")', custom)
        self.assertIn('sequence: "Ctrl+N"', custom)
        self.assertIn('sequence: "/"', custom)
        self.assertIn("id: editorSlot", custom)
        self.assertIn("editorSidebar.openCreate()", custom)
        self.assertIn("KeybindsService.addKeybind", editor)
        self.assertIn("KeybindsService.updateKeybind", editor)
        self.assertIn("Appearance.m3colors.m3surfaceContainerHigh", editor)
        self.assertIn("pageShift", editor)
        self.assertIn("pageOpacity", editor)
        self.assertIn("LIVE PREVIEW", editor)
        self.assertIn("detailsExpanded", editor)
        self.assertIn("Organize & identify", editor)
        self.assertIn("categorySuggestions", editor)
        self.assertIn("iconChoices", editor)
        self.assertIn("MaterialShapeWrappedMaterialSymbol", editor)
        self.assertNotIn("DashedBorder", editor)
        self.assertNotIn("MaterialTextField", editor)
        self.assertIn("Visual symbol", editor)
        self.assertNotIn("id: contextField", editor)
        self.assertNotIn("id: iconField", editor)
        self.assertIn("contextValue", editor)
        self.assertIn("iconValue", editor)
        self.assertIn("m3surfaceContainerLow", editor)
        self.assertIn("m3onSurfaceVariant", editor)
        self.assertNotIn("placeholderText: Translation.tr(\"Normal mode, editor focused…\")", editor)
        self.assertNotIn("placeholderText: Translation.tr(\"Or enter a Material Symbol name\")", editor)
        self.assertIn("requestDelete", editor)
        self.assertIn("if (KeybindsService.deleteKeybind", editor)
        self.assertIn("KeybindShortcutSequence", editor)
        self.assertIn("Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer", editor)

    def test_personal_shortcuts_use_shared_symbolic_sequences_and_action_rows(self):
        custom = (ROOT / "modules/ii/cheatsheet/CheatsheetCustomKeybindsPage.qml").read_text(encoding="utf-8")
        sequence = (ROOT / "modules/ii/cheatsheet/KeybindShortcutSequence.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")

        self.assertIn("KeybindShortcutSequence", custom)
        self.assertIn("categoryIcon", custom)
        self.assertIn("contextIcon", custom)
        self.assertIn("modeOrEditButton", custom)
        self.assertIn("chevronButton", custom)
        self.assertIn("keybindRow.width - keybindRow.keybindReserveWidth", custom)
        self.assertNotIn("keybindRow.width * 0.46", custom)
        self.assertIn('"SUPER": superKey', sequence)
        self.assertIn("font.family.iconNerd", sequence)
        self.assertIn("property color capsuleColor", sequence)
        self.assertTrue(sequence.lstrip().startswith("pragma ComponentBehavior: Bound"))
        self.assertIn("\nRectangle {\n    id: root", sequence)
        delegate = sequence.split("delegate: StyledText", 1)[1]
        self.assertNotIn("Rectangle {", delegate)
        keybind_row = custom.split("component KeybindRow", 1)[1].split("component StatChip", 1)[0]
        self.assertNotIn("MaterialShape", keybind_row)
        self.assertIn("inlineEditField", keybind_row)
        self.assertIn("Accessible.name", keybind_row)
        self.assertIn("readonly property real cardGap: 12", custom)
        self.assertIn("anchors.margins: 12", custom)
        self.assertIn("spacing: 2", custom)
        self.assertIn("colSurfaceContainerLow", sequence)
        self.assertIn("colOnSurface", sequence)
        self.assertIn("property real contentWidth", sequence)
        self.assertIn("font.pixelSize: Config.options.cheatsheet.fontSize.key", sequence)
        self.assertNotIn("border", sequence.lower())
        self.assertIn("icon:", service)
        self.assertIn("icon }, false", service)

    def test_catalog_contains_requested_programs(self):
        catalog = json.loads((ROOT / "defaults/keybinds/templates.json").read_text(encoding="utf-8"))
        programs = {template["program"] for template in catalog["templates"]}
        self.assertTrue({"Visual Studio Code", "Neovim", "IntelliJ IDEA"}.issubset(programs))
        for template in catalog["templates"]:
            self.assertGreaterEqual(len(template["keybinds"]), 10)
            for shortcut in template["keybinds"]:
                self.assertTrue(shortcut["keys"])
                self.assertTrue(shortcut["description"])

    def test_exports_do_not_include_absolute_source_path(self):
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        self.assertIn('portablePage.sourcePath = ""', service)

    def test_import_preserves_empty_pages_and_encoded_file_urls(self):
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        self.assertIn("rawEntries.length > 0 && page.keybinds.length === 0", service)
        self.assertIn("importFile.path = root.localPathFromDialogUrl(selectedFile)", service)
        self.assertIn("exportFile.path = targetPath", service)
        self.assertIn("decodeURIComponent", service)
        self.assertNotIn('Qt.resolvedUrl("file://" +', service)

    def test_store_limits_are_rejected_instead_of_truncated(self):
        service = (ROOT / "services/KeybindsService.qml").read_text(encoding="utf-8")
        self.assertIn("readonly property int maxPages: 500", service)
        self.assertIn("readonly property int maxKeybindsPerPage: 10000", service)
        self.assertNotIn("rawPages.slice(0, 500)", service)
        self.assertNotIn("inputEntries.slice(0, 10000)", service)

    def test_overview_keybinds_panel_category_tabs_and_all_search(self):
        panel = (ROOT / "modules/ii/overview/KeybindsPanel.qml").read_text(encoding="utf-8")
        self.assertIn("categoryTabsList", panel)
        self.assertIn('property string selectedCategory: "all"', panel)
        self.assertIn("readonly property var categories:", panel)
        self.assertIn("collectHyprlandBindings", panel)
        self.assertIn("collectCustomBindings", panel)
        self.assertIn("collectAllBindings", panel)
        self.assertIn("activeBindings", panel)
        self.assertIn("supportsSectionToggle: true", panel)
        self.assertIn("toggleSection()", panel)
        self.assertIn("cycleCategory", panel)
        self.assertIn("setCategory", panel)
        self.assertIn("KeybindsService.pages", panel)
        self.assertIn("HyprlandKeybinds", panel)

    def test_collapsed_rail_has_new_page_button_at_bottom(self):
        host = (ROOT / "modules/ii/cheatsheet/CheatsheetKeybinds.qml").read_text(encoding="utf-8")
        rail = host.split("id: collapsedRailSlot", 1)[1].split("Loader {", 1)[0]
        self.assertIn("pageForm.openCreate()", rail)
        self.assertIn('text: "add"', rail)


if __name__ == "__main__":
    unittest.main()

