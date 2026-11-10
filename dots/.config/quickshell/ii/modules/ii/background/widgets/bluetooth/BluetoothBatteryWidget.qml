import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.modules.ii.background.overview

AbstractBackgroundWidget {
    id: root

    configEntryName: "bluetooth_battery"

    implicitWidth: 240
    implicitHeight: 240

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
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.windowRounding

        // Perfect rounded-corner mask for all content inside the card (preventing any blur/text bleed)
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

            // === 1. PERCENTAGE TEXT AT BOTTOM (Vertical Progressive Blur) ===
            // The figure sinks below the card's bottom edge and blurs harder the
            // lower it goes. One layer, blurred by a shader whose radius grows
            // along y: the old sharp/blurred pair crossfaded through two
            // gradient masks only faded the text out, and FastBlur clipped the
            // glyphs to a box shorter than the type.
            Item {
                id: percentageContainer
                // Room around the glyphs for the blur to spread into; the card
                // clips what falls past its edge.
                readonly property real blurPadding: 24
                readonly property real textBoxHeight: 105
                readonly property real sinkBelowCard: 32
                // The card's bottom edge, as a fraction of this item's height.
                readonly property real cardEdgeAt: (height - blurPadding - sinkBelowCard) / height

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -(sinkBelowCard + blurPadding)
                height: textBoxHeight + blurPadding * 2
                visible: root.isConnected

                Text {
                    anchors.centerIn: parent
                    text: root.batteryPercent + "%"
                    color: root.textColorOnBg
                    font {
                        pixelSize: 100
                        weight: Font.Black
                        bold: true
                        family: "Google Sans Flex"
                        variableAxes: ({ "wght": 900, "ROND": 100 })
                    }
                }

                layer.enabled: visible
                layer.smooth: true
                layer.effect: ProgressiveBlur {
                    blurStart: (percentageContainer.blurPadding + percentageContainer.textBoxHeight * 0.1) / percentageContainer.height
                    blurEnd: percentageContainer.cardEdgeAt
                    maxRadius: 12
                    endOpacity: 0.6
                }
            }

            // === 2. PIXEL BUDS COMPOSITION (Top right & Center left earbuds) ===
            Item {
                id: budsGroup
                anchors.fill: parent
                opacity: root.isConnected ? 1.0 : 0.35

                Behavior on opacity {
                    NumberAnimation { duration: 300 }
                }

                // Dynamic image source without hardcoded absolute string
                readonly property string budsImageSource: Qt.resolvedUrl("../../../../../assets/images/devices/pixel_buds.png")

                // Source composition item for feathering & soft edge blur
                Item {
                    id: rawBudsComposition
                    anchors.fill: parent
                    visible: false

                    // Upper Right Earbud (Rotated -170 degrees, shifted right +12px for centering)
                    Image {
                        source: budsGroup.budsImageSource
                        width: 112
                        height: 112
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: 92
                        y: 26
                        rotation: -170
                    }

                    // Lower Left Earbud (Rotated 0 degrees, shifted right +12px for centering)
                    Image {
                        source: budsGroup.budsImageSource
                        width: 112
                        height: 112
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: 38
                        y: 81
                        rotation: 0
                    }
                }

                // Feathered soft edge blur layer
                FastBlur {
                    anchors.fill: parent
                    source: rawBudsComposition
                    radius: 2
                }

                // Drop Shadow for the earbuds (Soft offset shadow matching reference image)
                DropShadow {
                    anchors.fill: parent
                    source: sharpBudsContainer
                    radius: 20
                    samples: 41
                    color: Qt.rgba(0, 0, 0, 0.40)
                    horizontalOffset: 0
                    verticalOffset: 6
                }

                // Sharp main earbud render on top
                Item {
                    id: sharpBudsContainer
                    anchors.fill: parent

                    // Upper Right Earbud (Rotated -170 degrees, shifted right +12px for centering)
                    Image {
                        source: budsGroup.budsImageSource
                        width: 112
                        height: 112
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: 92
                        y: 26
                        rotation: -170
                    }

                    // Lower Left Earbud (Rotated 0 degrees, shifted right +12px for centering)
                    Image {
                        source: budsGroup.budsImageSource
                        width: 112
                        height: 112
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: 38
                        y: 81
                        rotation: 0
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
