pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A reminder alerting on the island: what it is and when, Snooze and Complete.
 *
 * Complete is the wide one, like the alarm's Stop: it is what the reminder is for. A
 * click on the text opens it in the Reminders tab; the close mark dismisses it and
 * leaves a notification behind.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property var reminder: RemindersService.ringing
    readonly property int snoozeMinutes: RemindersService.snoozeMinutes

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 12
        spacing: 10

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: RemindersService.stopRinging(true)

            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "close"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: RemindersService.ringingLevel === "strong" ? "alarm" : "notifications_active"
            fill: 1
            iconSize: 24
            color: Appearance.colors.colPrimary
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: RemindersService.open(root.reminder?.id ?? "")
            }

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: -2

                StyledText {
                    Layout.fillWidth: true
                    text: root.reminder ? (root.reminder.title || Translation.tr("Reminder")) : ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.reminder ? RemindersService.whenText(root.reminder, new Date()) : ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: snoozeLabel.implicitWidth + 24
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: RemindersService.snooze(root.reminder.id, root.snoozeMinutes)

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
            implicitWidth: 104
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            onClicked: RemindersService.complete(root.reminder.id)

            contentItem: StyledText {
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Translation.tr("Complete")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
