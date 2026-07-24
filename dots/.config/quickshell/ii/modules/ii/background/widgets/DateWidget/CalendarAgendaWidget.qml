import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_agenda"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg

    readonly property color agendaCardColor: WidgetColorScheme.innerShapeColor

    readonly property color highlightCircleColor: WidgetColorScheme.highlightCircleColor
    readonly property color highlightTextColor: WidgetColorScheme.highlightTextColor

    // Current system date & week strip dates (7 days)
    readonly property date currDate: DateTime.clock.date
    readonly property int currDay: currDate.getDate()
    readonly property int currMonth: currDate.getMonth()
    readonly property int currYear: currDate.getFullYear()

    readonly property var todayEvents: {
        if (!CalendarService.khalAvailable || !CalendarService.events) return [];
        let list = [];
        let today = root.currDate;
        if (!today) today = new Date();
        const currentDay = today.getDate();
        const currentMonth = today.getMonth();
        const currentYear = today.getFullYear();

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

    // Days in week strip (Mon, Tue, Wed, Thu, Fri, Sat, Sun) of current week
    readonly property var weekStripDays: {
        let list = [];
        let now = root.currDate;
        if (!now) now = new Date();
        let dayOfWeek = (now.getDay() + 6) % 7; // Mon=0 .. Sun=6
        let monday = new Date(now);
        monday.setDate(now.getDate() - dayOfWeek);

        for (let i = 0; i < 7; i++) {
            let d = new Date(monday);
            d.setDate(monday.getDate() + i);
            let hasEvts = false;
            if (CalendarService.khalAvailable && CalendarService.events) {
                for (let j = 0; j < CalendarService.events.length; j++) {
                    let evt = CalendarService.events[j];
                    let taskDate = new Date(evt.startDate);
                    if (taskDate.getDate() === d.getDate() && taskDate.getMonth() === d.getMonth() && taskDate.getFullYear() === d.getFullYear()) {
                        hasEvts = true;
                        break;
                    }
                }
            }
            list.push({
                "date": d,
                "dayNum": d.getDate(),
                "isToday": d.getDate() === now.getDate() && d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear(),
                "hasEvents": hasEvts
            });
        }
        return list;
    }

    StyledRectangularShadow {
        id: bgShadow
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
            anchors.fill: parent

            // Header Month & Year (ex: "Sep 2024")
            StyledText {
                id: monthYearText
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.top: parent.top
                anchors.topMargin: 16
                text: Qt.locale().toString(root.currDate, "MMM yyyy")
                font {
                    pixelSize: 18
                    weight: Font.Bold
                    family: Appearance.font.family.main
                }
                color: root.textColorOnBg
            }

            // Top Section: Weekday Header & Day Number Strip
            Item {
                id: weekStripSection
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.top: monthYearText.bottom
                anchors.topMargin: 2
                height: 52

                readonly property real cellWidth: width / 7

                // Row of Weekday Initials (S M T W T F S)
                Repeater {
                    model: [
                        Translation.tr("S"),
                        Translation.tr("M"),
                        Translation.tr("T"),
                        Translation.tr("W"),
                        Translation.tr("T"),
                        Translation.tr("F"),
                        Translation.tr("S")
                    ]
                    delegate: Item {
                        required property int index
                        required property string modelData
                        x: index * weekStripSection.cellWidth
                        y: 0
                        width: weekStripSection.cellWidth
                        height: 18

                        StyledText {
                            anchors.centerIn: parent
                            text: modelData
                            font {
                                pixelSize: 12
                                weight: Font.Medium
                                family: Appearance.font.family.main
                            }
                            color: root.subtextColorOnBg
                        }
                    }
                }

                // Row of Day Numbers + Highlight Circle + Dot Indicator
                Repeater {
                    model: root.weekStripDays
                    delegate: Item {
                        required property int index
                        required property var modelData
                        x: index * weekStripSection.cellWidth
                        y: 18
                        width: weekStripSection.cellWidth
                        height: 34

                        // Today Circle Highlight with DropShadow
                        Item {
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            visible: modelData.isToday

                            DropShadow {
                                anchors.fill: highlightCircle
                                source: highlightCircle
                                radius: 8
                                samples: 17
                                color: Qt.rgba(0, 0, 0, 0.18)
                                verticalOffset: 2
                            }

                            Rectangle {
                                id: highlightCircle
                                anchors.fill: parent
                                radius: width / 2
                                color: root.highlightCircleColor
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: modelData.isToday ? 0 : -2
                            text: modelData.dayNum.toString()
                            font {
                                pixelSize: 13
                                weight: modelData.isToday ? Font.Bold : Font.Normal
                                family: Appearance.font.family.main
                            }
                            color: modelData.isToday ? root.highlightTextColor : root.textColorOnBg
                        }

                        // Event Indicator Dot below non-today days
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 3
                            height: 3
                            radius: 1.5
                            color: root.subtextColorOnBg
                            visible: !modelData.isToday && modelData.hasEvents
                        }
                    }
                }
            }

            // Bottom Section: Agenda Events List Card taking full width and bottom without margins
            Item {
                id: agendaContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: weekStripSection.bottom
                anchors.topMargin: 8
                anchors.bottom: parent.bottom

                Rectangle {
                    anchors.fill: parent
                    color: root.agendaCardColor
                    radius: bgRect.radius

                    // Events ListView
                    ListView {
                        id: eventsListView
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 12
                        anchors.bottomMargin: 0
                        spacing: 10
                        clip: true

                        model: root.todayEvents

                        delegate: ColumnLayout {
                            required property int index
                            required property var modelData
                            width: eventsListView.width
                            spacing: 2

                            StyledText {
                                text: modelData.content || modelData.summary || Translation.tr("Event")
                                font {
                                    pixelSize: 13
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.main
                                }
                                color: root.textColorOnBg
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            StyledText {
                                text: {
                                    if (modelData.allDay) return Translation.tr("All Day");
                                    let st = Qt.formatDateTime(new Date(modelData.startDate), "hh:mm A");
                                    let et = Qt.formatDateTime(new Date(modelData.endDate), "hh:mm A");
                                    return st + " - " + et;
                                }
                                font {
                                    pixelSize: 11
                                    weight: Font.Normal
                                    family: Appearance.font.family.main
                                }
                                color: root.subtextColorOnBg
                                Layout.fillWidth: true
                            }

                            // Separator line between events
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                height: 1
                                color: Qt.rgba(root.subtextColorOnBg.r, root.subtextColorOnBg.g, root.subtextColorOnBg.b, 0.15)
                                visible: index < root.todayEvents.length - 1
                            }
                        }

                        // Placeholder when no events today
                        Item {
                            anchors.fill: parent
                            visible: root.todayEvents.length === 0

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "event_available"
                                    iconSize: 22
                                    color: root.subtextColorOnBg
                                }

                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Translation.tr("No Events Today")
                                    font {
                                        pixelSize: 12
                                        weight: Font.Medium
                                        family: Appearance.font.family.main
                                    }
                                    color: root.subtextColorOnBg
                                }
                            }
                        }
                    }
                }

                // Vertical Fade Gradient Overlay at the bottom
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 32
                    radius: bgRect.radius

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: root.agendaCardColor }
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
