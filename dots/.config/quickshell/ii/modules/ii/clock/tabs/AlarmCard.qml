import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One alarm, Pixel style: the time in huge condensed digits, what it repeats on, and
 * its switch. An enabled alarm is a filled tonal card; a disabled one recedes.
 */
Rectangle {
    id: root

    required property var alarm
    required property int alarmIndex
    property date now: new Date()

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property color colOn: ClockStyle.colActiveCard
    readonly property color colOnHover: ClockStyle.colTertiaryContainerHover
    readonly property color colOnContent: ClockStyle.colOnActiveCard
    readonly property color colOff: ClockStyle.colIdleCard
    readonly property color colOffHover: ClockStyle.colSurfaceHover
    readonly property color colOffContent: ClockStyle.colOnIdleCard
    readonly property bool stacked: root.width < ClockStyle.alarmCardMinWidth * 1.2
    readonly property real digitSize: root.stacked
        ? Math.max(ClockStyle.alarmDigitMin, Math.min((root.height - ClockStyle.cardPadding * 2 - ClockStyle.buttonHeight * 2) / 1.55, root.width * 0.44))
        : Math.max(ClockStyle.alarmDigitMin, Math.min(root.height * 0.42, root.width * 0.34))

    readonly property bool enabledAlarm: Boolean(root.alarm?.enabled)
    readonly property bool ringing: AlarmService.ringingAlarmIndex === root.alarmIndex
    readonly property var timeParts: ClockFormat.alarmParts(root.alarm?.time)
    readonly property color colContent: root.enabledAlarm ? root.colOnContent : root.colOffContent

    signal editRequested()

    implicitHeight: root.stacked ? ClockStyle.alarmCardHeightStacked : ClockStyle.alarmCardHeight
    radius: ClockStyle.radiusCard
    color: cardMouse.containsMouse
        ? (root.enabledAlarm ? root.colOnHover : root.colOffHover)
        : (root.enabledAlarm ? root.colOn : root.colOff)

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.editRequested()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
        }
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapTiny + 2

            MaterialSymbol {
                visible: String(root.alarm?.eventUid ?? "").length > 0
                text: "event"
                iconSize: ClockStyle.iconSmall
                color: root.colContent
            }

            StyledText {
                Layout.fillWidth: true
                text: String(root.alarm?.label ?? "").length > 0 ? root.alarm.label : Translation.tr("Alarm")
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                color: root.colContent
            }

            MaterialSymbol {
                visible: AlarmService.isSkipped(root.alarm)
                text: "event_busy"
                iconSize: ClockStyle.iconSmall
                color: root.colContent
            }

            MaterialSymbol {
                visible: root.ringing
                text: "notifications_active"
                iconSize: ClockStyle.iconSmall
                fill: 1
                color: root.colContent
            }
        }

        Item {
            id: timeArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridLayout {
                anchors.verticalCenter: parent.verticalCenter
                columns: root.stacked ? 2 : 3
                rows: root.stacked ? 2 : 1
                flow: GridLayout.LeftToRight
                columnSpacing: root.stacked ? ClockStyle.gapSmall : 0
                rowSpacing: -root.digitSize * 0.18

                StyledText {
                    Layout.row: 0
                    Layout.column: 0
                    text: root.timeParts.hours + (root.stacked ? "" : ":")
                    font.family: ClockStyle.fontMain
                    font.variableAxes: root.enabledAlarm ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                    font.pixelSize: root.digitSize
                    color: root.colContent
                }

                StyledText {
                    Layout.row: root.stacked ? 1 : 0
                    Layout.column: root.stacked ? 0 : 1
                    text: root.timeParts.minutes
                    font.family: ClockStyle.fontMain
                    font.variableAxes: root.enabledAlarm ? ClockStyle.axesDigitsBold : ClockStyle.axesDigits
                    font.pixelSize: root.digitSize
                    color: root.colContent
                }

                StyledText {
                    Layout.row: root.stacked ? 1 : 0
                    Layout.column: root.stacked ? 1 : 2
                    Layout.alignment: Qt.AlignBottom
                    Layout.leftMargin: root.stacked ? 0 : ClockStyle.gapSmall
                    Layout.bottomMargin: root.digitSize * 0.14
                    visible: root.timeParts.meridiem.length > 0
                    text: root.timeParts.meridiem
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: root.digitSize * 0.34
                    color: root.colContent
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: ClockFormat.repeatSummary(root.alarm, root.now)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall + 1
                    color: root.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.enabledAlarm && text.length > 0
                    text: AlarmService.untilText(root.alarm, root.now)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.8
                }
            }

            StyledSwitch {
                checked: root.enabledAlarm
                checkable: false
                activeColor: ClockStyle.colPrimary
                onClicked: AlarmService.toggleAlarm(root.alarmIndex)
            }
        }
    }
}
