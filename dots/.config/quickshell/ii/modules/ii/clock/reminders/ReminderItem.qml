pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One reminder, the way Samsung Reminder lists it: the completion circle in the
 * category's colour, the title, when it alerts (with repeat and alert-level marks), and —
 * in the card view — its notes, a checklist you can tick in place, image thumbnails and
 * links. The star on the right is Important.
 *
 * A click opens the editor; a right click or a long press starts selecting, after which
 * a click toggles the selection instead.
 */
Rectangle {
    id: root

    required property var reminder
    property date now: new Date()
    /// "card" shows everything; "list" is one dense line, alert and repeat as icons.
    property string view: "card"
    property bool selecting: false
    property bool selected: false
    property bool editing: false
    /// Hide the category chip inside that category's own list.
    property bool showCategory: true
    /// In the recycle bin a reminder can only be restored or deleted.
    property bool inTrash: false

    signal openRequested()
    signal selectToggled()

    readonly property color colAccent: RemindersStyle.categoryColor(root.reminder.categoryId)
    readonly property bool overdue: RemindersService.isOverdue(root.reminder, root.now)
    readonly property bool dense: root.view === "list"
    readonly property var images: root.reminder.attachments.filter(item => item.kind === "image")
    readonly property var links: root.reminder.attachments.filter(item => item.kind !== "image")
    readonly property int checklistDone: root.reminder.checklist.filter(item => item.done).length
    readonly property string level: root.reminder.schedule ? RemindersService.levelOf(root.reminder) : ""

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + (root.dense ? 12 : 22)
    radius: root.dense ? ClockStyle.radiusNormal : ClockStyle.radiusLarge
    color: root.selected ? ClockStyle.colSecondaryContainer
        : root.editing ? ClockStyle.colPrimaryContainer
        : pointer.containsMouse ? ClockStyle.colIdleCardHover : ClockStyle.colIdleCard

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    readonly property color colText: root.selected ? ClockStyle.colOnSecondaryContainer
        : root.editing ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
    readonly property color colMeta: root.selected ? ClockStyle.colOnSecondaryContainer
        : root.editing ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        pressAndHoldInterval: 450
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton || root.selecting)
                root.selectToggled();
            else
                root.openRequested();
        }
        onPressAndHold: root.selectToggled()
    }

    RowLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 6
            rightMargin: 8
        }
        spacing: 4

        Item {
            Layout.alignment: root.dense ? Qt.AlignVCenter : Qt.AlignTop
            implicitWidth: check.implicitWidth
            implicitHeight: check.implicitHeight

            ReminderCheck {
                id: check
                visible: !root.selecting
                checked: root.reminder.completed
                colAccent: root.colAccent
                size: root.dense ? 22 : 26
                tooltip: root.inTrash ? Translation.tr("Restore") : root.reminder.completed ? Translation.tr("Mark as not done") : Translation.tr("Complete")
                onToggled: {
                    if (root.inTrash)
                        RemindersService.restoreFromTrash([root.reminder.id]);
                    else
                        RemindersService.toggleComplete(root.reminder.id);
                }
            }

            // While selecting, the circle becomes the selection mark.
            Rectangle {
                visible: root.selecting
                anchors.centerIn: parent
                width: check.size
                height: width
                radius: ClockStyle.radiusSmall
                color: root.selected ? ClockStyle.colPrimary : "transparent"
                border.width: root.selected ? 0 : 2
                border.color: ClockStyle.colOnSurfaceVariant

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.selected
                    text: "check"
                    iconSize: parent.width * 0.7
                    color: ClockStyle.colOnPrimary
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: root.dense ? 0 : 4
            spacing: root.dense ? 0 : 6

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: root.reminder.title.length > 0 ? root.reminder.title : Translation.tr("Untitled reminder")
                    elide: Text.ElideRight
                    maximumLineCount: root.dense ? 1 : 3
                    wrapMode: root.dense ? Text.NoWrap : Text.Wrap
                    font.pixelSize: root.dense ? ClockStyle.textNormal + 1 : Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.strikeout: root.reminder.completed
                    color: root.colText
                    opacity: root.reminder.completed ? 0.6 : 1
                }

                // List view: the extras as small marks, the time at the end.
                Row {
                    visible: root.dense
                    spacing: 4

                    Repeater {
                        model: [
                            { show: root.reminder.checklist.length > 0, icon: "checklist" },
                            { show: root.images.length > 0, icon: "image" },
                            { show: root.links.length > 0, icon: "link" },
                            { show: root.reminder.notes.length > 0, icon: "notes" }
                        ].filter(item => item.show)

                        MaterialSymbol {
                            required property var modelData
                            text: modelData.icon
                            iconSize: ClockStyle.iconSmall
                            color: root.colMeta
                        }
                    }
                }

                StyledText {
                    visible: root.dense && root.reminder.schedule !== null
                    text: RemindersService.whenText(root.reminder, root.now)
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: root.overdue ? Font.DemiBold : Font.Normal
                    color: root.overdue ? ClockStyle.colError : root.colMeta
                }
            }

            // ── When, repeat, level, category ───────────────────────────
            Flow {
                Layout.fillWidth: true
                visible: !root.dense && (root.reminder.schedule !== null || (root.showCategory && root.reminder.categoryId !== "default")
                    || root.reminder.checklist.length > 0)
                spacing: 6

                MetaChip {
                    visible: root.reminder.schedule !== null
                    symbol: root.reminder.snoozedUntil > 0 ? "snooze" : "schedule"
                    label: root.reminder.snoozedUntil > 0
                        ? Translation.tr("Snoozed until %1").arg(Qt.locale().toString(new Date(root.reminder.snoozedUntil), Config.options?.time?.format ?? "hh:mm"))
                        : RemindersService.whenText(root.reminder, root.now)
                    alert: root.overdue
                }

                MetaChip {
                    visible: root.reminder.schedule?.repeat ? true : false
                    symbol: "repeat"
                    label: root.reminder.schedule?.repeat ? RemindersService.repeatText(root.reminder.schedule.repeat) : ""
                }

                MetaChip {
                    visible: root.level === "medium" || root.level === "strong"
                    symbol: RemindersStyle.alertLevel(root.level).icon
                    label: RemindersStyle.alertLevel(root.level).label
                }

                MetaChip {
                    visible: root.reminder.early !== null
                    symbol: "notification_add"
                    label: Translation.tr("Early alert")
                }

                MetaChip {
                    visible: root.reminder.checklist.length > 0
                    symbol: "checklist"
                    label: `${root.checklistDone}/${root.reminder.checklist.length}`
                }

                MetaChip {
                    visible: root.showCategory && root.reminder.categoryId !== "default"
                    dotColor: root.colAccent
                    label: RemindersService.categoryName(root.reminder.categoryId)
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.dense && root.reminder.notes.length > 0
                text: root.reminder.notes
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal
                color: root.colMeta
            }

            // ── Checklist, tickable in place ────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.dense && root.reminder.checklist.length > 0
                spacing: 0

                Repeater {
                    model: root.reminder.checklist.slice(0, 6)

                    RowLayout {
                        id: checkRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            implicitWidth: 18
                            implicitHeight: 18
                            radius: 5
                            color: checkRow.modelData.done ? root.colAccent : "transparent"
                            border.width: checkRow.modelData.done ? 0 : 1.5
                            border.color: root.colMeta

                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: checkRow.modelData.done
                                text: "check"
                                iconSize: 14
                                color: RemindersStyle.onColor(root.colAccent)
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.inTrash && !root.selecting
                                onClicked: RemindersService.toggleChecklistItem(root.reminder.id, checkRow.modelData.id)
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: checkRow.modelData.text
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            font.strikeout: checkRow.modelData.done
                            color: root.colText
                            opacity: checkRow.modelData.done ? 0.6 : 0.95
                        }
                    }
                }

                StyledText {
                    visible: root.reminder.checklist.length > 6
                    text: Translation.tr("+%1 more").arg(String(root.reminder.checklist.length - 6))
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colMeta
                }
            }

            // ── Images (up to eight) and links ──────────────────────────
            Flow {
                Layout.fillWidth: true
                visible: !root.dense && root.images.length > 0
                spacing: 6

                Repeater {
                    model: root.images.slice(0, 8)

                    Rectangle {
                        id: thumb
                        required property var modelData
                        width: 64
                        height: 64
                        radius: ClockStyle.radiusSmall
                        color: ClockStyle.colSurfaceHighest
                        clip: true

                        StyledImage {
                            anchors.fill: parent
                            source: "file://" + thumb.modelData.path
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 128
                            sourceSize.height: 128
                            asynchronous: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.selecting
                            onClicked: Qt.openUrlExternally("file://" + thumb.modelData.path)
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: !root.dense && root.links.length > 0
                spacing: 6

                Repeater {
                    model: root.links

                    LinkChip {
                        required property var modelData
                        attachment: modelData
                        enabled: !root.selecting
                    }
                }
            }
        }

        ClockIconButton {
            Layout.alignment: root.dense ? Qt.AlignVCenter : Qt.AlignTop
            visible: !root.inTrash && !root.selecting && (root.reminder.important || pointer.containsMouse || hovered)
            symbol: "star"
            filled: root.reminder.important
            size: root.dense ? 32 : 36
            iconSize: root.dense ? ClockStyle.iconSmall + 2 : ClockStyle.iconNormal - 2
            colIcon: root.reminder.important ? "#f2b33d" : root.colMeta
            tooltip: root.reminder.important ? Translation.tr("Not important") : Translation.tr("Important")
            onClicked: RemindersService.setImportant(root.reminder.id, !root.reminder.important)
        }
    }

    component MetaChip: Rectangle {
        id: chip
        property string symbol: ""
        property string label: ""
        property bool alert: false
        property color dotColor: "transparent"

        implicitWidth: chipRow.implicitWidth + 16
        implicitHeight: 24
        radius: height / 2
        color: chip.alert ? ClockStyle.colErrorContainer : ColorUtils.applyAlpha(root.colMeta, 0.1)

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
                visible: chip.dotColor.a > 0
                implicitWidth: 8
                implicitHeight: 8
                radius: 4
                color: chip.dotColor
            }

            MaterialSymbol {
                visible: chip.symbol.length > 0
                text: chip.symbol
                iconSize: ClockStyle.iconSmall - 1
                color: chip.alert ? ClockStyle.colOnErrorContainer : root.colMeta
            }

            StyledText {
                text: chip.label
                font.pixelSize: ClockStyle.textSmall
                font.weight: chip.alert ? Font.DemiBold : Font.Medium
                color: chip.alert ? ClockStyle.colOnErrorContainer : root.colMeta
            }
        }
    }

    /// A link or a file: its name or address, opened with the default app.
    component LinkChip: RippleButton {
        id: linkChip
        property var attachment

        implicitHeight: 30
        implicitWidth: Math.min(260, linkRow.implicitWidth + 20)
        buttonRadius: ClockStyle.radiusSmall
        colBackground: ColorUtils.applyAlpha(root.colAccent, 0.14)
        colBackgroundHover: ColorUtils.applyAlpha(root.colAccent, 0.24)
        colRipple: ColorUtils.applyAlpha(root.colAccent, 0.32)
        onClicked: Qt.openUrlExternally(linkChip.attachment.kind === "link" ? linkChip.attachment.url : "file://" + linkChip.attachment.path)

        contentItem: RowLayout {
            id: linkRow
            spacing: 5

            MaterialSymbol {
                text: linkChip.attachment.kind === "link" ? "link" : "draft"
                iconSize: ClockStyle.iconSmall
                color: root.colText
            }

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: 220
                text: linkChip.attachment.name || linkChip.attachment.url.replace(/^https?:\/\//, "") || linkChip.attachment.path
                elide: Text.ElideMiddle
                font.pixelSize: ClockStyle.textSmall
                color: root.colText
            }
        }
    }
}
