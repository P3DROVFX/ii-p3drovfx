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
 * Mobile Phone Battery quick toggle.
 * Ported from the desktop background's MobileBatteryWidget.
 *
 * Responsive layout filling the entire tile surface with 3D phone and top-right percentage.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.isConnected && root.activeDevice) {
            var name = KdeConnectService.activeDeviceDisplayName || root.activeDevice.name || Translation.tr("Phone");
            return name + " (" + root.batteryPercent + "%)";
        }
        return Translation.tr("Phone Battery");
    }

    // Device & Battery detection via KdeConnectService
    readonly property var activeDevice: KdeConnectService.activeDevice
    readonly property bool isConnected: KdeConnectService.activeReachable && activeDevice !== null
    readonly property int batteryPercent: (isConnected && activeDevice.charge !== undefined && activeDevice.charge >= 0)
                                           ? Math.round(activeDevice.charge)
                                           : 80

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

            // === 1. PERCENTAGE TEXT AT TOP-RIGHT ===
            Item {
                id: percentageContainer
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -4
                anchors.rightMargin: 4
                width: parent.width * 0.85
                height: Math.round(fontSize * 1.05)
                visible: root.isConnected

                readonly property real fontSize: Math.max(22, Math.min(parent.height * 0.44, parent.width * 0.44, 96))

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

            // === 2. MOBILE PHONE DEVICE IMAGE (Bottom-Left) ===
            Item {
                id: phoneGroup
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: -6
                anchors.bottomMargin: -6
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
                    radius: 16
                    samples: 33
                    color: Qt.rgba(0, 0, 0, 0.35)
                    horizontalOffset: 3
                    verticalOffset: 5
                }

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
    }
}
