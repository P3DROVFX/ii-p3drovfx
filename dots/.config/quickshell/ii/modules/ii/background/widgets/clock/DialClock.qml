pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property real implicitSize: 240

    property color colBackground: WidgetColorScheme.cardBgColor
    property color colBorder: WidgetColorScheme.textColorOnBg
    property color colTicks: WidgetColorScheme.textColorOnBg
    property color colNumbers: WidgetColorScheme.textColorOnBg
    property color colHandFill: WidgetColorScheme.accentColor
    property color colHandBorder: WidgetColorScheme.accentColor
    property color colMinuteHandFill: WidgetColorScheme.onAccentColor

    readonly property list<string> clockNumbers: DateTime.time.split(/[: ]/)
    readonly property int clockHour: parseInt(clockNumbers[0]) % 12
    readonly property int clockMinute: DateTime.clock.minutes

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    // Outer drop shadow support
    StyledDropShadow {
        id: outerShadow
        target: dialBody
        visible: Config.ready ? (Config.options.background.widgets.clock.dial.enableShadows ?? true) : true
    }

    // Base Dial Plate
    Rectangle {
        id: dialBody
        anchors.fill: parent
        color: root.colBackground
        radius: width / 2
        clip: true

        // Inner shadow container (only this item has layer enabled for OpacityMask to prevent layout distortion)
        Item {
            id: shadowContainer
            anchors.fill: parent
            z: 0.1 // Just above background
            layer.enabled: Config.ready ? (Config.options.background.widgets.clock.dial.enableInnerShadow ?? true) : true
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: shadowContainer.width
                    height: shadowContainer.height
                    radius: dialBody.radius
                    antialiasing: true
                }
            }

            // Moldura do Canvas com recorte (furo circular) para projetar a sombra para dentro
            Canvas {
                id: shadowMaskCanvas
                x: -80
                y: -80
                width: shadowContainer.width + 160
                height: shadowContainer.height + 160
                visible: false

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = "black";
                    ctx.beginPath();
                    ctx.rect(0, 0, width, height);
                    ctx.arc(width / 2, height / 2, shadowContainer.width / 2, 0, 2 * Math.PI);
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
                visible: Config.ready ? (Config.options.background.widgets.clock.dial.enableInnerShadow ?? true) : true
            }
        }

        // Outer Thin Ring Accent (inset from boundary by 6px)
        Rectangle {
            width: parent.width - 12
            height: parent.height - 12
            radius: width / 2
            color: "transparent"
            border.color: root.colBorder
            border.width: 2
            anchors.centerIn: parent
        }

        // Inner Thick Ring Accent (inset from boundary by 12px)
        Rectangle {
            width: parent.width - 24
            height: parent.height - 24
            radius: width / 2
            color: "transparent"
            border.color: root.colBorder
            border.width: 8
            anchors.centerIn: parent
            opacity: 0.15
        }

        // Ticks track (120 radial lines)
        Canvas {
            id: ticksCanvas
            anchors.fill: parent
            visible: Config.ready ? (Config.options.background.widgets.clock.dial.showTicks ?? true) : true
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.strokeStyle = root.colTicks;
                ctx.lineWidth = 1.5;

                var cx = width / 2;
                var cy = height / 2;
                var r = cx - 12; // Radius inside thin ring

                for (var i = 0; i < 120; i++) {
                    var angle = (i * 3) * Math.PI / 180;
                    var tickLen = 6; // All ticks uniform length

                    ctx.beginPath();
                    ctx.moveTo(cx + (r - tickLen) * Math.cos(angle), cy + (r - tickLen) * Math.sin(angle));
                    ctx.lineTo(cx + r * Math.cos(angle), cy + r * Math.sin(angle));
                    ctx.stroke();
                }
            }
        }

        // Numbers 12, 3, 6, 9
        Text {
            text: "12"
            font.family: Appearance.font.family.main
            font.pixelSize: parent.width * 0.18
            font.weight: Font.Black
            font.styleName: "Rounded"
            color: root.colNumbers
            anchors {
                top: parent.top
                topMargin: parent.height * 0.11
                horizontalCenter: parent.horizontalCenter
            }
        }

        Text {
            text: "6"
            font.family: Appearance.font.family.main
            font.pixelSize: parent.width * 0.18
            font.weight: Font.Black
            font.styleName: "Rounded"
            color: root.colNumbers
            anchors {
                bottom: parent.bottom
                bottomMargin: parent.height * 0.11
                horizontalCenter: parent.horizontalCenter
            }
        }

        Text {
            text: "3"
            font.family: Appearance.font.family.main
            font.pixelSize: parent.width * 0.18
            font.weight: Font.Black
            font.styleName: "Rounded"
            color: root.colNumbers
            anchors {
                right: parent.right
                rightMargin: parent.width * 0.13
                verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "9"
            font.family: Appearance.font.family.main
            font.pixelSize: parent.width * 0.18
            font.weight: Font.Black
            font.styleName: "Rounded"
            color: root.colNumbers
            anchors {
                left: parent.left
                leftMargin: parent.width * 0.13
                verticalCenter: parent.verticalCenter
            }
        }

        // Hour Hand
        Rectangle {
            id: hourHand
            width: 8
            height: parent.height * 0.28
            radius: width / 2
            color: "transparent"
            border.color: root.colHandBorder
            border.width: 1
            anchors.bottom: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            transformOrigin: Item.Bottom
            rotation: (root.clockHour * 30) + (root.clockMinute * 0.5)

            // Inner filled pill with spacing (gap)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1.5
                radius: height / 2
                color: root.colHandFill
            }

            Behavior on rotation {
                RotationAnimation {
                    duration: 300
                    direction: RotationAnimation.Shortest
                }
            }
        }

        // Minute Hand (configurable via toggle)
        Rectangle {
            id: minuteHand
            width: 8
            height: parent.height * 0.38
            radius: width / 2
            color: "transparent"
            border.color: root.colHandBorder
            border.width: 1
            anchors.bottom: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            transformOrigin: Item.Bottom
            rotation: root.clockMinute * 6
            visible: Config.ready ? (Config.options.background.widgets.clock.dial.showMinuteHand ?? true) : true

            // Inner filled pill with spacing (gap)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1.5
                radius: height / 2
                color: root.colMinuteHandFill
            }

            Behavior on rotation {
                RotationAnimation {
                    duration: 300
                    direction: RotationAnimation.Shortest
                }
            }
        }
    }
}
