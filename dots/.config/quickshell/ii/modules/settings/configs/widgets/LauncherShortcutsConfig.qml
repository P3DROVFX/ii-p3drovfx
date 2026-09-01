import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    readonly property var defaults: [
        { actionId: "actions", name: Translation.tr("Open actions"), keys: "Ctrl+K", icon: "bolt" },
        { actionId: "favorite", name: Translation.tr("Toggle favorite"), keys: "Ctrl+P", icon: "star" },
        { actionId: "historyPrevious", name: Translation.tr("Previous history"), keys: "Up", icon: "history" },
        { actionId: "historyNext", name: Translation.tr("Next history"), keys: "Down", icon: "history" },
        { actionId: "secondary", name: Translation.tr("Run secondary action"), keys: "Ctrl+Enter", icon: "play_arrow" },
        { actionId: "copy", name: Translation.tr("Copy selected item"), keys: "Ctrl+C", icon: "content_copy" },
        { actionId: "save", name: Translation.tr("Save selected item"), keys: "Ctrl+S", icon: "save" },
        { actionId: "edit", name: Translation.tr("Edit selected item"), keys: "Ctrl+E", icon: "edit" },
        { actionId: "ocr", name: Translation.tr("Read image text"), keys: "Ctrl+O", icon: "document_scanner" },
        { actionId: "create", name: Translation.tr("Create from search"), keys: "Ctrl+N", icon: "add" },
        { actionId: "copyDispatch", name: Translation.tr("Copy window dispatch"), keys: "Ctrl+Shift+K", icon: "code" },
        { actionId: "delete", name: Translation.tr("Delete selected item"), keys: "Shift+Delete", icon: "delete" },
        { actionId: "section", name: Translation.tr("Switch panel section"), keys: "Tab", icon: "tab" },
        { actionId: "select", name: Translation.tr("Mark selected file"), keys: "Ctrl+Space", icon: "select_check_box" },
        { actionId: "cut", name: Translation.tr("Cut selected file"), keys: "Ctrl+X", icon: "content_cut" },
        { actionId: "paste", name: Translation.tr("Paste files"), keys: "Ctrl+V", icon: "content_paste" },
        { actionId: "createFolder", name: Translation.tr("Create folder"), keys: "Ctrl+Shift+N", icon: "create_new_folder" },
        { actionId: "duplicate", name: Translation.tr("Duplicate selected file"), keys: "Ctrl+D", icon: "control_point_duplicate" },
        { actionId: "toggleHidden", name: Translation.tr("Show or hide dotfiles"), keys: "Ctrl+H", icon: "visibility" },
        { actionId: "refresh", name: Translation.tr("Refresh current panel"), keys: "Ctrl+R", icon: "refresh" },
        { actionId: "stageCopy", name: Translation.tr("Copy files for paste"), keys: "Ctrl+Shift+C", icon: "file_copy" },
        { actionId: "sortFiles", name: Translation.tr("Change file sort order"), keys: "Ctrl+Shift+S", icon: "sort" },
        { actionId: "goHome", name: Translation.tr("Go to home directory"), keys: "Ctrl+Home", icon: "home" },
        { actionId: "forward", name: Translation.tr("Go forward in panel history"), keys: "Alt+Right", icon: "arrow_forward" }
    ]
    property string collisionActionId: ""

    function normalizeShortcut(value) {
        return String(value ?? "").replace(/\s+/g, "").replace(/control/ig, "ctrl");
    }

    function valueFor(actionId, fallback) {
        const binding = Array.from(Config.options.search.keybindings ?? [])
            .find(item => String(item?.actionId ?? "") === actionId);
        return String(binding?.shortcut ?? fallback);
    }

    function saveShortcut(actionId, value) {
        const shortcut = root.normalizeShortcut(value);
        if (shortcut.length === 0)
            return;
        const bindings = Array.from(Config.options.search.keybindings ?? []);
        if (bindings.some(item => String(item?.actionId ?? "") !== actionId
                && root.normalizeShortcut(item?.shortcut).toLocaleLowerCase() === shortcut.toLocaleLowerCase())) {
            root.collisionActionId = actionId;
            return;
        }
        root.collisionActionId = "";
        const next = bindings.filter(item => String(item?.actionId ?? "") !== actionId);
        next.push({ actionId: actionId, shortcut: shortcut });
        Config.options.search.keybindings = next;
    }

    function restoreDefaults() {
        Config.options.search.keybindings = root.defaults.map(item => ({ actionId: item.actionId, shortcut: item.keys }));
        root.collisionActionId = "";
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false
        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton { implicitWidth: Appearance.sizes.elevationMargin * 4; implicitHeight: implicitWidth; buttonRadius: Appearance.rounding.full; colBackground: Appearance.colors.colSecondaryContainer; colBackgroundHover: Appearance.colors.colSecondaryContainerHover; colRipple: Appearance.colors.colSecondaryContainerActive; onClicked: root.goBack(); MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: Appearance.font.pixelSize.large; color: Appearance.colors.colOnSecondaryContainer } }
            StyledText { text: Translation.tr("Search shortcuts"); font.pixelSize: Appearance.font.pixelSize.large; font.family: Appearance.font.family.title; color: Appearance.colors.colOnLayer0 }
        }
        ContentSection {
            icon: "keyboard"
            title: Translation.tr("Keyboard shortcuts")
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                StyledText { Layout.fillWidth: true; text: Translation.tr("These shortcuts are handled only while Search has focus and never replace Hyprland bindings."); wrapMode: Text.Wrap; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                Repeater {
                    model: root.defaults
                    delegate: ConfigTextField {
                        required property var modelData
                        text: modelData.name
                        icon: modelData.icon
                        inputText: root.valueFor(modelData.actionId, modelData.keys)
                        textField.error: root.collisionActionId === modelData.actionId
                        textField.onEditingFinished: root.saveShortcut(modelData.actionId, inputText)
                    }
                }
                RippleButton {
                    implicitWidth: restoreText.implicitWidth + Appearance.sizes.elevationMargin * 2
                    implicitHeight: Appearance.sizes.elevationMargin * 4
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.restoreDefaults()
                    StyledText { id: restoreText; anchors.centerIn: parent; text: Translation.tr("Restore defaults"); color: Appearance.colors.colOnSecondaryContainer }
                }
            }
        }
        ContentSection {
            icon: "info"
            title: Translation.tr("Conflict protection")
            StyledText {
                Layout.fillWidth: true
                text: root.collisionActionId.length > 0
                    ? Translation.tr("That shortcut is already assigned to another Search action.")
                    : Translation.tr("Duplicate Search shortcuts are rejected. Global keybinds remain configured in Hyprland.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }
        }
    }
}
