pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Alarms: the next one up top, timetable suggestions, then every alarm as a card in a
 * grid that reflows from one column on a narrow window to as many as fit.
 */
Item {
    id: root

    property date now: new Date()
    property bool compact: false
    property bool wide: false

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real gridGap: ClockStyle.gap
    readonly property int columns: Math.max(1, Math.floor((root.width - root.padding * 2 + root.gridGap) / (ClockStyle.alarmCardMinWidth + root.gridGap)))
    readonly property bool showTimetable: (Config.options.clockApp?.showTimetableEvents ?? true) && CalendarService.khalAvailable

    readonly property int alarmCount: AlarmService.alarms.length
    readonly property var next: AlarmService.nextAlarm(root.now)
    readonly property string pageSubtitle: root.next
        ? Translation.tr("Next alarm %1").arg(ClockFormat.relativeDay(root.next.at, root.now) + " · " + ClockFormat.dateTime(root.next.at))
        : Translation.tr("No alarms on")

    function openEditor(index: int): void {
        editorLoader.active = true;
        editorLoader.item.load(index);
        editorLoader.item.open();
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + root.padding + ClockStyle.fabSize + ClockStyle.gapHuge * 2
        clip: true

        ColumnLayout {
            id: content
            x: root.padding
            y: ClockStyle.gapSmall
            width: flick.width - root.padding * 2
            spacing: ClockStyle.gapLarge

            Rectangle {
                id: nextBanner
                Layout.fillWidth: true
                visible: root.next !== null
                implicitHeight: bannerRow.implicitHeight + ClockStyle.gapLarge * 2
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPrimaryContainer

                StaggeredEntrance {
                    index: 0
                    active: !ClockStyle.reducedMotion
                }

                RowLayout {
                    id: bannerRow
                    anchors {
                        fill: parent
                        margins: ClockStyle.gapLarge
                        leftMargin: ClockStyle.cardPadding
                    }
                    spacing: ClockStyle.gapLarge

                    Item {
                        implicitWidth: ClockStyle.fabSize
                        implicitHeight: ClockStyle.fabSize

                        MaterialShape {
                            anchors.fill: parent
                            shapeString: "Cookie7Sided"
                            color: ClockStyle.colPrimary
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "alarm"
                            iconSize: ClockStyle.iconLarge
                            fill: 1
                            color: ClockStyle.colOnPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.next ? AlarmService.untilText(root.next.alarm, root.now) : ""
                            elide: Text.ElideRight
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: ClockStyle.textTitle
                            color: ClockStyle.colOnPrimaryContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.next
                                ? (String(root.next.alarm.label ?? "") || Translation.tr("Alarm")) + " · "
                                    + ClockFormat.relativeDay(root.next.at, root.now) + " " + ClockFormat.dateTime(root.next.at)
                                : ""
                            elide: Text.ElideRight
                            font.pixelSize: ClockStyle.textNormal
                            color: ClockStyle.colOnPrimaryContainer
                            opacity: 0.85
                        }
                    }

                    ClockButton {
                        visible: !root.compact && root.next !== null && (root.next.alarm.days ?? []).includes(true)
                        variant: "text"
                        symbol: "event_busy"
                        label: Translation.tr("Skip")
                        onClicked: AlarmService.skipNext(root.next.index)
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: root.showTimetable
                visible: active && (item?.visible ?? false)
                sourceComponent: TimetableEventsStrip {
                    now: root.now
                }
            }

            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: root.columns
                rowSpacing: root.gridGap
                columnSpacing: root.gridGap

                Repeater {
                    model: root.alarmCount

                    AlarmCard {
                        id: card
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: ClockStyle.alarmCardMinWidth
                        alarm: AlarmService.alarms[card.index] ?? ({})
                        alarmIndex: card.index
                        now: root.now
                        onEditRequested: root.openEditor(card.index)

                        StaggeredEntrance {
                            index: card.index + 1
                            step: ClockStyle.staggerStep
                            active: !ClockStyle.reducedMotion
                        }
                    }
                }
            }
        }
    }

    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.alarmCount === 0
        symbol: "alarm_add"
        shape: "Cookie9Sided"
        title: Translation.tr("No alarms")
        subtitle: Translation.tr("Tap + to wake up on time, or pick an event from your timetable.")
    }

    ClockFab {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: ClockStyle.gapHuge
        }
        symbol: "add"
        label: root.wide ? Translation.tr("Add alarm") : ""
        onClicked: root.openEditor(-1)
    }

    Loader {
        id: editorLoader
        anchors.fill: parent
        active: false
        sourceComponent: AlarmEditorSheet {
            onFullyClosed: editorLoader.active = false
            onTimeRequested: (hour, minute) => {
                timePickerLoader.active = true;
                timePickerLoader.item.open(hour, minute, Translation.tr("Alarm time"));
            }
            onDateRequested: current => {
                datePickerLoader.active = true;
                datePickerLoader.item.open(current.length > 0 ? ClockFormat.parseDay(current) : root.now, Translation.tr("Ring on"));
            }
        }
    }

    Loader {
        id: timePickerLoader
        anchors.fill: parent
        active: false
        z: 200
        sourceComponent: TimePickerPopup {
            keyboardShortcutsEnabled: true
            onAccepted: (hour, minute) => editorLoader.item?.setTime(hour, minute)
            onOpenedChanged: if (!opened) closeTimer.restart()
        }
    }

    Loader {
        id: datePickerLoader
        anchors.fill: parent
        active: false
        z: 200
        sourceComponent: DatePickerPopup {
            onAccepted: date => {
                if (editorLoader.item)
                    editorLoader.item.draftDate = Qt.formatDate(date, "yyyy-MM-dd");
            }
            onOpenedChanged: if (!opened) closeTimer.restart()
        }
    }

    Timer {
        id: closeTimer
        interval: ClockStyle.motionExit.duration + ClockStyle.motionFast.duration
        onTriggered: {
            if (timePickerLoader.item && !timePickerLoader.item.opened)
                timePickerLoader.active = false;
            if (datePickerLoader.item && !datePickerLoader.item.opened)
                datePickerLoader.active = false;
        }
    }
}
