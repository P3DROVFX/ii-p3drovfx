import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Today's count with − / +, the goal, and the week as a chart with day
 * initials (days that met the goal in tertiary, today in primary).
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property int glasses: WaterReminderService.glassesDrunk
    readonly property int goal: Math.max(1, WaterReminderService.dailyGoal)
    readonly property var week: panel.tile?.week ?? []
    readonly property int weekTotal: panel.week.reduce((sum, day) => sum + day.glasses, 0)
    readonly property int glassMl: panel.tile?.glassMl ?? 250

    spacing: 8

    // Today: the count large, with − and + as equal-height controls.
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        RippleButton {
            implicitWidth: 64
            implicitHeight: 96
            enabled: panel.glasses > 0
            opacity: enabled ? 1 : 0.4
            buttonRadius: ClockStyle.radiusLarge
            buttonRadiusPressed: ClockStyle.radiusNormal
            colBackground: ClockStyle.colSecondaryContainer
            colBackgroundHover: ClockStyle.colSecondaryContainerHover
            colRipple: ClockStyle.colSecondaryContainerActive
            onClicked: WaterReminderService.drink(-1)
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "remove"
                iconSize: 26
                color: ClockStyle.colOnSecondaryContainer
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 96
            radius: ClockStyle.radiusLarge
            color: panel.glasses >= panel.goal ? ClockStyle.colPrimaryContainer : ClockStyle.colField
            readonly property color ink: panel.glasses >= panel.goal ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

            // The share of the goal, as water along the foot of the block.
            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 10
                height: 6
                radius: 3
                width: (parent.width - 20) * Math.min(1, panel.glasses / panel.goal)
                color: ClockStyle.colPrimary
                Behavior on width {
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
            }
            RowLayout {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -3
                spacing: 4
                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    text: String(panel.glasses)
                    color: parent.parent.ink
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: 60
                }
                StyledText {
                    Layout.alignment: Qt.AlignBaseline
                    text: "/ " + panel.goal
                    color: parent.parent.ink
                    opacity: 0.6
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: 28
                }
            }
        }

        RippleButton {
            implicitWidth: 64
            implicitHeight: 96
            buttonRadius: ClockStyle.radiusLarge
            buttonRadiusPressed: ClockStyle.radiusNormal
            colBackground: ClockStyle.colPrimary
            colBackgroundHover: ClockStyle.colPrimaryHover
            colRipple: ClockStyle.colPrimaryActive
            onClicked: WaterReminderService.drink(1)
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "water_full"
                iconSize: 28
                fill: 1
                color: ClockStyle.colOnPrimary
            }
        }
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: Translation.tr("This week · %1 glasses · %2 L").arg(panel.weekTotal).arg((panel.weekTotal * panel.glassMl / 1000).toFixed(1))
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 150
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8
            Repeater {
                model: panel.week
                delegate: ColumnLayout {
                    id: day
                    required property var modelData
                    required property int index
                    readonly property bool today: day.index === 6
                    readonly property bool met: day.modelData.glasses >= panel.goal
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 4
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: day.modelData.glasses > 0 ? String(day.modelData.glasses) : ""
                        color: ClockStyle.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, 26)
                            height: Math.max(day.modelData.glasses > 0 ? width : 4, parent.height * Math.min(1, day.modelData.glasses / panel.goal))
                            radius: width / 2
                            color: day.today ? ClockStyle.colPrimary
                                : day.met ? ClockStyle.colTertiary
                                : day.modelData.glasses > 0 ? ClockStyle.colSecondaryContainer
                                : ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.08)
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDate(day.modelData.date, "ddd").charAt(0).toUpperCase()
                        color: day.today ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: day.today ? Font.Black : Font.DemiBold
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 52
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colField
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Daily goal")
                color: ClockStyle.colOnSurface
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
            }
            ClockStepper {
                value: panel.goal
                from: 1
                to: 30
                format: value => Translation.tr("%1 glasses").arg(value)
                onMoved: value => Config.options.background.widgets.water_reminder.dailyGoal = value
            }
        }
    }
}
