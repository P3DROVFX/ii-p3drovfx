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

    configEntryName: "pc_battery_cable"

    implicitWidth: 240
    implicitHeight: 240

    // PC Battery system info
    readonly property real batteryPct: Math.round((Battery.percentage ?? 0.74) * 100)
    readonly property bool isCharging: Battery.isCharging || Battery.isPluggedIn

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color fgColor: WidgetColorScheme.textColorOnBg

    StyledRectangularShadow {
        id: bgShadow
        target: cardBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        anchors.margins: 10
        color: root.cardBgColor
        radius: Appearance.rounding.windowRounding

        Item {
            anchors.fill: parent
            anchors.margins: 0

            // Top-Left Custom Cable Plug & Bolt Icon made using simple Rectangles
            Item {
                id: chargerCableGroup
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 24
                width: 140
                height: 40

                // Horizontal Cable Wire flush to left margin 0
                Rectangle {
                    id: cableWire
                    anchors.left: parent.left
                    anchors.verticalCenter: plugBody.verticalCenter
                    width: 38
                    height: 5
                    color: root.fgColor
                }

                // Charger Plug Body
                Rectangle {
                    id: plugBody
                    anchors.left: cableWire.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 32
                    radius: 6
                    color: root.fgColor
                }

                // Charger Connector Tip (Outline Rectangle seamlessly attached to plug body)
                Rectangle {
                    anchors.left: plugBody.right
                    anchors.verticalCenter: plugBody.verticalCenter
                    anchors.leftMargin: -6
                    width: 22
                    height: 22
                    radius: 6
                    color: "transparent"
                    border.color: root.fgColor
                    border.width: 1
                }

                // Charging Bolt Icon (if charging)
                MaterialSymbol {
                    anchors.left: plugBody.right
                    anchors.leftMargin: 28
                    anchors.verticalCenter: plugBody.verticalCenter
                    visible: root.isCharging
                    text: "bolt"
                    iconSize: 20
                    color: root.fgColor
                }
            }

            // Bottom-Right Percentage Text (thinner, matching image reference)
            ColumnLayout {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 18
                anchors.bottomMargin: 16
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignRight
                    text: root.batteryPct + "%"
                    color: root.fgColor
                    font {
                        pixelSize: 42
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
