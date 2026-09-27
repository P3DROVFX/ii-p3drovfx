import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One alarm as a Material 3 Expressive tile: the hours stacked over the minutes in tall
 * condensed digits that fill the tile, what it repeats on, and its switch.
 *
 * An enabled alarm is a primary container and its switch the primary itself — one hue
 * family. A disabled one drops to the pane colour with thin digits, the way the Pixel
 * clock outlines an alarm that is off. Hovering reveals duplicate and delete the way the
 * dashboard's to-do rows do: one animated extent that elides the label as it grows.
 */
Rectangle {
    id: root

    required property var alarm
    required property int alarmIndex
    property date now: new Date()
    property bool editing: false
    /// The settled width to size the digits by; the live width may be mid-animation.
    property real layoutWidth: root.width

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property bool enabledAlarm: Boolean(root.alarm?.enabled)
    readonly property bool ringing: AlarmService.ringingAlarmIndex === root.alarmIndex
    readonly property var timeParts: ClockFormat.alarmParts(root.alarm?.time)
    // The digits get whatever the label row and the footer leave, and stack only when
    // stacking actually buys a bigger number — never at a size that pushes the footer out.
    readonly property real innerWidth: root.layoutWidth - ClockStyle.cardPadding - ClockStyle.gapLarge
    readonly property real timeHeight: root.height - ClockStyle.gapLarge - ClockStyle.cardPadding - 36 - 52
    readonly property real stackedSize: Math.min(root.timeHeight / 1.62, root.innerWidth * 0.46)
    readonly property real inlineSize: Math.min(root.timeHeight * 0.95, root.innerWidth / 2.7)
    readonly property bool stacked: root.stackedSize > root.inlineSize * 1.2
    readonly property real digitSize: Math.round(Math.max(28, root.stacked ? root.stackedSize : root.inlineSize))
    readonly property color colContainer: root.enabledAlarm ? ClockStyle.colActiveCard : ClockStyle.colIdleCard
    readonly property color colContainerHover: root.enabledAlarm ? ClockStyle.colActiveCardHover : ClockStyle.colIdleCardHover
    readonly property color colContent: root.enabledAlarm ? ClockStyle.colOnActiveCard : ClockStyle.colOnIdleCard

    // Switching an alarm on thickens its digits. The variable font's weight and width
    // axes are interpolated rather than swapped between two presets, so the numbers swell
    // into their bold cut with the switch instead of snapping to it.
    property real boldness: root.enabledAlarm ? 1 : 0
    Behavior on boldness {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation {
            duration: ClockStyle.motionDefault.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
        }
    }
    readonly property var digitAxes: ({
        "wght": ClockStyle.axesDigits.wght + (ClockStyle.axesDigitsBold.wght - ClockStyle.axesDigits.wght) * root.boldness,
        "wdth": ClockStyle.axesDigits.wdth + (ClockStyle.axesDigitsBold.wdth - ClockStyle.axesDigits.wdth) * root.boldness,
        "ROND": 100
    })
    property color colDigits: root.colContent
    Behavior on colDigits {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }
    readonly property bool engaged: cardHover.hovered || editButton.activeFocus || duplicateButton.activeFocus || deleteButton.activeFocus

    signal editRequested()

    radius: ClockStyle.radiusCard
    color: root.editing ? ClockStyle.colSecondaryContainer : root.engaged ? root.colContainerHover : root.colContainer

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.editRequested()
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.gapLarge
        }
        spacing: 0

        // ── Label and hover actions ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            spacing: 6

            MaterialSymbol {
                visible: String(root.alarm?.eventUid ?? "").length > 0
                text: "event"
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

            StyledText {
                id: labelText
                Layout.fillWidth: true
                text: String(root.alarm?.label ?? "").length > 0 ? root.alarm.label : Translation.tr("Alarm")
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textNormal + 1
                font.weight: Font.DemiBold
                color: root.colContent

                HoverHandler {
                    id: labelHover
                }
                StyledToolTip {
                    extraVisibleCondition: labelHover.hovered && labelText.truncated
                    text: labelText.text
                }
            }

            MaterialSymbol {
                visible: AlarmService.isSkipped(root.alarm)
                text: "event_busy"
                iconSize: ClockStyle.iconSmall
                color: root.colContent

                HoverHandler {
                    id: skipHover
                }
                StyledToolTip {
                    extraVisibleCondition: skipHover.hovered
                    text: Translation.tr("Next one skipped")
                }
            }

            // The world clock's reveal: one animated extent slides the actions in from
            // the right and elides the label with the same motion.
            Item {
                id: actionSlot
                property real revealProgress: root.engaged ? 1 : 0

                Layout.preferredWidth: (actionRow.implicitWidth + 4) * actionSlot.revealProgress
                Layout.preferredHeight: actionRow.implicitHeight
                clip: true

                Behavior on revealProgress {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: actionRow
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    opacity: actionSlot.revealProgress
                    enabled: root.engaged

                    ClockCardAction {
                        id: editButton
                        symbol: "edit"
                        tip: Translation.tr("Edit alarm")
                        colContent: root.colContent
                        onClicked: root.editRequested()
                    }
                    ClockCardAction {
                        id: duplicateButton
                        symbol: "content_copy"
                        tip: Translation.tr("Duplicate")
                        colContent: root.colContent
                        onClicked: AlarmService.duplicateAlarm(root.alarmIndex)
                    }
                    ClockCardAction {
                        id: deleteButton
                        symbol: "delete"
                        tip: Translation.tr("Delete")
                        danger: true
                        onClicked: AlarmService.deleteAlarm(root.alarmIndex)
                    }
                }
            }
        }

        // ── Time ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            GridLayout {
                anchors.verticalCenter: parent.verticalCenter
                columns: root.stacked ? 2 : 3
                flow: GridLayout.LeftToRight
                columnSpacing: root.stacked ? ClockStyle.gapSmall : 0
                rowSpacing: -root.digitSize * 0.2

                StyledText {
                    Layout.row: 0
                    Layout.column: 0
                    text: root.timeParts.hours + (root.stacked ? "" : ":")
                    font.family: ClockStyle.fontMain
                    font.variableAxes: root.digitAxes
                    font.pixelSize: root.digitSize
                    color: root.colDigits
                }

                StyledText {
                    Layout.row: root.stacked ? 1 : 0
                    Layout.column: root.stacked ? 0 : 1
                    text: root.timeParts.minutes
                    font.family: ClockStyle.fontMain
                    font.variableAxes: root.digitAxes
                    font.pixelSize: root.digitSize
                    color: root.colDigits
                }

                StyledText {
                    Layout.row: root.stacked ? 1 : 0
                    Layout.column: root.stacked ? 1 : 2
                    Layout.alignment: Qt.AlignBottom
                    Layout.leftMargin: root.stacked ? 0 : ClockStyle.gapSmall
                    Layout.bottomMargin: root.digitSize * 0.16
                    visible: root.timeParts.meridiem.length > 0
                    text: root.timeParts.meridiem
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: root.digitSize * 0.3
                    color: root.colDigits
                }
            }
        }

        // ── Repeat and switch ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            spacing: ClockStyle.gap

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: ClockFormat.repeatSummary(root.alarm, root.now)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                    color: root.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.enabledAlarm && text.length > 0
                    text: AlarmService.untilText(root.alarm, root.now)
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal
                    color: root.colContent
                    opacity: 0.8
                }
            }

            StyledSwitch {
                // Full M3 size: the one control a tile exists for.
                sizeScale: 1.15
                checked: root.enabledAlarm
                checkable: false
                activeColor: ClockStyle.colPrimary
                activeThumbColor: ClockStyle.colOnPrimary
                onClicked: AlarmService.toggleAlarm(root.alarmIndex)
            }
        }
    }
}
