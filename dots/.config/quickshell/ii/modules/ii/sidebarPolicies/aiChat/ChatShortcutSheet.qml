pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Every key this chat answers to, in the place the chat was.
 *
 * It is a page in the same canvas the other controls use rather than a
 * floating cheatsheet, because the point is to be reachable from inside the
 * conversation with one key and gone again with Escape. Nothing here is a
 * list of features: each row is a key that works right now, grouped by what
 * the reader is doing when they reach for it.
 */
Item {
    id: root

    readonly property real rowHeight: Math.round(Appearance.font.pixelSize.huge * 1.8)
    readonly property real groupGap: Appearance.rounding.small

    function navigateUp() {
        sheetFlickable.contentY = Math.max(0, sheetFlickable.contentY - sheetFlickable.height / 2);
    }

    function navigateDown() {
        sheetFlickable.contentY = Math.min(
            Math.max(0, sheetFlickable.contentHeight - sheetFlickable.height),
            sheetFlickable.contentY + sheetFlickable.height / 2);
    }

    readonly property var groups: [
        {
            title: Translation.tr("The conversation"),
            icon: "forum",
            rows: [
                { keys: ["Ctrl", "Shift", "O"], what: Translation.tr("Start a new chat") },
                { keys: ["Ctrl", "L"], what: Translation.tr("Saved chats") },
                { keys: ["Ctrl", "F"], what: Translation.tr("Find in this chat") },
                { keys: ["Ctrl", "E"], what: Translation.tr("Edit the last question") },
                { keys: ["Ctrl", "R"], what: Translation.tr("Ask the last question again") },
                { keys: ["Ctrl", "J"], what: Translation.tr("Move this chat to the Search panel") }
            ]
        },
        {
            title: Translation.tr("What answers"),
            icon: "tune",
            rows: [
                { keys: ["Ctrl", "M"], what: Translation.tr("Pick the model") },
                { keys: ["Ctrl", "T"], what: Translation.tr("Tools") },
                { keys: ["Ctrl", "P"], what: Translation.tr("Persona and prompt") },
                { keys: ["Ctrl", "K"], what: Translation.tr("API keys") },
                { keys: ["Ctrl", "I"], what: Translation.tr("What the tools can do, with example prompts") }
            ]
        },
        {
            title: Translation.tr("Writing"),
            icon: "keyboard",
            rows: [
                { keys: ["Enter"], what: Translation.tr("Send") },
                { keys: ["Shift", "Enter"], what: Translation.tr("New line") },
                { keys: ["Tab"], what: Translation.tr("Take the suggestion, or move to the next control") },
                { keys: ["Ctrl", "V"], what: Translation.tr("Paste — an image in the clipboard is attached") },
                { keys: ["Esc"], what: Translation.tr("Stop editing, drop the attachments, close a panel") },
                { keys: ["/"], what: Translation.tr("Commands") },
                { keys: ["?"], what: Translation.tr("This page, from an empty composer") }
            ]
        },
        {
            title: Translation.tr("Reading"),
            icon: "swipe_vertical",
            rows: [
                { keys: ["Alt", "↑"], what: Translation.tr("Previous turn") },
                { keys: ["Alt", "↓"], what: Translation.tr("Next turn") },
                { keys: ["Page ↑"], what: Translation.tr("Up a screen") },
                { keys: ["Page ↓"], what: Translation.tr("Down a screen") },
                { keys: ["Ctrl", "End"], what: Translation.tr("Back to the newest message") }
            ]
        },
        {
            title: Translation.tr("The sidebar itself"),
            icon: "dock_to_right",
            rows: [
                { keys: ["Ctrl", "O"], what: Translation.tr("Expand the sidebar") },
                { keys: ["Ctrl", "D"], what: Translation.tr("Detach it into its own window") },
                { keys: ["Ctrl", "P"], what: Translation.tr("Pin it open") }
            ]
        }
    ]

    StyledFlickable {
        id: sheetFlickable
        anchors.fill: parent
        contentHeight: sheetColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: sheetColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: root.groupGap

            Repeater {
                model: ScriptModel {
                    values: root.groups
                }

                delegate: ColumnLayout {
                    id: group
                    required property var modelData

                    Layout.fillWidth: true
                    spacing: Appearance.rounding.unsharpenmore

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Appearance.rounding.unsharpenmore
                        spacing: Appearance.rounding.unsharpenmore

                        MaterialSymbol {
                            text: group.modelData.icon
                            fill: 1
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: group.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: group.modelData.rows
                        }

                        delegate: Rectangle {
                            id: shortcutRow
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: root.rowHeight
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Appearance.rounding.small
                                anchors.rightMargin: Appearance.rounding.unsharpenmore
                                spacing: Appearance.rounding.unsharpenmore

                                StyledText {
                                    Layout.fillWidth: true
                                    text: shortcutRow.modelData.what
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                }

                                Repeater {
                                    model: ScriptModel {
                                        values: shortcutRow.modelData.keys
                                    }

                                    delegate: Rectangle {
                                        id: keyCap
                                        required property var modelData

                                        implicitWidth: Math.max(keyLabel.implicitWidth + Appearance.rounding.small, root.rowHeight * 0.62)
                                        implicitHeight: Math.round(root.rowHeight * 0.62)
                                        radius: Appearance.rounding.verysmall
                                        color: Appearance.colors.colLayer3

                                        StyledText {
                                            id: keyLabel
                                            anchors.centerIn: parent
                                            text: keyCap.modelData
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnLayer3
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: Appearance.rounding.large
            }
        }
    }

    ScrollEdgeFade {
        target: sheetFlickable
        vertical: true
        color: Appearance.colors.colLayer1
    }
}
