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

    configEntryName: "calendar_grid"

    implicitWidth: 492
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color headerMonthColor: WidgetColorScheme.textColorOnBg
    readonly property color dayNameColor: WidgetColorScheme.textColorOnBg
    readonly property color dateNumberColor: WidgetColorScheme.textColorOnBg
    readonly property color dateMutedColor: WidgetColorScheme.subtextColorOnBg
    
    readonly property color highlightCircleColor: WidgetColorScheme.highlightCircleColor
    readonly property color highlightTextColor: WidgetColorScheme.highlightTextColor

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
            anchors.margins: 20

            // Left Section: Month, Weekday, Big Day Number
            Item {
                id: leftSection
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 170

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    StyledText {
                        text: Qt.locale().toString(DateTime.clock.date, "MMMM")
                        font {
                            pixelSize: 18
                            weight: Font.Medium
                            family: Appearance.font.family.main
                        }
                        color: root.headerMonthColor
                    }

                    StyledText {
                        text: Qt.locale().toString(DateTime.clock.date, "dddd")
                        font {
                            pixelSize: 22
                            weight: Font.Bold
                            family: Appearance.font.family.main
                        }
                        color: root.textColorOnBg
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.locale().toString(DateTime.clock.date, "dd")
                            font {
                                pixelSize: 84
                                weight: Font.Black
                                bold: true
                                family: "Google Sans Flex"
                                variableAxes: ({ "wght": 900 })
                            }
                            color: root.textColorOnBg
                        }
                    }
                }
            }

            // Right Section: Monthly Calendar Grid
            Item {
                id: gridScope
                anchors.left: leftSection.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                readonly property date currDate: DateTime.clock.date
                readonly property int currDay: currDate.getDate()
                readonly property int currMonth: currDate.getMonth()
                readonly property int currYear: currDate.getFullYear()

                // Calculate first day of month (0 = Sun, 1 = Mon, ..., 6 = Sat)
                readonly property int firstDayOfWeekRaw: new Date(currYear, currMonth, 1).getDay()
                // Convert to Mon=0, Tue=1, ..., Sun=6
                readonly property int firstDayOfWeek: (firstDayOfWeekRaw + 6) % 7
                readonly property int daysInMonth: new Date(currYear, currMonth + 1, 0).getDate()
                readonly property int totalRowsNeeded: Math.ceil((firstDayOfWeek + daysInMonth) / 7)

                readonly property real cellWidth: width / 7
                readonly property real headerHeight: 24
                readonly property real cellHeight: (height - headerHeight) / totalRowsNeeded

                // Days of week header (M T W T F S S)
                Repeater {
                    model: [
                        Translation.tr("M"),
                        Translation.tr("T"),
                        Translation.tr("W"),
                        Translation.tr("T"),
                        Translation.tr("F"),
                        Translation.tr("S"),
                        Translation.tr("S")
                    ]
                    delegate: Item {
                        required property int index
                        required property string modelData
                        x: index * gridScope.cellWidth
                        y: 0
                        width: gridScope.cellWidth
                        height: gridScope.headerHeight

                        StyledText {
                            anchors.centerIn: parent
                            text: modelData
                            font {
                                pixelSize: 13
                                weight: Font.Bold
                                family: Appearance.font.family.main
                            }
                            color: root.dayNameColor
                        }
                    }
                }

                // Days Grid: 42 cells positioning x and y explicitly
                Repeater {
                    model: 42
                    delegate: Item {
                        required property int index
                        readonly property int col: index % 7
                        readonly property int row: Math.floor(index / 7)
                        readonly property int dayNumber: index - gridScope.firstDayOfWeek + 1
                        readonly property bool isValidDay: dayNumber >= 1 && dayNumber <= gridScope.daysInMonth
                        readonly property bool isToday: isValidDay && dayNumber === gridScope.currDay

                        x: col * gridScope.cellWidth
                        y: gridScope.headerHeight + row * gridScope.cellHeight
                        width: gridScope.cellWidth
                        height: gridScope.cellHeight
                        visible: isValidDay

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * 0.85
                            height: width
                            radius: width / 2
                            color: root.highlightCircleColor
                            visible: isToday
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: isValidDay ? dayNumber.toString() : ""
                            font {
                                pixelSize: 13
                                weight: isToday ? Font.Bold : Font.Medium
                                family: Appearance.font.family.main
                            }
                            color: isToday ? root.highlightTextColor : root.dateNumberColor
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
