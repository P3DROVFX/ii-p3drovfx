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

    // One grouped shape: large outer corners, tight joins. The row under the pointer rounds
    // off and the rows facing it round with it, pressing a notch into the group.
    ColumnLayout {
        id: list

        property int hoveredIndex: -1
        readonly property int lastIndex: RemindersService.categories.length - 1

        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: RemindersService.categories

            Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property color colAccent: RemindersStyle.categoryColor(row.modelData.id)
                readonly property bool movable: row.modelData.id !== "default"
                readonly property bool hovered: list.hoveredIndex === row.index
                property real roundTop: row.index === 0 || row.hovered || list.hoveredIndex === row.index - 1
                    ? ClockStyle.radiusLarge : Appearance.rounding.verysmall
                property real roundBottom: row.index === list.lastIndex || row.hovered
                    || list.hoveredIndex === row.index + 1
                    ? ClockStyle.radiusLarge : Appearance.rounding.verysmall

                Layout.fillWidth: true
                implicitHeight: 58
                topLeftRadius: row.roundTop
                topRightRadius: row.roundTop
                bottomLeftRadius: row.roundBottom
                bottomRightRadius: row.roundBottom
                color: row.hovered ? ClockStyle.colFieldHover : ClockStyle.colField

                Behavior on color {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }
                Behavior on roundTop {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                }
                Behavior on roundBottom {
                    enabled: !ClockStyle.reducedMotion
                    animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                }

                // A handler, not the MouseArea's containsMouse: the row stays hovered while
                // the pointer is over its own buttons.
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered)
                            list.hoveredIndex = row.index;
                        else if (list.hoveredIndex === row.index)
                            list.hoveredIndex = -1;
                    }
                }

                MouseArea {
                    anchors.fill: parent
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
                            id: nameText
                            Layout.fillWidth: true
                            text: RemindersService.categoryName(row.modelData.id)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: ClockStyle.colOnSurface

                            HoverHandler {
                                id: nameHover
                            }
                            StyledToolTip {
                                extraVisibleCondition: nameHover.hovered && nameText.truncated
                                text: nameText.text
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: RemindersStyle.countText(root.counts[row.modelData.id] ?? 0)
                                + (row.modelData.pinned ? " · " + Translation.tr("Pinned") : "")
                                + (row.modelData.remote?.todo?.listId ? " · " + Translation.tr("Synced") : "")
                            elide: Text.ElideRight
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
                        onClicked: RemindersService.updateCategory(row.modelData.id,
                            { pinned: !row.modelData.pinned })
                    }

                    MaterialSymbol {
                        text: root.mode === "move" ? "drive_file_move" : "edit"
                        iconSize: ClockStyle.iconSmall + 2
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }
            }
        }
    }

    ClockFormField {
        id: newField
        Layout.topMargin: 6
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

    // Managing commits as it goes, so its one button is the filled Done; moving commits on
    // the row picked, so its one button backs out.
    actions: [
        ClockSheetAction {
            label: root.mode === "move" ? Translation.tr("Cancel") : Translation.tr("Done")
            symbol: root.mode === "move" ? "close" : "check"
            primary: root.mode === "manage"
            onClicked: root.close()
        }
    ]
}
