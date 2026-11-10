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
 * PC Battery Cable quick toggle.
 * Ported from the desktop background's PcBatteryCableWidget.
 *
 * Responsive layout filling the entire tile surface with custom cable plug visual and percentage readout.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        var status = root.isCharging ? Translation.tr("Charging") : Translation.tr("Discharging");
        return Translation.tr("Battery") + ": " + root.batteryPct + "% (" + status + ")";
    }

    // PC Battery system info
    readonly property real batteryPct: Math.round((Battery.percentage ?? 0.74) * 100)
    readonly property bool isCharging: Battery.isCharging || Battery.isPluggedIn

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color fgColor: WidgetColorScheme.textColorOnBg

    Rectangle {
        id: cardBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.cardBgColor)
        radius: Appearance.rounding.large
        clip: true

        Item {
            anchors.fill: parent
            anchors.margins: Math.max(12, Math.round(root.surface.height * 0.10))

            // Top-Left Custom Cable Plug & Bolt Icon
            Item {
                id: chargerCableGroup
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: Math.max(4, Math.round(parent.height * 0.04))
                width: Math.min(parent.width * 0.70, root.surface.height * 0.90)
                height: Math.max(28, Math.min(48, Math.round(root.surface.height * 0.22)))

                // Horizontal Cable Wire flush to left margin 0
                Rectangle {
                    id: cableWire
                    anchors.left: parent.left
                    anchors.verticalCenter: plugBody.verticalCenter
                    width: Math.max(18, Math.round(parent.width * 0.28))
                    height: Math.max(3, Math.round(parent.height * 0.14))
                    color: root.fgColor
                }

                // Charger Plug Body
                Rectangle {
                    id: plugBody
                    anchors.left: cableWire.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(32, Math.round(parent.width * 0.38))
                    height: Math.max(20, Math.round(parent.height * 0.80))
                    radius: Appearance.rounding.small
                    color: root.fgColor
                }

                // Charger Connector Tip
                Rectangle {
                    anchors.left: plugBody.right
                    anchors.verticalCenter: plugBody.verticalCenter
                    anchors.leftMargin: -Math.max(2, Math.round(plugBody.height * 0.15))
                    width: Math.max(14, Math.round(plugBody.height * 0.65))
                    height: Math.max(14, Math.round(plugBody.height * 0.65))
                    radius: Appearance.rounding.small
                    color: "transparent"
                    border.color: root.fgColor
                    border.width: 1
                }

                // Charging Bolt Icon
                MaterialSymbol {
                    anchors.left: plugBody.right
                    anchors.leftMargin: Math.max(18, Math.round(plugBody.height * 0.85))
                    anchors.verticalCenter: plugBody.verticalCenter
                    visible: root.isCharging
                    text: "bolt"
                    iconSize: Math.max(16, Math.min(26, Math.round(plugBody.height * 0.70)))
                    color: root.fgColor
                }
            }

            // Bottom-Right Percentage Text
            ColumnLayout {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Math.max(4, Math.round(parent.width * 0.03))
                anchors.bottomMargin: Math.max(2, Math.round(parent.height * 0.02))
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.batteryPct + "%"
                    color: root.fgColor
                    font {
                        pixelSize: Math.max(26, Math.min(root.surface.height * 0.38, root.surface.width * 0.38, 72))
                        weight: Font.DemiBold
                        bold: false
                        family: "Google Sans Flex"
                        variableAxes: ({ "wght": 600, "RNDS": 100 })
                    }
                }
            }
        }
    }
}
