pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Bluetooth Headphone Cookie quick toggle.
 * Ported from the desktop background's BluetoothHeadphoneCookieWidget.
 *
 * Centered 1:1 circular Material Shape Cookie container scaled responsively.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.primaryDevice && root.primaryDevice.name) {
            return root.primaryDevice.name + " (" + root.batteryPercent + "%)";
        }
        return Translation.tr("Bluetooth Headphone");
    }

    readonly property string selectedShape: Config.options.background.widgets.bluetooth_headphone_cookie.materialShape ?? "Cookie12Sided"

    // Device & Battery detection
    readonly property var activeDevices: BluetoothStatus.connectedDevices
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[0] : null
    readonly property bool isConnected: primaryDevice !== null
    readonly property real batteryLevel: (primaryDevice && primaryDevice.batteryAvailable) ? (primaryDevice.battery ?? 0.8) : 0.8
    readonly property int batteryPercent: Math.round(batteryLevel * 100)

    // Palette tokens from WidgetColorScheme
    readonly property color outerCircleColor: WidgetColorScheme.pillBgColor
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    readonly property real circleSize: Math.max(32, Math.min(root.surface.width, root.surface.height) - 12)

    // Outer Circle Container (Centered Square/Circle)
    Rectangle {
        id: outerCircle
        anchors.centerIn: parent
        width: root.circleSize
        height: root.circleSize
        radius: width / 2
        color: WidgetColorScheme.tintBackground(root.outerCircleColor)

        // Inner Material Shape Container (Cookie12Sided by default)
        MaterialShape {
            id: innerCookie
            anchors.centerIn: parent
            implicitSize: outerCircle.width * 0.94
            shapeString: root.selectedShape
            color: "transparent"

            // Background Fill Shape
            MaterialShape {
                id: cookieBg
                anchors.fill: parent
                shapeString: parent.shapeString
                color: WidgetColorScheme.tintBackground(root.cardBgColor)
            }

            // Masked Content inside the Cookie Shape
            Item {
                id: shapeContentContainer
                anchors.fill: parent

                layer.enabled: true
                layer.smooth: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: shapeContentContainer.width
                        height: shapeContentContainer.height
                        shapeString: root.selectedShape
                        color: "black"
                    }
                }

                // === 1. COMPLETE HEADPHONE IMAGE WITH 45° DEPTH GRADIENT FADE ===
                Item {
                    id: headphoneCompleteGroup
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    opacity: root.isConnected ? 1.0 : 0.35

                    readonly property string completeImageSource: Qt.resolvedUrl("../../../../../assets/images/devices/pixel_headphone_2_complete.png")

                    // Base Complete Image
                    Image {
                        id: completeImage
                        anchors.fill: parent
                        source: headphoneCompleteGroup.completeImageSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    // Linear Gradient Fade Overlay
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0.0
                                color: "transparent"
                            }
                            GradientStop {
                                position: 0.40
                                color: Qt.rgba(root.cardBgColor.r, root.cardBgColor.g, root.cardBgColor.b, 0.30)
                            }
                            GradientStop {
                                position: 0.75
                                color: Qt.rgba(root.cardBgColor.r, root.cardBgColor.g, root.cardBgColor.b, 0.85)
                            }
                            GradientStop {
                                position: 1.0
                                color: root.cardBgColor
                            }
                        }
                    }
                }

                // === 2. PERCENTAGE TEXT (Behind Front Image, in front of Complete Image) ===
                Item {
                    id: percentageContainer
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: Math.round(parent.width * 0.11)
                    anchors.verticalCenterOffset: -Math.round(parent.height * 0.18)
                    width: Math.round(parent.width * 0.58)
                    height: Math.round(parent.height * 0.35)
                    visible: root.isConnected

                    Text {
                        anchors.centerIn: parent
                        text: root.batteryPercent + "%"
                        color: root.textColorOnBg
                        font {
                            pixelSize: Math.max(12, Math.round(parent.parent.width * 0.22))
                            weight: Font.Black
                            bold: true
                            family: "Google Sans Flex"
                            variableAxes: ({
                                "wght": 900,
                                "ROND": 100
                            })
                        }
                    }
                }

                // === 3. FRONT HEADPHONE IMAGE (Positioned identically on top of text) ===
                Item {
                    id: headphoneFrontGroup
                    anchors.centerIn: parent
                    width: parent.width
                    height: parent.height
                    opacity: root.isConnected ? 1.0 : 0.35

                    readonly property string frontImageSource: Qt.resolvedUrl("../../../../../assets/images/devices/pixel_headphone_2_front.png")

                    Image {
                        anchors.fill: parent
                        source: headphoneFrontGroup.frontImageSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                }
            }
        }
    }
}
