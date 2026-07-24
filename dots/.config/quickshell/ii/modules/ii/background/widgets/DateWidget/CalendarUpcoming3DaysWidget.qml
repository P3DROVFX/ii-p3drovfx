import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_upcoming_3days"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    readonly property color createButtonBgColor: WidgetColorScheme.innerShapeColor

    // Process for IPC toggle to open cheatsheet timetable
    Process {
        id: cheatsheetIpcProcess
        command: ["qs", "ipc", "-c", "ii", "call", "cheatsheet", "toggle"]
    }

    // Stable date calculation without re-triggering model on clock seconds or events updates
    readonly property date todayDate: DateTime.clock.date
    readonly property int todayDayNum: todayDate ? todayDate.getDate() : 0
    readonly property int eventsCount: CalendarService.events ? CalendarService.events.length : 0

    // Statically helper function for date filtering
    function getEventsForDate(targetDate) {
        if (!CalendarService.khalAvailable || !CalendarService.events) return [];
        let list = [];
        let currentDay = targetDate.getDate();
        let currentMonth = targetDate.getMonth();
        let currentYear = targetDate.getFullYear();

        for (let i = 0; i < CalendarService.events.length; i++) {
            let evt = CalendarService.events[i];
            let taskDate = new Date(evt.startDate);
            if (taskDate.getDate() === currentDay && taskDate.getMonth() === currentMonth && taskDate.getFullYear() === currentYear) {
                list.push(evt);
            }
        }
        list.sort((a, b) => a.startDate - b.startDate);
        return list;
    }

    // Fixed 3-day data model structure
    readonly property var next3DaysGrouped: {
        let dummy1 = root.todayDayNum;
        let dummy2 = root.eventsCount;
        let now = root.todayDate;
        if (!now) now = new Date();

        let daysList = [];
        for (let d = 0; d < 3; d++) {
            let dayDate = new Date(now);
            dayDate.setDate(now.getDate() + d);

            daysList.push({
                "date": dayDate,
                "isToday": d === 0,
                "dateString": Qt.locale().toString(dayDate, "ddd, MMM d"),
                "events": root.getEventsForDate(dayDate)
            });
        }
        return daysList;
    }

    StyledRectangularShadow {
        id: shadowEffect
        target: bgRect
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.margins: 10
        color: root.cardBgColor
        radius: Appearance.rounding.windowRounding

        layer.enabled: Config.options.background.widgets.enableInnerShadow ?? true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bgRect.width
                height: bgRect.height
                radius: bgRect.radius
                antialiasing: true
            }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 16
            anchors.bottomMargin: 0

            ListView {
                id: daysListView
                anchors.fill: parent
                anchors.bottomMargin: 0
                spacing: 12
                clip: true

                model: root.next3DaysGrouped

                delegate: ColumnLayout {
                    id: dayColumn
                    required property int index
                    required property var modelData
                    readonly property bool isTodayItem: modelData.isToday
                    width: daysListView.width
                    spacing: 6

                    // Day Header Row: "Sat, Jul 27" + (+) button ONLY for today
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            text: modelData.dateString
                            font {
                                pixelSize: 18
                                weight: Font.Bold
                                family: "Google Sans Flex"
                            }
                            color: root.expressive ? (isTodayItem ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary) : root.textColorOnBg
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Item { Layout.fillWidth: true }

                        // Circular Create Event Button (+) on today's section
                        RippleButton {
                            id: createBtn
                            visible: isTodayItem
                            implicitWidth: 40
                            implicitHeight: 28
                            topLeftRadius: Appearance.rounding.full
                            topRightRadius: Appearance.rounding.full
                            bottomLeftRadius: Appearance.rounding.full
                            bottomRightRadius: Appearance.rounding.full

                            colBackground: root.expressive ? Appearance.colors.colPrimary : root.createButtonBgColor
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            colRipple: Appearance.colors.colLayer1Active

                            StyledText {
                                anchors.centerIn: parent
                                text: "+"
                                font {
                                    pixelSize: 20
                                    weight: Font.Bold
                                    family: "Google Sans Flex"
                                }
                                color: root.expressive ? Appearance.colors.colOnPrimary : root.textColorOnBg
                            }

                            onClicked: {
                                cheatsheetIpcProcess.start();
                            }
                        }
                    }

                    // Events List under this Day
                    Repeater {
                        model: modelData.events
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: eventCol.implicitHeight + 20
                            radius: Appearance.rounding.normal

                            color: root.expressive 
                                ? (dayColumn.isTodayItem ? Appearance.colors.colPrimary : Appearance.colors.colSecondary)
                                : Appearance.colors.colSurfaceContainerLow

                            ColumnLayout {
                                id: eventCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 2

                                StyledText {
                                    text: modelData.content || modelData.summary || Translation.tr("Event")
                                    font {
                                        pixelSize: 16
                                        weight: Font.Normal
                                        family: "Google Sans Flex"
                                    }
                                    color: root.expressive
                                        ? (dayColumn.isTodayItem ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary)
                                        : Appearance.colors.colOnSurface
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                StyledText {
                                    text: {
                                        if (modelData.allDay) return Translation.tr("All Day");
                                        let st = Qt.formatDateTime(new Date(modelData.startDate), "hh:mm");
                                        let et = Qt.formatDateTime(new Date(modelData.endDate), "hh:mm A");
                                        return st + " - " + et;
                                    }
                                    font {
                                        pixelSize: 13
                                        weight: Font.ExtraBold
                                        bold: true
                                        family: "Google Sans Flex"
                                    }
                                    color: root.expressive
                                        ? (dayColumn.isTodayItem 
                                            ? Qt.rgba(Appearance.colors.colOnPrimary.r, Appearance.colors.colOnPrimary.g, Appearance.colors.colOnPrimary.b, 0.8)
                                            : Qt.rgba(Appearance.colors.colOnSecondary.r, Appearance.colors.colOnSecondary.g, Appearance.colors.colOnSecondary.b, 0.8))
                                        : Qt.rgba(Appearance.colors.colOnSurfaceVariant.r, Appearance.colors.colOnSurfaceVariant.g, Appearance.colors.colOnSurfaceVariant.b, 0.75)
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Placeholder if day has no events
                    Rectangle {
                        visible: modelData.events.length === 0
                        Layout.fillWidth: true
                        implicitHeight: 46
                        radius: Appearance.rounding.normal
                        color: root.expressive 
                            ? (dayColumn.isTodayItem ? Appearance.colors.colPrimary : Appearance.colors.colSecondary)
                            : Appearance.colors.colSurfaceContainerLow

                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("No Events")
                            font {
                                pixelSize: 13
                                weight: Font.Medium
                                family: Appearance.font.family.main
                            }
                            color: root.expressive
                                ? (dayColumn.isTodayItem ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary)
                                : Qt.rgba(Appearance.colors.colOnSurfaceVariant.r, Appearance.colors.colOnSurfaceVariant.g, Appearance.colors.colOnSurfaceVariant.b, 0.75)
                        }
                    }
                }
            }
        }

        Canvas {
            id: shadowMaskCanvas
            x: -80
            y: -80
            width: bgRect.width + 160
            height: bgRect.height + 160
            visible: false

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = "black";
                ctx.beginPath();
                ctx.rect(0, 0, width, height);

                var rx = 80;
                var ry = 80;
                var rw = bgRect.width;
                var rh = bgRect.height;
                var r = bgRect.radius;

                ctx.moveTo(rx + r, ry);
                ctx.arcTo(rx, ry, rx, ry + r, r);
                ctx.lineTo(rx, ry + rh - r);
                ctx.arcTo(rx, ry + rh, rx + r, ry + rh, r);
                ctx.lineTo(rx + rw - r, ry + rh);
                ctx.arcTo(rx + rw, ry + rh, rx + rw, ry + rh - r, r);
                ctx.lineTo(rx + rw, ry + r);
                ctx.arcTo(rx + rw, ry, rx + rw - r, ry, r);
                ctx.lineTo(rx + r, ry);

                ctx.closePath();
                ctx.fill("evenodd");
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        DropShadow {
            id: innerShadow
            x: -80
            y: -80
            width: shadowMaskCanvas.width
            height: shadowMaskCanvas.height
            source: shadowMaskCanvas
            radius: 24
            samples: 49
            color: Qt.rgba(0, 0, 0, 0.35)
            horizontalOffset: 0
            verticalOffset: 0
            visible: Config.options.background.widgets.enableInnerShadow ?? true
        }
    }
}
