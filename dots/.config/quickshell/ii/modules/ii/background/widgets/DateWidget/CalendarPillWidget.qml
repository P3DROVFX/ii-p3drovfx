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

    configEntryName: "calendar_pill"

    implicitWidth: 240
    implicitHeight: 120

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color circleBgColor: WidgetColorScheme.accentColor
    readonly property color circleTextColor: WidgetColorScheme.onAccentColor

    StyledRectangularShadow {
        id: shadowEffect
        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        anchors.margins: 10
        radius: Appearance.rounding.full
        color: root.cardBgColor

        layer.enabled: Config.options.background.widgets.enableInnerShadow ?? true
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: mainContainer.width
                height: mainContainer.height
                radius: mainContainer.radius
                antialiasing: true
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 12
            spacing: 8

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Qt.locale().toString(DateTime.clock.date, "dddd")
                color: root.textColorOnBg
                font {
                    pixelSize: 22
                    weight: Font.DemiBold
                    family: Appearance.font.family.main
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: mainContainer.height - 16
                implicitHeight: implicitWidth
                radius: implicitWidth / 2
                color: root.circleBgColor

                StyledText {
                    anchors.centerIn: parent
                    text: DateTime.clock.date.getDate().toString()
                    color: root.circleTextColor
                    font {
                        pixelSize: 28
                        weight: Font.Black
                        bold: true
                        family: "Google Sans Flex"
                        variableAxes: ({ "wght": 800 })
                    }
                }
            }
        }

        Canvas {
            id: shadowMaskCanvas
            x: -80
            y: -80
            width: mainContainer.width + 160
            height: mainContainer.height + 160
            visible: false

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = "black";
                ctx.beginPath();
                ctx.rect(0, 0, width, height);

                var rx = 80;
                var ry = 80;
                var rw = mainContainer.width;
                var rh = mainContainer.height;
                var r = mainContainer.radius;

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
