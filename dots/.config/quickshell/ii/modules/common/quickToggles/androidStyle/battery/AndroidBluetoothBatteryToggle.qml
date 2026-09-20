pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Bluetooth Device Battery quick toggle.
 * Ported from the desktop background's BluetoothBatteryWidget.
 *
 * Responsive layout filling the entire tile surface with aligned Pixel Buds and blurred percentage.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.primaryDevice && root.primaryDevice.name) {
            return root.primaryDevice.name + " (" + root.batteryPercent + "%)";
        }
        return Translation.tr("Bluetooth Battery");
    }

    // Device & Battery detection
    readonly property var activeDevices: BluetoothStatus.connectedDevices
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[0] : null
    readonly property bool isConnected: primaryDevice !== null
    readonly property real batteryLevel: (primaryDevice && primaryDevice.batteryAvailable) ? (primaryDevice.battery ?? 0.8) : 0.8
    readonly property int batteryPercent: Math.round(batteryLevel * 100)

    // Palette tokens from WidgetColorScheme
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    Rectangle {
        id: bgRect
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.large
        clip: true

        Item {
            id: container
            anchors.fill: parent

            // === 1. PERCENTAGE TEXT AT BOTTOM (Vertical Progressive Blur) ===
            Item {
                id: percentageContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -Math.round(fontSize * 0.32)
                height: Math.round(fontSize * 1.05)
                visible: root.isConnected

                readonly property real fontSize: Math.max(22, Math.min(parent.height * 0.45, parent.width * 0.45, 100))

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
                            pixelSize: percentageContainer.fontSize
                            weight: Font.Black
                            bold: true
                            family: "Google Sans Flex"
                            variableAxes: ({ "wght": 900, "ROND": 100 })
                        }
                    }
                }

                // Blurred Text Source
                FastBlur {
                    id: blurredTextSource
                    anchors.fill: parent
                    source: textSourceItem
                    radius: Math.max(6, Math.round(percentageContainer.fontSize * 0.28))
                    visible: false
                }

                // Sharp Text (Visible mainly on upper half)
                OpacityMask {
                    anchors.fill: parent
                    source: textSourceItem
                    maskSource: sharpMask
                }

                // Blurred Text (Visible mainly on lower half, fading down)
                OpacityMask {
                    anchors.fill: parent
                    source: blurredTextSource
                    maskSource: blurMask
                }

                // Gradient mask for Sharp Top Portion
                Item {
                    id: sharpMask
                    anchors.fill: parent
                    visible: false

                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(0, 0)
                        end: Qt.point(0, parent.height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 1.0) }
                            GradientStop { position: 0.50; color: Qt.rgba(1, 1, 1, 1.0) }
                            GradientStop { position: 0.72; color: Qt.rgba(1, 1, 1, 0.35) }
                            GradientStop { position: 0.95; color: Qt.rgba(1, 1, 1, 0.0) }
                        }
                    }
                }

                // Gradient mask for Blurred Bottom Portion
                Item {
                    id: blurMask
                    anchors.fill: parent
                    visible: false

                    LinearGradient {
                        anchors.fill: parent
                        start: Qt.point(0, 0)
                        end: Qt.point(0, parent.height)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                            GradientStop { position: 0.52; color: Qt.rgba(1, 1, 1, 0.15) }
                            GradientStop { position: 0.80; color: Qt.rgba(1, 1, 1, 0.95) }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.25) }
                        }
                    }
                }
            }

            // === 2. PIXEL BUDS COMPOSITION ===
            Item {
                id: budsGroup
                anchors.fill: parent
                opacity: root.isConnected ? 1.0 : 0.35

                Behavior on opacity {
                    NumberAnimation { duration: 300 }
                }

                readonly property string budsImageSource: Qt.resolvedUrl("../../../../../assets/images/devices/pixel_buds.png")
                readonly property real budSize: Math.max(36, Math.min(parent.width * 0.48, parent.height * 0.48, 115))

                Item {
                    id: rawBudsComposition
                    anchors.fill: parent
                    visible: false

                    // Upper Right Earbud
                    Image {
                        source: budsGroup.budsImageSource
                        width: budsGroup.budSize
                        height: budsGroup.budSize
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: parent.width * 0.48
                        y: parent.height * 0.10
                        rotation: -170
                    }

                    // Lower Left Earbud
                    Image {
                        source: budsGroup.budsImageSource
                        width: budsGroup.budSize
                        height: budsGroup.budSize
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: parent.width * 0.15
                        y: parent.height * 0.34
                        rotation: 0
                    }
                }

                FastBlur {
                    anchors.fill: parent
                    source: rawBudsComposition
                    radius: 2
                }

                DropShadow {
                    anchors.fill: parent
                    source: sharpBudsContainer
                    radius: 16
                    samples: 33
                    color: Qt.rgba(0, 0, 0, 0.40)
                    horizontalOffset: 0
                    verticalOffset: 5
                }

                Item {
                    id: sharpBudsContainer
                    anchors.fill: parent

                    // Upper Right Earbud
                    Image {
                        source: budsGroup.budsImageSource
                        width: budsGroup.budSize
                        height: budsGroup.budSize
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: parent.width * 0.48
                        y: parent.height * 0.10
                        rotation: -170
                    }

                    // Lower Left Earbud
                    Image {
                        source: budsGroup.budsImageSource
                        width: budsGroup.budSize
                        height: budsGroup.budSize
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        x: parent.width * 0.15
                        y: parent.height * 0.34
                        rotation: 0
                    }
                }
            }
        }
    }
}
