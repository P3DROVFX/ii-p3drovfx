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

    configEntryName: "bluetooth_headphone"

    readonly property bool halfSize: Config.options.background.widgets.bluetooth_headphone.halfSize ?? true

    implicitWidth: halfSize ? 120 : 240
    implicitHeight: halfSize ? 240 : 492

    // Device & Battery detection
    readonly property var activeDevices: BluetoothStatus.connectedDevices
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[0] : null
    readonly property bool isConnected: primaryDevice !== null
    readonly property real batteryLevel: (primaryDevice && primaryDevice.batteryAvailable) ? (primaryDevice.battery ?? 0.8) : 0.8
    readonly property int batteryPercent: Math.round(batteryLevel * 100)

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

            // === 1. HEADPHONE HERO IMAGE (Filling 100% of widget with bottom blur + opacity gradient) ===
            Item {
                id: headphoneGroup
                anchors.fill: parent
                opacity: root.isConnected ? 1.0 : 0.35

                Behavior on opacity {
                    NumberAnimation { duration: 300 }
                }

                readonly property string headphoneImageSource: Qt.resolvedUrl("../../../../../assets/images/devices/pixel_headphone1.png")

                // Raw Headphone Image Source
                Item {
                    id: headphoneSourceItem
                    anchors.fill: parent
                    visible: false

                    Image {
                        source: headphoneGroup.headphoneImageSource
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        mipmap: true
                    }
                }

                // Render sharp headphone image
                Image {
                    source: headphoneGroup.headphoneImageSource
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }

                // Blurred Headphone Image Source (for bottom area - doubled blur strength)
                FastBlur {
                    id: blurredHeadphoneSource
                    anchors.fill: parent
                    source: headphoneSourceItem
                    radius: 56
                    visible: false
                }

                // Masked blurred bottom portion of headphone image
                OpacityMask {
                    anchors.fill: parent
                    source: blurredHeadphoneSource
                    maskSource: headphoneBottomBlurMask
                }

                // Overlay gradient at the bottom for text contrast using cardBgColor transparency steps
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.35; color: "transparent" }
                        GradientStop { position: 0.70; color: Qt.rgba(root.cardBgColor.r, root.cardBgColor.g, root.cardBgColor.b, 0.45) }
                        GradientStop { position: 1.0; color: Qt.rgba(root.cardBgColor.r, root.cardBgColor.g, root.cardBgColor.b, 0.90) }
                    }
                }

                // Linear gradient mask for headphone bottom blur (Strengthened & extended higher)
                Item {
                    id: headphoneBottomBlurMask
                    anchors.fill: parent
                    visible: false

                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(0, 0)
                        end: Qt.point(0, parent.height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 0.40; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 0.70; color: Qt.rgba(1, 1, 1, 0.80) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 1.0) }
                        }
                    }
                }
            }

            // === 2. PERCENTAGE TEXT AT BOTTOM (With top-right 45-degree corner blur mask) ===
            Item {
                id: percentageContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root.halfSize ? -8 : -16
                anchors.rightMargin: root.halfSize ? -8 : -16
                anchors.bottomMargin: root.halfSize ? -16 : -32
                height: root.halfSize ? 60 : 120
                visible: root.isConnected

                // Raw Text Source Component
                Item {
                    id: textSourceItem
                    anchors.fill: parent
                    visible: false

                    Text {
                        anchors.centerIn: parent
                        text: root.batteryPercent + "%"
                        color: root.textColorOnBg
                        font {
                            pixelSize: root.halfSize ? 50 : 100
                            weight: Font.Black
                            bold: true
                            family: "Google Sans Flex"
                            variableAxes: ({ "wght": 900, "ROND": 100 })
                        }
                    }
                }

                // Blurred Text Source (Scales radius proportionally to 24 in half-size)
                FastBlur {
                    id: textBlurTipSource
                    anchors.fill: parent
                    source: textSourceItem
                    radius: root.halfSize ? 24 : 48
                    visible: false
                }

                // Sharp text layer
                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: textSourceItem
                    live: true
                }

                // Top-Right Tip Blur Overlay (at 45 degree angle tip only)
                OpacityMask {
                    anchors.fill: parent
                    source: textBlurTipSource
                    maskSource: topRightTipMask
                }

                // Mask for top-right 45° angle tip blur
                Item {
                    id: topRightTipMask
                    anchors.fill: parent
                    visible: false

                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(parent.width * 0.3, 0)
                        end: Qt.point(parent.width, parent.height * 0.7)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.75) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 1.0) }
                        }
                    }
                }

                // Vertical background-colored gradient overlay (from bottom up, 40% opacity) over text
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.50; color: "transparent" }
                        GradientStop { position: 1.0; color: Qt.rgba(root.cardBgColor.r, root.cardBgColor.g, root.cardBgColor.b, 0.40) }
                    }
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
