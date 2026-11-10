pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../../services/reminders/RemindersLogic.js" as Logic

/**
 * Samsung Reminder's home-screen widget, for the island dashboard and the sidebar: what
 * is due (overdue and today first, then what is scheduled, then the rest), ticked off
 * from here, and a field to add one. Holding the tile, or the open button, opens the
 * Reminders tab.
 */
Item {
    id: root

    property int sizeW: 0
    property int sizeH: 0
    property int entranceTrigger: -1

    readonly property bool roomy: root.height > 220
    readonly property int rowHeight: 38
    /// Rows are filled plates, as in the Notes and Tasks widgets, so they need a gap.
    readonly property int rowGap: 4
    readonly property int maxRows: Math.max(1, Math.floor((root.height - header.height - addBar.height - 16
        + root.rowGap) / (root.rowHeight + root.rowGap)))

    property var memo: ({})
    readonly property var shownIds: {
        const allDay = RemindersService.allDayTime;
        const open = RemindersService.reminders.filter(item => Logic.isLive(item));
        const dated = Logic.sortReminders(open.filter(item => item.schedule), "alertTime", false, {}, allDay);
        const undated = Logic.sortReminders(open.filter(item => !item.schedule), "modified", true, {},
            allDay);
        const ids = dated.concat(undated).slice(0, root.maxRows).map(item => item.id);
        return ObjectUtils.keep(root.memo, "ids", ids);
    }
    readonly property int todayCount: Logic.smartCounts(RemindersService.reminders, new Date()).today

    function add(): void {
        const title = addField.text.trim();
        if (title.length === 0)
            return;
        RemindersService.create({ title: title });
        addField.text = "";
    }

    function openApp(id: string): void {
        GlobalStates.sidebarRightOpen = false;
        GlobalStates.islandDashboardOpen = false;
        RemindersService.open(id);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "task_alt"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: root.todayCount > 0 ? Translation.tr("Reminders · %1 today").arg(String(root.todayCount))
                    : Translation.tr("Reminders")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: root.openApp("")

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                StyledToolTip {
                    text: Translation.tr("Open Reminders")
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.rowGap

            Repeater {
                model: root.shownIds

                RippleButton {
                    id: row
                    required property string modelData
                    readonly property var reminder: RemindersService.reminder(row.modelData)
                    readonly property bool overdue: RemindersService.isOverdue(row.reminder, new Date())
                    readonly property color accent: RemindersService.category(row.reminder?.categoryId)?.color
                        || Appearance.colors.colPrimary

                    Layout.fillWidth: true
                    implicitHeight: root.rowHeight
                    visible: row.reminder !== null
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.openApp(row.modelData)

                    contentItem: RowLayout {
                        spacing: 8

                        // The tick: a disc tinted with the category, turning into a rounded
                        // square with its check on hover (shape is state).
                        Rectangle {
                            id: checkDisc
                            readonly property bool engaged: checkPointer.containsMouse
                            Layout.leftMargin: 4
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: checkDisc.engaged ? Math.min(height / 2, Appearance.rounding.verysmall)
                                : Math.min(height / 2, Appearance.rounding.full)
                            color: ColorUtils.applyAlpha(row.accent, checkDisc.engaged ? 0.32 : 0.18)

                            readonly property var motion: Appearance.animation.elementMoveFast

                            Behavior on radius {
                                enabled: !Appearance.reducedMotion
                                animation: checkDisc.motion.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                enabled: !Appearance.reducedMotion
                                animation: checkDisc.motion.colorAnimation.createObject(this)
                            }

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 14
                                color: row.accent
                                opacity: checkDisc.engaged ? 1 : 0
                            }

                            MouseArea {
                                id: checkPointer
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: RemindersService.complete(row.modelData)
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.reminder?.title || Translation.tr("Untitled reminder")
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }

                        MaterialSymbol {
                            visible: row.reminder?.important ?? false
                            text: "star"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colTertiary
                        }

                        StyledText {
                            Layout.rightMargin: 4
                            visible: (row.reminder?.schedule ?? null) !== null
                            text: row.reminder ? RemindersService.whenText(row.reminder, new Date()) : ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: row.overdue ? Appearance.colors.colError : Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Empty: a glyph over the line, as the Notes widget does.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.shownIds.length === 0
                spacing: 4

                Item {
                    Layout.fillHeight: true
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "task_alt"
                    iconSize: 28
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Nothing to remember")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            Item {
                Layout.fillHeight: true
                visible: root.shownIds.length > 0
            }
        }

        Rectangle {
            id: addBar
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 4
                spacing: 6

                StyledTextInput {
                    id: addField
                    Layout.fillWidth: true
                    clip: true
                    color: Appearance.colors.colOnLayer2
                    onAccepted: root.add()

                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: addField.text.length === 0
                        text: Translation.tr("Add reminder")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1Inactive
                    }
                }

                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: root.add()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "add"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }
    }
}
