pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property int tagIndex: 0
    property string noticeText: ""

    readonly property var tags: [""].concat(CommandsService.allTags())
    readonly property string activeTag: root.tags[Math.max(0, Math.min(root.tagIndex, root.tags.length - 1))] ?? ""
    readonly property var rows: root.filteredCommands()
    readonly property var selectedCommand: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length ? root.rows[root.selectedIndex] : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : root.selectedCommand
        ? String(root.selectedCommand.command ?? "")
        : Translation.tr("%1 commands").arg(String(root.rows.length))

    implicitWidth: 720
    implicitHeight: scaffold.implicitHeight

    function tagsFor(command) {
        const tags = command?.tags;
        if (!tags || tags.count === undefined)
            return [];
        const values = [];
        for (let index = 0; index < tags.count; index++)
            values.push(String(tags.get(index)?.modelData ?? ""));
        return values.filter(Boolean);
    }

    function filteredCommands() {
        const query = root.searchQuery.trim().toLocaleLowerCase();
        const rows = [];
        const model = CommandsService.commandsModel;
        for (let index = 0; model && index < model.count; index++) {
            const command = model.get(index);
            const tags = root.tagsFor(command);
            if (root.activeTag.length > 0 && !tags.includes(root.activeTag))
                continue;
            if (query.length > 0 && ![command?.command, command?.description, tags.join(" ")].join(" ").toLocaleLowerCase().includes(query))
                continue;
            rows.push({ id: String(command?.id ?? ""), command: String(command?.command ?? ""), description: String(command?.description ?? ""), tags: tags });
        }
        return rows;
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
        root.tagIndex = Math.max(0, Math.min(root.tagIndex, root.tags.length - 1));
    }

    function navigateUp(): bool {
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        commandsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length - 1)
            return false;
        root.selectedIndex++;
        commandsList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateLeft(): bool {
        if (root.tagIndex <= 0)
            return false;
        root.tagIndex--;
        root.selectedIndex = 0;
        return true;
    }

    function navigateRight(): bool {
        if (root.tagIndex >= root.tags.length - 1)
            return false;
        root.tagIndex++;
        root.selectedIndex = 0;
        return true;
    }

    function copySelected(): bool {
        if (!root.selectedCommand)
            return false;
        Quickshell.clipboardText = root.selectedCommand.command;
        root.showNotice(Translation.tr("Command copied to clipboard"));
        return true;
    }

    function activateSelected(): bool { return root.copySelected(); }

    function secondaryActivateSelected(): bool {
        if (!root.selectedCommand?.command)
            return false;
        Quickshell.execDetached(["bash", "-lc", root.selectedCommand.command]);
        root.showNotice(Translation.tr("Command started"));
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    function focusInput(): bool { return false; }

    onRowsChanged: root.clampSelection()
    onTagsChanged: root.clampSelection()
    onSearchQueryChanged: root.selectedIndex = 0

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Commands")
        icon: "terminal"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: ({ label: Translation.tr("Copy"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Run"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Tag"), keys: ["←", "→"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                Repeater {
                    model: root.tags.slice(0, 8)

                    delegate: RippleButton {
                        required property int index
                        required property string modelData
                        implicitWidth: tagLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                        implicitHeight: tagLabel.implicitHeight + Appearance.sizes.elevationMargin
                        buttonRadius: Appearance.rounding.full
                        colBackground: root.activeTag === modelData ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: root.activeTag === modelData ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.activeTag === modelData ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: { root.tagIndex = index; root.selectedIndex = 0; }

                        StyledText {
                            id: tagLabel
                            anchors.centerIn: parent
                            text: modelData.length > 0 ? modelData : Translation.tr("All")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.activeTag === modelData ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            ListView {
                id: commandsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.sizes.elevationMargin / 2
                model: root.rows

                delegate: RippleButton {
                    required property int index
                    required property var modelData
                    width: commandsList.width
                    implicitHeight: commandContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                    buttonRadius: Appearance.rounding.normal
                    colBackground: root.selectedIndex === index ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: root.selectedIndex === index ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: { root.selectedIndex = index; root.copySelected(); }

                    RowLayout {
                        id: commandContent
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin

                        MaterialSymbol {
                            text: "terminal"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.command
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.description.length > 0 ? modelData.description : modelData.tags.join(" · ")
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.selectedIndex === index ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        ConfiguredKeyHint {
                            visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                            actionId: "activate"
                            fallbackKeys: ["↵"]
                            surface: Appearance.colors.colPrimaryContainer
                            onSurface: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.rows.length === 0
                    text: Translation.tr("No commands match")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
