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

    configEntryName: "calendar_next_event"

    implicitWidth: 492
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg

    readonly property color primaryCardBg: WidgetColorScheme.accentColor
    readonly property color primaryCardText: WidgetColorScheme.onAccentColor
    readonly property color primaryCardSubtext: Qt.rgba(WidgetColorScheme.onAccentColor.r, WidgetColorScheme.onAccentColor.g, WidgetColorScheme.onAccentColor.b, 0.75)

    readonly property color normalCardBg: WidgetColorScheme.innerShapeColor

    // Process for IPC toggle to open cheatsheet timetable
    Process {
        id: cheatsheetIpcProcess
        command: ["qs", "ipc", "-c", "ii", "call", "cheatsheet", "toggle"]
    }

    // Current system date & time
    readonly property date currDate: DateTime.clock.date
    readonly property int currDay: currDate.getDate()
    readonly property int currMonth: currDate.getMonth()
    readonly property int currYear: currDate.getFullYear()

    // When an event stops being upcoming. khal ends an all-day event at 00:00
    // or 23:59 of its own day, so it counts until the next midnight.
    function effectiveEnd(evt) {
        if (CalendarService.isAllDayEvent(evt)) {
            const start = new Date(evt.startDate);
            return new Date(start.getFullYear(), start.getMonth(), start.getDate() + 1).getTime();
        }
        return new Date(evt.endDate).getTime();
    }

    // Every event that has not ended yet, soonest first
    readonly property var upcomingEvents: {
        if (!CalendarService.khalAvailable || !CalendarService.events) return [];
        const now = root.currDate ? root.currDate.getTime() : Date.now();
        const list = CalendarService.events.filter(evt => root.effectiveEnd(evt) > now);
        list.sort((a, b) => a.startDate - b.startDate);
        return list;
    }

    // The day the card shows: today while something is still ahead on it,
    // else the next day that has events (khal keeps each event within a day)
    readonly property date focusDate: root.upcomingEvents.length > 0
        && new Date(root.upcomingEvents[0].startDate) > root.currDate
        ? new Date(root.upcomingEvents[0].startDate) : root.currDate
    readonly property int focusDayOffset: {
        const today = new Date(root.currYear, root.currMonth, root.currDay);
        const day = new Date(root.focusDate.getFullYear(), root.focusDate.getMonth(), root.focusDate.getDate());
        return Math.round((day - today) / 86400000);
    }

    // The focus day's remaining events
    readonly property var dayEvents: root.upcomingEvents.filter(evt => {
        const start = new Date(evt.startDate);
        return start.getDate() === root.focusDate.getDate() && start.getMonth() === root.focusDate.getMonth()
            && start.getFullYear() === root.focusDate.getFullYear();
    })

    readonly property var nextEvent: root.dayEvents.length > 0 ? root.dayEvents[0] : null

    // Formatted time string until next event (ex: "in 45m" or "in 1h 10m")
    readonly property string timeUntilNextEvent: {
        let evt = root.nextEvent;
        if (!evt) return "";
        let now = root.currDate ? root.currDate.getTime() : Date.now();
        let start = new Date(evt.startDate).getTime();
        let diffMs = start - now;

        if (diffMs <= 0) {
            let end = new Date(evt.endDate).getTime();
            if (now < end) return Translation.tr("Now");
            return "";
        }
        let totalMins = Math.floor(diffMs / 60000);
        if (totalMins < 60) return "in " + String(totalMins) + "m";
        if (totalMins >= 24 * 60) return "in " + String(Math.round(totalMins / (24 * 60))) + "d";
        let hours = Math.floor(totalMins / 60);
        let mins = totalMins % 60;
        if (mins === 0) return "in " + String(hours) + "h";
        return "in " + String(hours) + "h " + String(mins) + "m";
    }

    StyledRectangularShadow {
        id: bgShadow
        target: bgRect
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
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
            anchors.fill: parent

            // Left Section: Weekday, Big Day Number, Time until next event with arrow icon
            Item {
                id: leftSection
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.top: parent.top
                anchors.topMargin: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: 110

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.focusDayOffset === 1 ? Translation.tr("Tomorrow")
                            : root.focusDayOffset > 6 ? Qt.locale().toString(root.focusDate, "ddd MMM")
                            : Qt.locale().toString(root.focusDate, "ddd")
                        font {
                            pixelSize: 22
                            weight: Font.Medium
                            family: Appearance.font.family.main
                        }
                        color: root.subtextColorOnBg
                    }

                    StyledText {
                        text: Qt.locale().toString(root.focusDate, "dd")
                        font {
                            pixelSize: 84
                            weight: Font.ExtraBold
                            bold: true
                            family: "Google Sans Flex"
                            variableAxes: ({ "wght": 800 })
                        }
                        color: root.textColorOnBg
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: root.timeUntilNextEvent !== ""

                            MaterialSymbol {
                                text: "north_east"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                text: root.timeUntilNextEvent
                                font {
                                    pixelSize: 15
                                    weight: Font.Medium
                                    family: Appearance.font.family.main
                                }
                                color: root.subtextColorOnBg
                            }
                        }
                    }
                }
            }

            // Right Section: Events List Cards (First event in colPrimary)
            Item {
                id: rightSection
                anchors.left: leftSection.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.top: parent.top
                anchors.topMargin: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 0

                ListView {
                    id: eventsListView
                    anchors.fill: parent
                    anchors.bottomMargin: 0
                    spacing: 8
                    clip: true

                    model: root.dayEvents

                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        readonly property bool isFirst: index === 0

                        width: eventsListView.width
                        implicitHeight: colLayout.implicitHeight + 24
                        radius: Appearance.rounding.normal
                        color: isFirst ? root.primaryCardBg : WidgetColorScheme.tintBackground(root.normalCardBg)

                        ColumnLayout {
                            id: colLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 4

                            StyledText {
                                text: modelData.content || modelData.summary || Translation.tr("Event")
                                font {
                                    pixelSize: 15
                                    weight: Font.Bold
                                    family: Appearance.font.family.main
                                }
                                color: isFirst ? root.primaryCardText : root.textColorOnBg
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: {
                                    if (CalendarService.isAllDayEvent(modelData)) return Translation.tr("All Day");
                                    const fmt = Config.options.time.format || "hh:mm";
                                    let st = Qt.formatDateTime(new Date(modelData.startDate), fmt);
                                    let et = Qt.formatDateTime(new Date(modelData.endDate), fmt);
                                    return st + " – " + et;
                                }
                                font {
                                    pixelSize: 13
                                    weight: Font.Normal
                                    family: Appearance.font.family.main
                                }
                                color: isFirst ? root.primaryCardSubtext : root.subtextColorOnBg
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // Placeholder when nothing is ahead
                    Item {
                        anchors.fill: parent
                        visible: root.dayEvents.length === 0

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.normal
                            color: WidgetColorScheme.tintBackground(root.normalCardBg)

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "event_available"
                                    iconSize: 26
                                    color: root.subtextColorOnBg
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("No Upcoming Events")
                                    font {
                                        pixelSize: 13
                                        weight: Font.Medium
                                        family: Appearance.font.family.main
                                    }
                                    color: root.subtextColorOnBg
                                }
                            }
                        }
                    }

                    TouchpadScrollHandler {
                        flickable: eventsListView
                    }
                }

                // Vertical Fade Gradient Overlay at bottom of events list (flat bottom to cover entire list width)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 36

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: WidgetColorScheme.tintBackground(root.cardBgColor) }
                    }
                }
            }

            // Floating Circular Add Button (+) opening cheatsheet timetable via IPC
            RippleButton {
                id: addButton
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                implicitWidth: 46
                implicitHeight: 46
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full

                colBackground: Appearance.colors.colTertiaryContainer
                colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                colRipple: Appearance.colors.colTertiaryContainerActive

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: 24
                    color: Appearance.colors.colOnTertiaryContainer
                }

                onClicked: {
                    cheatsheetIpcProcess.start();
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
                var r = Math.max(0, bgRect.radius - 8);

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
