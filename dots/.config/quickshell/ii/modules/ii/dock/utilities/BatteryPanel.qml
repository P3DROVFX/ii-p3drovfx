import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Battery details: draw, health, cycles and the charge limit, as caption/value rows. */
ColumnLayout {
    id: panel

    property var host: null

    readonly property var rows: [
        { symbol: "speed", caption: Translation.tr("Power draw"),
          value: Math.abs(Battery.energyRate) > 0.05 ? Math.abs(Battery.energyRate).toFixed(1) + " W" : "—" },
        { symbol: "favorite", caption: Translation.tr("Health"),
          value: Battery.health > 0 ? Math.round(Battery.health) + "%" : "—" },
        { symbol: "autorenew", caption: Translation.tr("Charge cycles"),
          value: Battery.cycles >= 0 ? String(Battery.cycles) : "—" },
        { symbol: "battery_charging_80", caption: Translation.tr("Charge limit"),
          value: Battery.chargeLimitActive ? Battery.chargeLimit + "%" : Translation.tr("Off") }
    ]

    spacing: 4

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 4
        rowSpacing: 4

        Repeater {
            model: panel.rows
            delegate: Rectangle {
                id: cell
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 72
                radius: ClockStyle.radiusNormal
                color: ClockStyle.colField

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 0
                    RowLayout {
                        spacing: 4
                        MaterialSymbol {
                            text: cell.modelData.symbol
                            iconSize: 14
                            fill: 1
                            color: ClockStyle.colOnSurfaceVariant
                        }
                        StyledText {
                            text: cell.modelData.caption
                            color: ClockStyle.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                        }
                    }
                    Item { Layout.fillHeight: true }
                    StyledText {
                        text: cell.modelData.value
                        color: ClockStyle.colOnSurface
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: 24
                    }
                }
            }
        }
    }

    ClockButton {
        Layout.fillWidth: true
        Layout.topMargin: 4
        symbol: "settings"
        label: Translation.tr("Battery settings")
        onClicked: {
            panel.host?.closePanel();
            GlobalStates.openSettingsPage("power");
        }
    }
}
