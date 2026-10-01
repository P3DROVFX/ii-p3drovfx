pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Samsung Reminder's repeat page, folded into the editor: every N minutes, hours, days,
 * weeks (on chosen weekdays), months (on chosen days) or years (on chosen dates), and how
 * it ends — never, after a number of times, or on a date.
 *
 * Works on a copy and reports every change through `edited(repeat)`; null means "don't
 * repeat".
 */
ColumnLayout {
    id: root

    /// The rule being edited, or null.
    property var repeat: null
    /// The reminder's date: the default weekday, day of month and date of year.
    property date startDate: new Date()
    /// The window's pickers (ClockPickerHost), for the "until" date and yearly dates.
    property Item pickers: null

    signal edited(var repeat)

    readonly property string unit: root.repeat?.unit ?? ""
    readonly property var units: [
        { id: "", label: Translation.tr("Don't repeat") },
        { id: "day", label: Translation.tr("Daily") },
        { id: "week", label: Translation.tr("Weekly") },
        { id: "month", label: Translation.tr("Monthly") },
        { id: "year", label: Translation.tr("Yearly") },
        { id: "hour", label: Translation.tr("Hourly") },
        { id: "minute", label: Translation.tr("By the minute") }
    ]

    function base() {
        return root.repeat ? JSON.parse(JSON.stringify(root.repeat)) : {
            unit: "day", interval: 1, weekdays: [false, false, false, false, false, false, false],
            monthDays: [], yearDates: [], end: { kind: "never", count: 5, until: "" }
        };
    }

    function change(edit): void {
        const next = root.base();
        edit(next);
        root.edited(next);
    }

    function setUnit(unit: string): void {
        if (unit.length === 0) {
            root.edited(null);
            return;
        }
        root.change(next => {
            next.unit = unit;
            next.interval = 1;
            if (unit === "week" && !next.weekdays.includes(true)) {
                next.weekdays = [false, false, false, false, false, false, false];
                next.weekdays[root.startDate.getDay()] = true;
            }
            if (unit === "month" && next.monthDays.length === 0)
                next.monthDays = [root.startDate.getDate()];
            if (unit === "year" && next.yearDates.length === 0)
                next.yearDates = [Qt.formatDate(root.startDate, "MM-dd")];
        });
    }

    function unitWord(): string {
        const n = root.repeat?.interval ?? 1;
        switch (root.unit) {
        case "minute": return n === 1 ? Translation.tr("minute") : Translation.tr("minutes");
        case "hour": return n === 1 ? Translation.tr("hour") : Translation.tr("hours");
        case "week": return n === 1 ? Translation.tr("week") : Translation.tr("weeks");
        case "month": return n === 1 ? Translation.tr("month") : Translation.tr("months");
        case "year": return n === 1 ? Translation.tr("year") : Translation.tr("years");
        default: return n === 1 ? Translation.tr("day") : Translation.tr("days");
        }
    }

    spacing: 10

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.units

            ClockFormChip {
                required property var modelData
                label: modelData.label
                selected: root.unit === modelData.id
                onTriggered: root.setUnit(modelData.id)
            }
        }
    }

    // ── Every N ─────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        visible: root.unit.length > 0
        spacing: ClockStyle.gapSmall

        StyledText {
            text: Translation.tr("Every")
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSurface
        }

        ClockStepper {
            value: root.repeat?.interval ?? 1
            from: 1
            to: 99
            format: value => String(value)
            onMoved: value => root.change(next => next.interval = value)
        }

        StyledText {
            Layout.fillWidth: true
            text: root.unitWord()
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSurface
        }
    }

    // ── Weekly: which days ──────────────────────────────────────────────
    ClockDayChips {
        Layout.fillWidth: true
        visible: root.unit === "week"
        chipSize: 36
        days: root.repeat?.weekdays ?? []
        onToggled: day => root.change(next => {
            next.weekdays[day] = !next.weekdays[day];
            if (!next.weekdays.includes(true))
                next.weekdays[day] = true;
        })
    }

    // ── Monthly: which days of the month ───────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        visible: root.unit === "month"
        columns: 7
        rowSpacing: 4
        columnSpacing: 4

        Repeater {
            model: 31

            RippleButton {
                id: dayButton
                required property int index
                readonly property int day: index + 1
                readonly property bool on: (root.repeat?.monthDays ?? []).includes(dayButton.day)
                Layout.fillWidth: true
                implicitHeight: 34
                buttonRadius: dayButton.on ? ClockStyle.radiusSmall : height / 2
                colBackground: dayButton.on ? ClockStyle.colPrimary : ClockStyle.colField
                colBackgroundHover: dayButton.on ? ClockStyle.colPrimaryHover : ClockStyle.colFieldHover
                colRipple: dayButton.on ? ClockStyle.colPrimaryActive : ClockStyle.colSurfaceActive
                onClicked: root.change(next => {
                    const days = next.monthDays.filter(day => day !== dayButton.day);
                    if (!dayButton.on)
                        days.push(dayButton.day);
                    next.monthDays = days.length > 0 ? days.sort((a, b) => a - b) : [dayButton.day];
                })

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: String(dayButton.day)
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.DemiBold
                    color: dayButton.on ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.unit === "month" && (root.repeat?.monthDays ?? []).some(day => day > 28)
        text: Translation.tr("In shorter months it falls on the last day.")
        wrapMode: Text.Wrap
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    // ── Yearly: which dates ─────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        visible: root.unit === "year"
        spacing: 6

        Repeater {
            model: root.repeat?.yearDates ?? []

            ClockChip {
                id: dateChip
                required property string modelData
                readonly property var parts: dateChip.modelData.split("-").map(Number)
                selected: true
                symbol: "close"
                label: Qt.locale().toString(new Date(2000, dateChip.parts[0] - 1, dateChip.parts[1]), "d MMMM")
                onClicked: root.change(next => {
                    const dates = next.yearDates.filter(key => key !== dateChip.modelData);
                    next.yearDates = dates.length > 0 ? dates : next.yearDates;
                })
            }
        }

        ClockChip {
            symbol: "add"
            label: Translation.tr("Add date")
            onClicked: root.pickers?.pickDate(root.startDate, Translation.tr("Repeats on"), date => root.change(next => {
                const key = Qt.formatDate(date, "MM-dd");
                if (!next.yearDates.includes(key))
                    next.yearDates = next.yearDates.concat([key]).sort();
            }))
        }
    }

    // ── Ends ────────────────────────────────────────────────────────────
    StyledText {
        visible: root.unit.length > 0
        Layout.topMargin: 2
        text: Translation.tr("Ends")
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Bold
        color: ClockStyle.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        visible: root.unit.length > 0
        spacing: 6

        Repeater {
            model: [
                { id: "never", label: Translation.tr("Forever") },
                { id: "count", label: Translation.tr("Number of times") },
                { id: "until", label: Translation.tr("Until a date") }
            ]

            ClockFormChip {
                required property var modelData
                label: modelData.label
                selected: (root.repeat?.end?.kind ?? "never") === modelData.id
                onTriggered: root.change(next => {
                    next.end.kind = modelData.id;
                    if (modelData.id === "until" && !next.end.until) {
                        const until = new Date(root.startDate.getFullYear(), root.startDate.getMonth() + 1, root.startDate.getDate());
                        next.end.until = Qt.formatDate(until, "yyyy-MM-dd");
                    }
                })
            }
        }
    }

    RowLayout {
        visible: root.repeat?.end?.kind === "count"
        spacing: ClockStyle.gapSmall

        ClockStepper {
            value: root.repeat?.end?.count ?? 5
            from: 1
            to: 999
            format: value => String(value)
            onMoved: value => root.change(next => next.end.count = value)
        }

        StyledText {
            text: Translation.tr("times")
            font.pixelSize: ClockStyle.textNormal
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSurface
        }
    }

    ClockFormPicker {
        visible: root.repeat?.end?.kind === "until"
        symbol: "event_busy"
        shapeKind: MaterialShape.Shape.Cookie6Sided
        caption: Translation.tr("Until")
        value: root.repeat?.end?.until ? Qt.locale().toString(ClockFormat.parseDay(root.repeat.end.until), "dddd, d MMMM yyyy") : ""
        onTriggered: root.pickers?.pickDate(ClockFormat.parseDay(root.repeat.end.until), Translation.tr("Repeat until"),
            date => root.change(next => next.end.until = Qt.formatDate(date, "yyyy-MM-dd")))
    }
}
