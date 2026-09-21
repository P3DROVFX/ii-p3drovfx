pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A ringing alarm: its time and label, Snooze and Stop.
 *
 * Stop is the wide one. A half-awake hand is aiming at the island, and missing Stop for
 * Snooze only buys nine minutes, while the reverse loses the alarm.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var alarm: AlarmService.ringingAlarm
    readonly property int snoozeMinutes: 9

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 12
        spacing: 12

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "alarm"
            fill: 1
            iconSize: 26
            color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2

            StyledText {
                Layout.fillWidth: true
                text: root.alarm ? root.alarm.time : ""
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Bold
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnLayer0
            }

            StyledText {
                Layout.fillWidth: true
                text: root.alarm && root.alarm.label ? root.alarm.label : Translation.tr("Alarm")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: snoozeLabel.implicitWidth + 28
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: AlarmService.snooze(root.snoozeMinutes)

            contentItem: StyledText {
                id: snoozeLabel
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Snooze %1 min").arg(root.snoozeMinutes)
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 96
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: AlarmService.stopRinging()

            contentItem: StyledText {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Stop")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
