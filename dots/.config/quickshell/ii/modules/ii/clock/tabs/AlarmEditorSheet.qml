pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Creating or editing an alarm, in the side sheet. The time and the date open the shell's
 * own pickers (the dashboard clock's TimePickerPopup, the one the timetable's rail
 * mirrors), centred over the app. It works on a draft: nothing reaches AlarmService until
 * Save.
 */
ClockSheet {
    id: root

    property int alarmIndex: -1
    property string draftTime: "08:00"
    property var draftDays: [false, false, false, false, false, false, false]
    property string draftDate: ""
    /// Set once the draft is loaded: the time only animates changes the user makes.
    property bool ready: false
    /// New alarms can bring a task along, due that day and tied to the alarm.
    property bool alsoTask: false
    readonly property bool linkedToTask: root.editing && (String(root.alarm?.taskId ?? "").length > 0 || String(root.alarm?.taskContent ?? "").length > 0)

    readonly property bool editing: root.alarmIndex >= 0
    readonly property var alarm: root.editing ? AlarmService.alarms[root.alarmIndex] ?? null : null
    readonly property bool repeats: root.draftDays.includes(true)
    readonly property var draftDay: root.draftDate.length > 0 ? ClockFormat.parseDay(root.draftDate) : null
    readonly property var timeParts: ClockFormat.alarmParts(root.draftTime)
    readonly property var presets: [
        { label: Translation.tr("Once"), days: [false, false, false, false, false, false, false] },
        { label: Translation.tr("Weekdays"), days: [false, true, true, true, true, true, false] },
        { label: Translation.tr("Weekends"), days: [true, false, false, false, false, false, true] },
        { label: Translation.tr("Every day"), days: [true, true, true, true, true, true, true] }
    ]

    function load(): void {
        const source = AlarmService.alarms[root.alarmIndex];
        if (root.editing && source) {
            root.draftTime = source.time;
            labelField.text = source.label ?? "";
            root.draftDays = Array.from(source.days ?? [false, false, false, false, false, false, false]);
            root.draftDate = String(source.date ?? "");
        } else {
            const now = new Date();
            now.setMinutes(now.getMinutes() + 1);
            root.draftTime = Qt.formatTime(now, "HH:mm");
            labelField.text = "";
            root.draftDays = [false, false, false, false, false, false, false];
            root.draftDate = "";
        }
    }

    function pickTime(): void {
        const parts = root.draftTime.split(":");
        root.host?.pickers?.pickTime(parseInt(parts[0]) || 0, parseInt(parts[1]) || 0, Translation.tr("Alarm time"),
            (hour, minute) => root.setTime(hour, minute));
    }

    function pickDate(): void {
        root.host?.pickers?.pickDate(root.draftDay ?? new Date(), Translation.tr("Rings on"),
            date => root.draftDate = Qt.formatDate(date, "yyyy-MM-dd"));
    }

    /** The day a one-off alarm at the draft time rings next: today if still ahead, else tomorrow. */
    function nextDay() {
        const now = new Date();
        const parts = root.draftTime.split(":").map(Number);
        const at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), parts[0] || 0, parts[1] || 0);
        if (at.getTime() <= now.getTime())
            at.setDate(at.getDate() + 1);
        return new Date(at.getFullYear(), at.getMonth(), at.getDate());
    }

    function setTime(hour: int, minute: int): void {
        root.draftTime = ClockFormat.pad(hour) + ":" + ClockFormat.pad(minute);
    }

    function setDays(days): void {
        root.draftDays = Array.from(days);
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
        } else if (root.alsoTask) {
            // The task comes first: the alarm is tied to it and leaves with it.
            const day = root.draftDate.length > 0 ? root.draftDay : root.nextDay();
            const task = {
                id: "local-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8),
                content: label.length > 0 ? label : Translation.tr("Alarm"),
                done: false,
                date: day
            };
            Todo.addItem(task);
            AlarmService.setAlarmForTask(task, root.draftTime, Qt.formatDate(day, "yyyy-MM-dd"));
        } else {
            AlarmService.addAlarm(root.draftTime, label, root.draftDays, root.draftDate);
        }
        root.close();
    }

    title: root.editing ? Translation.tr("Edit alarm") : Translation.tr("New alarm")
    subtitle: root.editing && root.alarm?.enabled ? AlarmService.untilText(root.alarm, new Date()) : ""

    Component.onCompleted: {
        root.load();
        Qt.callLater(() => root.ready = true);
    }
    // The sheet stays put while the list under it changes; an alarm deleted from its
    // tile must not leave a sheet editing whatever slid into its index.
    Connections {
        target: AlarmService
        function onAlarmsChanged() {
            if (root.editing && !AlarmService.alarms[root.alarmIndex])
                root.close();
        }
    }

    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
            root.save();
            event.accepted = true;
        }
    }

    headerActions: [
        ClockIconButton {
            visible: root.editing
            symbol: "content_copy"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            tooltip: Translation.tr("Duplicate")
            onClicked: {
                AlarmService.duplicateAlarm(root.alarmIndex);
                root.close();
            }
        },
        ClockIconButton {
            visible: root.editing
            symbol: "delete"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            colIcon: ClockStyle.colError
            tooltip: Translation.tr("Delete")
            onClicked: {
                const index = root.alarmIndex;
                root.alarmIndex = -1;
                AlarmService.deleteAlarm(index);
                root.close();
            }
        }
    ]

    // ── Time ────────────────────────────────────────────────────────────
    // The timetable rail's Starts / Ends tile, grown to be the sheet's headline: the whole
    // tile opens the picker, and it fills with the primary container under the pointer.
    Rectangle {
        id: timeTile
        Layout.fillWidth: true
        implicitHeight: 124
        radius: Appearance.rounding.small
        color: timePointer.containsMouse ? ClockStyle.colPrimaryContainer : ClockStyle.colField

        readonly property color colContent: timePointer.containsMouse ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        MouseArea {
            id: timePointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.pickTime()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                MaterialSymbol {
                    text: "schedule"
                    iconSize: Appearance.font.pixelSize.smallie
                    color: timePointer.containsMouse ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Alarm time")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: timePointer.containsMouse ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                    elide: Text.ElideRight
                }

                MaterialSymbol {
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.normal
                    color: timeTile.colContent
                    opacity: timePointer.containsMouse ? 1 : 0.5
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        text: root.timeParts.hours + ":" + root.timeParts.minutes
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 68
                        color: timeTile.colContent
                        animateChange: root.ready && !ClockStyle.reducedMotion
                    }

                    StyledText {
                        visible: root.timeParts.meridiem.length > 0
                        Layout.alignment: Qt.AlignBottom
                        Layout.leftMargin: 6
                        Layout.bottomMargin: 12
                        text: root.timeParts.meridiem
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigits
                        font.pixelSize: 22
                        color: timeTile.colContent
                    }
                }
            }
        }
    }

    // ── Label ───────────────────────────────────────────────────────────
    ClockFormField {
        id: labelField
        symbol: "label"
        caption: Translation.tr("Label")
        placeholder: Translation.tr("What is it for?")
        onAccepted: root.save()
    }

    // ── Repeat ──────────────────────────────────────────────────────────
    StyledText {
        Layout.topMargin: 2
        text: Translation.tr("Repeat")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.presets

            ClockFormChip {
                required property var modelData
                label: modelData.label
                selected: String(root.draftDays) === String(modelData.days)
                onTriggered: root.setDays(modelData.days)
            }
        }
    }

    ClockDayChips {
        Layout.fillWidth: true
        chipSize: 38
        days: root.draftDays
        onToggled: day => root.toggleDay(day)
    }

    // ── Date (one-off alarms) ───────────────────────────────────────────
    ClockFormPicker {
        visible: !root.repeats
        symbol: "calendar_month"
        shapeKind: MaterialShape.Shape.Cookie12Sided
        caption: Translation.tr("Rings on")
        value: root.draftDay
            ? ClockFormat.relativeDay(root.draftDay, new Date()) + " · " + Qt.locale().toString(root.draftDay, "dddd, d MMMM")
            : Translation.tr("Next time it comes round")
        onTriggered: root.pickDate()

        ClockIconButton {
            visible: root.draftDate.length > 0
            symbol: "close"
            size: 32
            iconSize: Appearance.font.pixelSize.large
            tooltip: Translation.tr("Next occurrence")
            onClicked: root.draftDate = ""
        }
    }

    ClockFormPicker {
        visible: !root.repeats && root.draftDate.length > 0
        symbol: "calendar_view_month"
        shapeKind: MaterialShape.Shape.Cookie6Sided
        caption: Translation.tr("Timetable")
        value: Translation.tr("Open in timetable")
        onTriggered: {
            GlobalStates.openTimetableAt(root.draftDate);
            root.close();
        }
    }

    // ── Task ────────────────────────────────────────────────────────────
    ClockFormToggle {
        visible: !root.editing && !root.repeats
        symbol: "task_alt"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        label: Translation.tr("Also add as a task")
        description: Translation.tr("Due that day; the alarm goes away when the task is done")
        checked: root.alsoTask
        onToggled: checked => root.alsoTask = checked
    }

    ClockFormPicker {
        visible: root.linkedToTask
        symbol: "task_alt"
        shapeKind: MaterialShape.Shape.Cookie9Sided
        caption: Translation.tr("Linked task")
        value: String(root.alarm?.taskContent ?? root.alarm?.label ?? "")
        showChevron: false
        highlighted: true
    }

    // ── Skip ────────────────────────────────────────────────────────────
    ClockFormToggle {
        visible: root.editing && root.repeats && Boolean(root.alarm?.enabled)
        symbol: "event_busy"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        label: Translation.tr("Skip next alarm")
        description: {
            const next = AlarmService.nextOccurrence(root.alarm, new Date());
            return next ? ClockFormat.relativeDay(next, new Date()) + " · " + ClockFormat.dateTime(next) : "";
        }
        checked: AlarmService.isSkipped(root.alarm)
        onToggled: checked => {
            if (checked)
                AlarmService.skipNext(root.alarmIndex);
            else
                AlarmService.unskip(root.alarmIndex);
        }
    }

    actions: [
        ClockSheetAction {
            label: Translation.tr("Cancel")
            symbol: "close"
            onClicked: root.close()
        },
        ClockSheetAction {
            primary: true
            label: root.editing ? Translation.tr("Save changes") : Translation.tr("Create alarm")
            symbol: root.editing ? "check" : "alarm_add"
            onClicked: root.save()
        }
    ]
}
