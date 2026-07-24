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

    configEntryName: "mobile_battery"

    implicitWidth: 240
    implicitHeight: 240

    // Device & Battery detection via KdeConnectService
    readonly property var activeDevice: KdeConnectService.activeDevice
    readonly property bool isConnected: KdeConnectService.activeReachable && activeDevice !== null
    readonly property int batteryPercent: (isConnected && activeDevice.charge !== undefined && activeDevice.charge >= 0)
                                           ? Math.round(activeDevice.charge)
                                           : 80

    // Palette tokens from WidgetColorScheme
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

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

        // Perfect rounded-corner mask for all content inside the card
        layer.enabled: true
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
            id: container
            anchors.fill: parent

            // === 1. PERCENTAGE TEXT AT TOP-RIGHT (Partially behind phone image) ===
            Item {
                id: percentageContainer
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -8
                anchors.rightMargin: -8
                width: parent.width * 0.90
                height: 100
                visible: root.isConnected

                Text {
                    anchors.centerIn: parent
                    text: root.batteryPercent + "%"
                    color: root.textColorOnBg
                    font {
                        pixelSize: 96
                        weight: Font.Black
                        bold: true
                        family: "Google Sans Flex"
                        variableAxes: ({ "wght": 900, "ROND": 100 })
                    }
                }
            }

            // === 2. MOBILE PHONE DEVICE IMAGE (Aligned to bottom-left, occupying ~85% width and ~85% height) ===
            Item {
                id: phoneGroup
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: -10
                anchors.bottomMargin: -10
                width: parent.width * 0.86
                height: parent.height * 0.84
                opacity: root.isConnected ? 1.0 : 0.35

                Behavior on opacity {
                    NumberAnimation { duration: 300 }
                }

                readonly property string phoneImageSource: Qt.resolvedUrl("../../../../../assets/images/devices/pixel_3d.png")

                // Drop Shadow for the 3D Phone Image
                DropShadow {
                    anchors.fill: parent
                    source: phoneImage
                    radius: 20
                    samples: 41
                    color: Qt.rgba(0, 0, 0, 0.35)
                    horizontalOffset: 4
                    verticalOffset: 6
                }

                // 3D Phone Image (Aligned to bottom-left)
                Image {
                    id: phoneImage
                    anchors.fill: parent
                    source: phoneGroup.phoneImageSource
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: Image.AlignLeft
                    verticalAlignment: Image.AlignBottom
                    smooth: true
                    mipmap: true
                }
            }
        }

        // Inner shadow Canvas mask
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
