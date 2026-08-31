import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick

/**
 * Material 3 Expressive date picker: compact month grid for picking a single date.
 *
 * Deliberately self-contained: it reports a date and knows nothing about events,
 * so any surface in the shell can reuse it for date picking.
 */
Item {
    id: root

    property bool opened: false
    property string title: Translation.tr("Select date")
    property date selected: new Date()
    property int viewYear: DateTime.clock.date.getFullYear()
    property int viewMonth: DateTime.clock.date.getMonth()

    signal accepted(var pickedDate)
    signal dismissed

    visible: root.opened || progress.value > 0.001
    z: 300

    readonly property int firstDayOfWeek: Config.options.time.firstDayOfWeek
    readonly property var cells: root.buildMonthCells(root.viewYear, root.viewMonth, root.firstDayOfWeek, DateTime.clock.date)
    readonly property var weekdays: root.weekdayLabels(root.firstDayOfWeek, Config.options.calendar.locale, Locale.NarrowFormat)
    readonly property real cellSize: 38

    function pad2(value) {
        return (value < 10 ? "0" : "") + value;
    }

    function sameDate(a, b) {
        if (!a || !b)
            return false;
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function startOfDay(date) {
        return new Date(date.getFullYear(), date.getMonth(), date.getDate());
    }

    function addMonths(date, count) {
        const firstOfTarget = new Date(date.getFullYear(), date.getMonth() + count, 1);
        const available = new Date(firstOfTarget.getFullYear(), firstOfTarget.getMonth() + 1, 0).getDate();
        return new Date(firstOfTarget.getFullYear(), firstOfTarget.getMonth(), Math.min(date.getDate(), available));
    }

    function columnForJsDay(jsDay, firstDay) {
        return (jsDay - firstDay + 6) % 7;
    }

    function isWeekendColumn(column, firstDay) {
        const jsDay = (firstDay + 1 + column) % 7;
        return jsDay === 0 || jsDay === 6;
    }

    function buildMonthCells(year, month, firstDay, todayDate) {
        const lead = (new Date(year, month, 1).getDay() - firstDay + 6) % 7;
        const daysInCurrentMonth = new Date(year, month + 1, 0).getDate();
        const cellCount = Math.ceil((lead + daysInCurrentMonth) / 7) * 7;
        const cellList = [];
        for (let i = 0; i < cellCount; i++) {
            const date = new Date(year, month, 1 - lead + i);
            cellList.push({
                date: date,
                key: date.getFullYear() + "-" + root.pad2(date.getMonth() + 1) + "-" + root.pad2(date.getDate()),
                day: date.getDate(),
                inMonth: date.getMonth() === month && date.getFullYear() === year,
                isWeekend: date.getDay() === 0 || date.getDay() === 6,
                isToday: root.sameDate(date, todayDate),
                row: Math.floor(i / 7),
                column: i % 7
            });
        }
        return cellList;
    }

    function weekdayLabels(firstDay, localeName, format) {
        const locale = localeName ? Qt.locale(localeName) : Qt.locale();
        const labels = [];
        for (let i = 0; i < 7; i++) {
            labels.push(locale.dayName((firstDay + 1 + i) % 7, format));
        }
        return labels;
    }

    function open(date, titleText) {
        root.title = titleText && titleText.length > 0 ? titleText : Translation.tr("Select date");
        const start = date ? root.startOfDay(date) : root.startOfDay(DateTime.clock.date);
        root.selected = start;
        root.viewYear = start.getFullYear();
        root.viewMonth = start.getMonth();
        root.opened = true;
    }

    function close() {
        root.opened = false;
    }

    function dismiss() {
        root.close();
        root.dismissed();
    }

    function confirm() {
        root.accepted(root.selected);
        root.close();
    }

    function shiftMonth(delta) {
        const target = root.addMonths(new Date(root.viewYear, root.viewMonth, 1), delta);
        root.viewYear = target.getFullYear();
        root.viewMonth = target.getMonth();
    }

    QtObject {
        id: progress
        property real value: 0
    }

    onOpenedChanged: {
        openAnim.stop();
        closeAnim.stop();
        if (root.opened)
            openAnim.start();
        else
            closeAnim.start();
    }

    NumberAnimation {
        id: openAnim
        target: progress
        property: "value"
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    NumberAnimation {
        id: closeAnim
        target: progress
        property: "value"
        to: 0
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: progress.value

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: root.dismiss()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: cardColumn.implicitWidth + 40
        height: Math.min(cardColumn.implicitHeight + 40, root.height - 24)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        clip: true

        opacity: progress.value
        scale: 0.9 + 0.1 * progress.value
        transform: Translate {
            y: (1 - progress.value) * 20
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onPressed: mouse => {
                mouse.accepted = true;
            }
        }

        Column {
            id: cardColumn
            anchors.centerIn: parent
            spacing: 10

            StyledText {
                text: root.title.toUpperCase()
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurfaceVariant
            }

            // ─── Month nav ───
            Item {
                width: root.cellSize * 7
                height: 42

                RippleButton {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.shiftMonth(-1)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    text: Qt.formatDate(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSurface
                    animateChange: true
                    animationDistanceX: 8
                    animationDistanceY: 0
                }

                RippleButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                    onClicked: root.shiftMonth(1)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // ─── Weekdays ───
            Row {
                Repeater {
                    model: 7

                    delegate: StyledText {
                        required property int index

                        width: root.cellSize
                        height: 24
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: String(root.weekdays?.[index] ?? "").toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: root.isWeekendColumn(index, root.firstDayOfWeek) ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                }
            }

            // ─── Days ───
            Grid {
                columns: 7

                Repeater {
                    model: root.cells

                    delegate: Item {
                        id: dayCell
                        required property var modelData

                        width: root.cellSize
                        height: root.cellSize

                        readonly property bool isSelected: root.sameDate(dayCell.modelData.date, root.selected)
                        readonly property bool hasEvents: (CalendarService.eventsByDay[dayCell.modelData.key]?.length ?? 0) > 0

                        Rectangle {
                            anchors.centerIn: parent
                            width: root.cellSize - 4
                            height: root.cellSize - 4
                            radius: width / 2
                            color: {
                                if (dayCell.isSelected)
                                    return Appearance.colors.colPrimary;
                                if (dayCell.modelData.isToday)
                                    return Appearance.colors.colPrimaryContainer;
                                if (dayPointer.containsMouse)
                                    return Appearance.colors.colSurfaceContainerHighestHover;
                                return "transparent";
                            }

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: String(dayCell.modelData.day)
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: dayCell.isSelected || dayCell.modelData.isToday ? Font.Bold : Font.Medium
                            color: {
                                if (dayCell.isSelected)
                                    return Appearance.colors.colOnPrimary;
                                if (dayCell.modelData.isToday)
                                    return Appearance.colors.colOnPrimaryContainer;
                                if (!dayCell.modelData.inMonth)
                                    return Appearance.colors.colOnLayer1Inactive;
                                return Appearance.colors.colOnSurface;
                            }
                        }

                        // A day that already has something on it, marked without
                        // stealing room from the number.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            visible: dayCell.hasEvents && !dayCell.isSelected
                            width: 4
                            height: 4
                            radius: 2
                            color: Appearance.colors.colPrimary
                            opacity: dayCell.modelData.inMonth ? 1 : 0.45
                        }

                        MouseArea {
                            id: dayPointer
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selected = dayCell.modelData.date;
                                if (!dayCell.modelData.inMonth) {
                                    root.viewYear = dayCell.modelData.date.getFullYear();
                                    root.viewMonth = dayCell.modelData.date.getMonth();
                                }
                            }
                            onDoubleClicked: root.confirm()
                        }
                    }
                }
            }

            // ─── Actions ───
            Item {
                width: root.cellSize * 7
                height: 46

                RippleButtonWithIcon {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 116
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "close"
                    materialIconFill: false
                    mainText: Translation.tr("Cancel")
                    iconPixelSize: Appearance.font.pixelSize.large
                    textPixelSize: Appearance.font.pixelSize.small
                    mainTextWeight: Font.DemiBold
                    colText: Appearance.colors.colPrimary
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12)
                    onClicked: root.dismiss()

                    DashedBorder {
                        anchors.fill: parent
                        color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.75)
                        borderWidth: 1
                        dashLength: 5
                        gapLength: 4
                        radius: Appearance.rounding.full
                    }
                }

                RippleButtonWithIcon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 126
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "check"
                    materialIconFill: false
                    mainText: Translation.tr("Set date")
                    iconPixelSize: Appearance.font.pixelSize.large
                    textPixelSize: Appearance.font.pixelSize.small
                    mainTextWeight: Font.Bold
                    colText: Appearance.colors.colOnPrimary
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    onClicked: root.confirm()
                }
            }
        }
    }
}
