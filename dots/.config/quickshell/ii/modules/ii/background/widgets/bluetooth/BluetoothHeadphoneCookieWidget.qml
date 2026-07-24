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

    configEntryName: "bluetooth_headphone_cookie"

    implicitWidth: 240
    implicitHeight: 240

    readonly property string selectedShape: Config.options.background.widgets.bluetooth_headphone_cookie.materialShape ?? "Cookie12Sided"

    // Device & Battery detection
    readonly property var activeDevices: BluetoothStatus.connectedDevices
    readonly property var primaryDevice: activeDevices.length > 0 ? activeDevices[0] : null
    readonly property bool isConnected: primaryDevice !== null
    readonly property real batteryLevel: (primaryDevice && primaryDevice.batteryAvailable) ? (primaryDevice.battery ?? 0.8) : 0.8
    readonly property int batteryPercent: Math.round(batteryLevel * 100)

    // Palette tokens from WidgetColorScheme
    readonly property color outerCircleColor: Appearance.colors.colPrimary
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg

    StyledDropShadow {
        id: shadowEffect
        target: outerCircle
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    // Outer Circle Container with 8px margins
    Rectangle {
        id: outerCircle
        anchors.fill: parent
        anchors.margins: -8
        radius: width / 2
        color: root.outerCircleColor

        // Inner Material Shape Container (Cookie12Sided by default)
        MaterialShape {
            id: innerCookie
            anchors.centerIn: parent
            implicitSize: outerCircle.width * 0.96
            shapeString: root.selectedShape
            color: "transparent"

            // Background Fill Shape
            MaterialShape {
                id: cookieBg
                anchors.fill: parent
                shapeString: parent.shapeString
                color: root.cardBgColor
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
                    height: parent.height * 0.85
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

                    // Linear Gradient Fade Overlay (45° angle: left 0% opacity -> right 100% cardBgColor opacity)
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
                    anchors.horizontalCenterOffset: 26
                    anchors.verticalCenterOffset: -44
                    width: 140
                    height: 80
                    visible: root.isConnected

                    Text {
                        anchors.centerIn: parent
                        text: root.batteryPercent + "%"
                        color: root.textColorOnBg
                        font {
                            pixelSize: 52
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
                    height: parent.height * 0.85
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

            // Optional Inner Shadow
            InnerShadow {
                anchors.fill: parent
                radius: 20
                samples: 41
                color: Qt.rgba(0, 0, 0, 0.35)
                source: cookieBg
                visible: Config.options.background.widgets.enableInnerShadow ?? true
            }
        }
    }
}
