pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Creating or editing a focus schedule. The two times are tall tiles that open the
 * shell's time picker, centred over the page; the days are the clock's day chips; the
 * apps are either all of them or a picked set.
 */
ClockSheet {
    id: root

    property var source: null

    readonly property bool editing: root.source !== null && root.source !== undefined
    readonly property string editingId: root.editing ? "s:" + root.source.id : ""

    property string draftStart: "22:00"
    property string draftEnd: "07:00"
    property var draftDays: [true, true, true, true, true, true, true]
    property var draftKeys: []
    property bool draftAllApps: false
    property bool draftStrict: false
    property bool ready: false

    readonly property bool canSave: (root.draftAllApps || root.draftKeys.length > 0) && root.draftStart !== root.draftEnd
    readonly property var presets: [
        { name: Translation.tr("Work hours"), start: "09:00", end: "18:00", days: [false, true, true, true, true, true, false], symbol: "work" },
        { name: Translation.tr("Evening"), start: "19:00", end: "22:00", days: [true, true, true, true, true, true, true], symbol: "nights_stay" },
        { name: Translation.tr("Night"), start: "23:00", end: "07:00", days: [true, true, true, true, true, true, true], symbol: "bedtime" }
    ]
    readonly property int spanMinutes: {
        const start = ScreenTimeLimits.minutesOf(root.draftStart);
        const end = ScreenTimeLimits.minutesOf(root.draftEnd);
        return end > start ? end - start : end + 24 * 60 - start;
    }

    function load(): void {
        if (!root.editing)
            return;
        root.draftStart = root.source.start ?? "22:00";
        root.draftEnd = root.source.end ?? "07:00";
        root.draftDays = Array.from(root.source.days ?? [true, true, true, true, true, true, true]);
        root.draftKeys = Array.from(root.source.keys ?? []);
        root.draftAllApps = root.source.allApps === true;
        root.draftStrict = root.source.strict === true;
        nameField.text = root.source.name ?? "";
    }

    function pad(n: int): string {
        return String(n).padStart(2, "0");
    }

    function pick(which: string): void {
        const value = which === "start" ? root.draftStart : root.draftEnd;
        const parts = value.split(":");
        root.host?.pickers?.pickTime(parseInt(parts[0]) || 0, parseInt(parts[1]) || 0,
            which === "start" ? Translation.tr("Starts at") : Translation.tr("Ends at"),
            (hour, minute) => {
                const text = root.pad(hour) + ":" + root.pad(minute);
                if (which === "start")
                    root.draftStart = text;
                else
                    root.draftEnd = text;
            });
    }

    function toggleKey(key: string): void {
        const next = Array.from(root.draftKeys);
        const index = next.indexOf(key);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(key);
        root.draftKeys = next;
    }

    function toggleDay(day: int): void {
        const next = Array.from(root.draftDays);
        next[day] = !next[day];
        root.draftDays = next;
    }

    function save(): void {
        if (!root.canSave)
            return;
        const schedule = {
            name: nameField.text.trim(),
            start: root.draftStart,
            end: root.draftEnd,
            days: root.draftDays,
            keys: root.draftAllApps ? [] : root.draftKeys,
            allApps: root.draftAllApps,
            strict: root.draftStrict && ScreenTimeLimits.hasPin,
            enabled: true
        };
        if (root.editing)
            schedule.id = root.source.id;
        ScreenTimeLimits.saveSchedule(schedule);
        root.close();
    }

    title: root.editing ? Translation.tr("Edit schedule") : Translation.tr("New schedule")
    subtitle: Translation.tr("%1 a day").arg(ScreenTimeLimits.formatMinutes(root.spanMinutes))

    Component.onCompleted: {
        root.load();
        Qt.callLater(() => root.ready = true);
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
            symbol: "delete"
            size: 38
            iconSize: Appearance.font.pixelSize.larger
            colIcon: ClockStyle.colError
            tooltip: Translation.tr("Delete")
            onClicked: {
                ScreenTimeLimits.removeSchedule(root.source.id);
                root.close();
            }
        }
    ]

    // Presets fill the times and days in one go; a new schedule starts from them.
    Flow {
        visible: !root.editing
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.presets

            ClockFormChip {
                required property var modelData
                label: modelData.name
                symbol: modelData.symbol
                selected: root.draftStart === modelData.start && root.draftEnd === modelData.end && String(root.draftDays) === String(modelData.days)
                onTriggered: {
                    root.draftStart = modelData.start;
                    root.draftEnd = modelData.end;
                    root.draftDays = Array.from(modelData.days);
                    if (nameField.text.trim().length === 0)
                        nameField.text = modelData.name;
                }
            }
        }
    }

    // ── Times ───────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: [
                { key: "start", caption: Translation.tr("Starts"), symbol: "play_circle" },
                { key: "end", caption: Translation.tr("Ends"), symbol: "stop_circle" }
            ]

            Rectangle {
                id: timeTile
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 104
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
                    onClicked: root.pick(timeTile.modelData.key)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        MaterialSymbol {
                            text: timeTile.modelData.symbol
                            iconSize: Appearance.font.pixelSize.smallie
                            color: timePointer.containsMouse ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: timeTile.modelData.caption
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: timePointer.containsMouse ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    StyledText {
                        Layout.fillHeight: true
                        verticalAlignment: Text.AlignVCenter
                        text: timeTile.modelData.key === "start" ? root.draftStart : root.draftEnd
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 50
                        color: timeTile.colContent
                        animateChange: root.ready && !ClockStyle.reducedMotion
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: 2
        text: Translation.tr("Repeats on")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    ClockDayChips {
        Layout.fillWidth: true
        chipSize: 38
        days: root.draftDays
        onToggled: day => root.toggleDay(day)
    }

    ClockFormToggle {
        Layout.topMargin: 4
        symbol: "select_all"
        shapeKind: MaterialShape.Shape.Sunny
        label: Translation.tr("Every app")
        description: Translation.tr("Except always-allowed apps")
        checked: root.draftAllApps
        onToggled: checked => root.draftAllApps = checked
    }

    LimitsAppPicker {
        visible: !root.draftAllApps
        Layout.fillWidth: true
        selected: root.draftKeys
        onToggled: key => root.toggleKey(key)
    }

    ClockFormField {
        id: nameField
        Layout.topMargin: 4
        symbol: "label"
        caption: Translation.tr("Name")
        placeholder: Translation.tr("Focus time")
        onAccepted: root.save()
    }

    ClockFormToggle {
        symbol: "lock"
        shapeKind: MaterialShape.Shape.Cookie4Sided
        label: Translation.tr("Ask for the PIN")
        description: ScreenTimeLimits.hasPin ? Translation.tr("Lifting it needs the PIN") : Translation.tr("Set a PIN in limit settings first")
        checked: root.draftStrict && ScreenTimeLimits.hasPin
        enabled: ScreenTimeLimits.hasPin
        opacity: enabled ? 1 : 0.55
        onToggled: checked => root.draftStrict = checked
    }

    actions: [
        ClockSheetAction {
            Layout.fillWidth: true
            label: Translation.tr("Cancel")
            onClicked: root.close()
        },
        ClockSheetAction {
            Layout.fillWidth: true
            primary: true
            enabled: root.canSave
            symbol: "check"
            label: Translation.tr("Save")
            onClicked: root.save()
        }
    ]
}
