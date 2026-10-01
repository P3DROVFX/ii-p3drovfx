pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Two jobs on one list of categories. "manage" is Samsung's Manage categories: reorder,
 * pin, edit, delete, add. "move" files the selected reminders under the category picked.
 */
ClockSheet {
    id: root

    property string mode: "manage"
    /// Reminders to move (mode "move").
    property var reminderIds: []

    signal editRequested(string categoryId)
    signal moved()

    readonly property var counts: {
        const counts = {};
        RemindersService.liveReminders.forEach(item => {
            if (!item.completed)
                counts[item.categoryId] = (counts[item.categoryId] ?? 0) + 1;
        });
        return counts;
    }

    title: root.mode === "move" ? Translation.tr("Move to") : Translation.tr("Manage categories")
    subtitle: root.mode === "move" ? RemindersStyle.countText(root.reminderIds.length) : ""

    Repeater {
        model: RemindersService.categories

        Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property color colAccent: RemindersStyle.categoryColor(row.modelData.id)
            readonly property bool movable: row.modelData.id !== "default"

            Layout.fillWidth: true
            implicitHeight: 58
            radius: Appearance.rounding.small
            color: rowPointer.containsMouse ? ClockStyle.colFieldHover : ClockStyle.colField

            MouseArea {
                id: rowPointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.mode === "move") {
                        RemindersService.move(root.reminderIds, row.modelData.id);
                        root.moved();
                        root.close();
                    } else {
                        root.editRequested(row.modelData.id);
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 10

                Rectangle {
                    implicitWidth: 36
                    implicitHeight: 36
                    radius: 18
                    color: row.colAccent

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: row.modelData.icon
                        iconSize: 18
                        color: RemindersStyle.onColor(row.colAccent)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: RemindersService.categoryName(row.modelData.id)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Bold
                        color: ClockStyle.colOnSurface
                    }

                    StyledText {
                        text: RemindersStyle.countText(root.counts[row.modelData.id] ?? 0)
                            + (row.modelData.pinned ? " · " + Translation.tr("Pinned") : "")
                            + (row.modelData.remote?.todo?.listId ? " · " + Translation.tr("Synced") : "")
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }

                ClockIconButton {
                    visible: root.mode === "manage" && row.movable
                    symbol: "arrow_upward"
                    size: 32
                    iconSize: ClockStyle.iconSmall
                    tooltip: Translation.tr("Move up")
                    onClicked: RemindersService.moveCategory(row.modelData.id, -1)
                }

                ClockIconButton {
                    visible: root.mode === "manage" && row.movable
                    symbol: "arrow_downward"
                    size: 32
                    iconSize: ClockStyle.iconSmall
                    tooltip: Translation.tr("Move down")
                    onClicked: RemindersService.moveCategory(row.modelData.id, 1)
                }

                ClockIconButton {
                    visible: root.mode === "manage" && row.movable
                    symbol: "keep"
                    filled: row.modelData.pinned
                    size: 32
                    iconSize: ClockStyle.iconSmall
                    tooltip: row.modelData.pinned ? Translation.tr("Unpin") : Translation.tr("Pin to top")
                    onClicked: RemindersService.updateCategory(row.modelData.id, { pinned: !row.modelData.pinned })
                }

                MaterialSymbol {
                    text: root.mode === "move" ? "drive_file_move" : "edit"
                    iconSize: ClockStyle.iconSmall + 2
                    color: ClockStyle.colOnSurfaceVariant
                }
            }
        }
    }

    ClockFormField {
        id: newField
        symbol: "create_new_folder"
        caption: Translation.tr("New category")
        placeholder: Translation.tr("Name it and press Enter")
        onAccepted: {
            const color = RemindersStyle.palette[RemindersService.categories.length % RemindersStyle.palette.length];
            const id = RemindersService.addCategory(newField.text, color, "list");
            newField.text = "";
            if (id.length > 0 && root.mode === "move") {
                RemindersService.move(root.reminderIds, id);
                root.moved();
                root.close();
            }
        }
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Done")
            symbol: "check"
            primary: root.mode === "manage"
            onClicked: root.close()
        }
    ]
}
