pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Creating or editing an alarm. Works on a draft; nothing reaches AlarmService until Save.
 */
ClockSheet {
    id: root

    property int alarmIndex: -1
    property string draftTime: "08:00"
    property string draftLabel: ""
    property var draftDays: [false, false, false, false, false, false, false]
    property string draftDate: ""

    readonly property bool editing: root.alarmIndex >= 0
    readonly property var alarm: root.editing ? AlarmService.alarms[root.alarmIndex] ?? null : null
    readonly property bool repeats: root.draftDays.includes(true)
    readonly property var timeParts: ClockFormat.alarmParts(root.draftTime)

    signal timeRequested(int hour, int minute)
    signal dateRequested(string current)

    function load(index: int): void {
        root.alarmIndex = index;
        const source = AlarmService.alarms[index];
        if (source) {
            root.draftTime = source.time;
            root.draftLabel = source.label ?? "";
            root.draftDays = Array.from(source.days ?? [false, false, false, false, false, false, false]);
            root.draftDate = String(source.date ?? "");
        } else {
            const now = new Date();
            now.setMinutes(now.getMinutes() + 1);
            root.draftTime = Qt.formatTime(now, "HH:mm");
            root.draftLabel = "";
            root.draftDays = [false, false, false, false, false, false, false];
            root.draftDate = "";
        }
        labelField.text = root.draftLabel;
    }

    function setTime(hour: int, minute: int): void {
        root.draftTime = ClockFormat.pad(hour) + ":" + ClockFormat.pad(minute);
    }

    function setDays(days): void {
        root.draftDays = days;
        if (days.includes(true))
            root.draftDate = "";
    }

    function toggleDay(day: int): void {
        const next = Array.from(root.draftDays);
        next[day] = !next[day];
        root.setDays(next);
    }

    function save(): void {
        const label = labelField.text.trim();
        if (root.editing) {
            AlarmService.updateAlarm(root.alarmIndex, {
                time: root.draftTime,
                label: label.length > 0 ? label : Translation.tr("Alarm"),
                days: root.draftDays,
                date: root.draftDate,
                skipDate: "",
                enabled: true
            });
        } else {
            AlarmService.addAlarm(root.draftTime, label, root.draftDays, root.draftDate);
        }
        root.close();
    }

    title: root.editing ? Translation.tr("Edit alarm") : Translation.tr("New alarm")

    RippleButton {
        id: timeButton
        Layout.fillWidth: true
        implicitHeight: ClockStyle.alarmCardHeight * 0.62
        buttonRadius: ClockStyle.radiusCard
        buttonRadiusPressed: ClockStyle.radiusLarge
        colBackground: ClockStyle.colPrimaryContainer
        colBackgroundHover: ClockStyle.colPrimaryContainerHover
        colRipple: ClockStyle.colPrimaryContainerActive
        onClicked: {
            const parts = root.draftTime.split(":");
            root.timeRequested(parseInt(parts[0]) || 0, parseInt(parts[1]) || 0);
        }

        contentItem: Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: `${root.timeParts.hours}:${root.timeParts.minutes}`
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: timeButton.height * 0.62
                    color: ClockStyle.colOnPrimaryContainer
                    animateChange: !ClockStyle.reducedMotion
                }

                StyledText {
                    visible: root.timeParts.meridiem.length > 0
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: timeButton.height * 0.14
                    text: root.timeParts.meridiem
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigits
                    font.pixelSize: timeButton.height * 0.2
                    color: ClockStyle.colOnPrimaryContainer
                }
            }

            MaterialSymbol {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: ClockStyle.gapLarge
                }
                text: "edit"
                iconSize: ClockStyle.iconSmall
                color: ClockStyle.colOnPrimaryContainer
                opacity: timeButton.hovered ? 1 : 0.6
            }
        }
    }

    MaterialTextField {
        id: labelField
        Layout.fillWidth: true
        placeholderText: Translation.tr("Label")
        onAccepted: root.save()
    }

    StyledText {
        Layout.topMargin: ClockStyle.gapSmall
        text: Translation.tr("Repeat")
        font.pixelSize: ClockStyle.textNormal
        font.weight: Font.DemiBold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        ClockChip {
            label: Translation.tr("Once")
            selected: !root.repeats
            onClicked: root.setDays([false, false, false, false, false, false, false])
        }
        ClockChip {
            label: Translation.tr("Weekdays")
            selected: String(root.draftDays) === String([false, true, true, true, true, true, false])
            onClicked: root.setDays([false, true, true, true, true, true, false])
        }
        ClockChip {
            label: Translation.tr("Weekends")
            selected: String(root.draftDays) === String([true, false, false, false, false, false, true])
            onClicked: root.setDays([true, false, false, false, false, false, true])
        }
        ClockChip {
            label: Translation.tr("Every day")
            selected: !root.draftDays.includes(false)
            onClicked: root.setDays([true, true, true, true, true, true, true])
        }
    }

    ClockDayChips {
        Layout.fillWidth: true
        days: root.draftDays
        onToggled: day => root.toggleDay(day)
    }

    Flow {
        Layout.fillWidth: true
        visible: !root.repeats
        spacing: ClockStyle.gapSmall

        ClockChip {
            symbol: "calendar_month"
            label: root.draftDate.length > 0
                ? ClockFormat.relativeDay(ClockFormat.parseDay(root.draftDate), new Date())
                : Translation.tr("Pick a date")
            selected: root.draftDate.length > 0
            onClicked: root.dateRequested(root.draftDate)
        }
        ClockChip {
            visible: root.draftDate.length > 0
            symbol: "close"
            label: Translation.tr("Next occurrence")
            onClicked: root.draftDate = ""
        }
        ClockChip {
            visible: root.draftDate.length > 0
            symbol: "calendar_view_month"
            label: Translation.tr("Open in timetable")
            onClicked: {
                GlobalStates.openTimetableAt(root.draftDate);
                root.close();
            }
        }
    }

    ClockSettingsRow {
        visible: root.editing && root.repeats && Boolean(root.alarm?.enabled)
        first: true
        last: true
        symbol: "event_busy"
        title: Translation.tr("Skip next alarm")
        description: {
            const next = AlarmService.nextOccurrence(root.alarm, new Date());
            return next ? ClockFormat.relativeDay(next, new Date()) + " · " + ClockFormat.dateTime(next) : "";
        }
        color: ClockStyle.colSurfaceHighest

        StyledSwitch {
            checked: AlarmService.isSkipped(root.alarm)
            checkable: false
            onClicked: {
                if (AlarmService.isSkipped(root.alarm))
                    AlarmService.unskip(root.alarmIndex);
                else
                    AlarmService.skipNext(root.alarmIndex);
            }
        }
    }

    actions: [
        ClockButton {
            visible: root.editing
            variant: "text"
            danger: true
            iconOnly: !root.wide
            symbol: "delete"
            label: Translation.tr("Delete")
            onClicked: {
                AlarmService.deleteAlarm(root.alarmIndex);
                root.close();
            }
        },
        ClockButton {
            visible: root.editing
            variant: "text"
            iconOnly: !root.wide
            symbol: "content_copy"
            label: Translation.tr("Duplicate")
            onClicked: {
                AlarmService.duplicateAlarm(root.alarmIndex);
                root.close();
            }
        },
        Item {
            Layout.fillWidth: true
        },
        ClockButton {
            variant: "text"
            label: Translation.tr("Cancel")
            onClicked: root.close()
        },
        ClockButton {
            variant: "filled"
            symbol: "check"
            label: Translation.tr("Save")
            onClicked: root.save()
        }
    ]
}
