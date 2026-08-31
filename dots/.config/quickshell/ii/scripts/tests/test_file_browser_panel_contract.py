#!/usr/bin/env python3

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class FileBrowserPanelContractTests(unittest.TestCase):
    def test_file_browser_is_a_registry_hosted_panel_with_the_existing_prefix(self):
        registry = source("modules/common/SearchPanelRegistry.qml")
        config = source("modules/common/Config.qml")
        panel_line = next(line for line in registry.splitlines() if 'id: "fileBrowser"' in line)
        self.assertIn('source: "FileBrowserPanel.qml"', panel_line)
        self.assertIn('prefixKey: "fileBrowser"', panel_line)
        self.assertIn('searchShape: "ClamShell"', panel_line)
        self.assertIn("hosted: true", panel_line)
        self.assertIn("Config.options.search.fileBrowser.panelWidth", panel_line)
        self.assertIn('property string fileBrowser: "~"', config)
        self.assertIn("property JsonObject fileBrowser: JsonObject", config)
        self.assertIn("property int panelWidth: 1120", config)
        self.assertIn("property int panelBodyHeight: 620", config)

    def test_legacy_ls_provider_was_removed_without_removing_global_file_search(self):
        launcher = source("services/LauncherSearch.qml")
        self.assertNotIn("fileBrowserProc", launcher)
        self.assertNotIn("fileBrowserResults", launcher)
        self.assertNotIn('ls -1 -p', launcher)
        self.assertIn("fileSearchExpression", launcher)
        self.assertIn("fileSearchDebounce", launcher)

    def test_panel_has_navigation_preview_metadata_operations_and_feedback(self):
        panel = source("modules/ii/overview/FileBrowserPanel.qml")
        backend = source("modules/ii/overview/filebrowser/FileBrowserBackend.qml")
        helper = source("scripts/file_browser_helper.py")
        for contract in (
            "function navigateBack", "function navigateForward", "function enterDirectory",
            "ThumbnailImage", "metadataRows", "previewText", "function toggleSelection",
            "function pasteClipboard", "function deleteSelected", "function toggleActions",
            "Moved %1 item(s) to Trash", "reuseItems: true",
        ):
            self.assertIn(contract, panel)
        self.assertIn('["python3", root.helperPath, "list"', backend)
        self.assertIn('["python3", root.helperPath, "inspect"', backend)
        self.assertIn('["python3", root.helperPath, "operate"', backend)
        self.assertNotIn('["bash", "-c"', backend)
        self.assertIn('subprocess.run(["gio", "trash"', helper)

    def test_scroll_edge_fade_receives_its_required_list_target(self):
        panel = source("modules/ii/overview/FileBrowserPanel.qml")
        self.assertIn("ScrollEdgeFade {\n                                    target: fileList", panel)

    def test_file_rows_activate_on_single_click(self):
        panel = source("modules/ii/overview/FileBrowserPanel.qml")
        ripple_button = source("modules/common/widgets/RippleButton.qml")

        # The File Browser chooses direct activation: a click selects the row
        # and opens its file or directory in the same gesture.
        self.assertIn("onClicked: { root.selectedIndex = index; root.activateSelected(); }", panel)
        self.assertNotIn("onDoubleClicked: { root.selectedIndex = index; root.activateSelected(); }", panel)

        # RippleButton still forwards the native double-click signal for the
        # other panels that intentionally use the conventional interaction.
        self.assertIn("onDoubleClicked: event =>", ripple_button)
        self.assertIn("root.doubleClicked()", ripple_button)

    def test_panel_motion_spacing_and_size_controls_are_explicit(self):
        panel = source("modules/ii/overview/FileBrowserPanel.qml")
        settings = source("modules/settings/configs/widgets/LauncherModulesConfig.qml")
        for contract in (
            "minimumContentHeight: Config.options.search.fileBrowser.panelBodyHeight",
            "buttonRadius: selected ? Appearance.rounding.full",
            'shapeString: fileRow.selected ? "Circle"',
            "width: Math.max(0, ListView.view.width - root.rowHoverGutter * 2)",
            "transformOrigin: Item.BottomRight",
            "id: actionMenuEnterAnimation",
            "easing.type: Easing.OutBack",
            "Show dotfiles · Ctrl+H",
            'text: "folder_open"',
            "directoryRevealAnimation.restart()",
            "color: Appearance.colors.colScrim",
            "function closeTransientOverlays",
            "y: (1 - root.directoryRevealProgress) * root.rowHoverGutter",
        ):
            self.assertIn(contract, panel)
        action_menu = panel.split("id: actionMenu\n", 1)[1].split("id: editorPopup", 1)[0]
        self.assertIn("anchors.bottomMargin: 0", action_menu)
        self.assertNotIn("bottomMargin: root.rowHoverGutter", action_menu)
        self.assertNotIn('text: "folder_sync"', panel)
        self.assertIn("Config.options.search.fileBrowser.panelWidth", settings)
        self.assertIn("Config.options.search.fileBrowser.panelBodyHeight", settings)

    def test_file_operations_are_keyboard_routed_and_configurable(self):
        search_bar = source("modules/ii/overview/SearchBar.qml")
        widget = source("modules/ii/overview/SearchWidget.qml")
        overview = source("modules/ii/overview/Overview.qml")
        shortcuts = source("modules/settings/configs/widgets/LauncherShortcutsConfig.qml")
        for action in ("select", "cut", "paste", "createFolder", "duplicate", "toggleHidden", "refresh", "stageCopy", "sortFiles", "goHome", "forward"):
            self.assertIn('"' + action + '"', search_bar)
            self.assertIn('actionId: "' + action + '"', shortcuts)
        self.assertIn("onPanelShortcut", widget)
        self.assertIn("handlePanelBackspace", widget)
        self.assertIn('typeof root.activePanelItem.handleEscape === "function"', widget)
        self.assertIn("active: searchResultsSurface.registeredPanelActive || keepAlive", widget)
        self.assertIn("maximumSurfaceWidth", widget)
        self.assertIn("maximumSurfaceHeight", widget)
        self.assertIn("activePanelHeightBudget", widget)
        self.assertIn("centeredMaximumY", overview)
        self.assertIn("Math.min(centeredPreferredY, centeredMaximumY)", overview)
        self.assertIn("readonly property bool keepAlive", source("modules/ii/overview/SearchPanelHost.qml"))
        self.assertIn("active: contentKeepAlive ||", overview)
        self.assertIn("onKeepAliveChanged: realOverviewLoader.contentKeepAlive = keepAlive", overview)

    def test_file_browser_visual_regressions(self):
        panel = source("modules/ii/overview/FileBrowserPanel.qml")
        explorer = panel.split("id: browserBody", 1)[1].split("id: modalScrim", 1)[0]
        action_menu = panel.split("id: actionMenu\n", 1)[1].split("id: editorPopup", 1)[0]

        self.assertNotIn("colSurfaceContainerLow", explorer)
        self.assertIn('shapeString: fileRow.selected ? "Circle" : "Clover8Leaf"', explorer)
        self.assertIn("onActionMenuOpenChanged:", panel)
        self.assertIn("id: actionMenuEnterAnimation", panel)
        self.assertIn("Layout.alignment: Qt.AlignVCenter", action_menu)
        self.assertIn("Layout.leftMargin: root.rowHoverGutter", action_menu)
        self.assertIn("Layout.rightMargin: root.rowHoverGutter", action_menu)
        self.assertIn("width: ListView.view.width", action_menu)
        self.assertNotIn("x: root.rowHoverGutter", action_menu)


if __name__ == "__main__":
    unittest.main()
