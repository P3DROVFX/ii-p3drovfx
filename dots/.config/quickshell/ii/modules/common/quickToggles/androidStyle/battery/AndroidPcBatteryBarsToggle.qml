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
 * PC Battery Bars quick toggle.
 * Ported from the desktop background's PcBatteryBarsWidget.
 *
 * Responsive layout filling the entire tile surface with 5 vertical bars and charging color.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        var status = root.isCharging ? Translation.tr("Charging") : Translation.tr("Discharging");
        return Translation.tr("Battery") + ": " + root.batteryPct + "% (" + status + ")";
    }

    // PC Battery system info
    readonly property real batteryPct: Math.round((Battery.percentage ?? 0.52) * 100)
    readonly property bool isCharging: Battery.isCharging || Battery.isPluggedIn
    readonly property real timeRemainingSec: isCharging ? (Battery.timeToFull ?? 7200) : (Battery.timeToEmpty ?? 7200)
    readonly property int hoursRemaining: Math.floor(timeRemainingSec / 3600)

    readonly property color lightGreenCharging: "#c4f3a6"
    readonly property color activeCardBg: root.isCharging ? root.lightGreenCharging : WidgetColorScheme.cardBgColor
    readonly property color activeAccentColor: root.isCharging ? Appearance.colors.colPrimary : WidgetColorScheme.accentColor

    Rectangle {
        id: cardBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.activeCardBg)
        radius: Appearance.rounding.large
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.max(8, Math.round(root.surface.height * 0.08))
            spacing: 2

            // Top Header: Charging Bolt + Percentage
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                MaterialSymbol {
                    visible: root.isCharging
                    text: "bolt"
                    iconSize: Math.max(16, Math.min(28, Math.round(root.surface.height * 0.16)))
                    color: root.activeAccentColor
                }

                Text {
                    text: root.batteryPct + "%"
                    color: root.activeAccentColor
                    font {
                        pixelSize: Math.max(18, Math.min(36, Math.round(root.surface.height * 0.18)))
                        weight: Font.Normal
                        bold: false
                        family: "Google Sans Flex"
                        variableAxes: ({ "wght": 600, "ROND": 100 })
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Center 5 Vertical Bars Container
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(parent.width * 0.85, root.surface.height * 1.2)
                Layout.preferredHeight: Math.max(26, Math.min(parent.height * 0.44, 80))
                radius: Appearance.rounding.normal
                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.12)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Math.max(4, Math.round(parent.height * 0.12))
                    spacing: Math.max(3, Math.round(parent.width * 0.03))

                    Repeater {
                        model: 5

                        delegate: Item {
                            id: barDelegate
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            readonly property int barIndex: index // 0 to 4
                            readonly property real barThreshold: (barIndex + 1) * 20.0
                            readonly property real prevThreshold: barIndex * 20.0
                            readonly property real currentPct: root.batteryPct

                            // Fill ratio for this specific bar (0.0 to 1.0)
                            readonly property real fillRatio: {
                                if (currentPct >= barThreshold) return 1.0
                                if (currentPct <= prevThreshold) return 0.0
                                return (currentPct - prevThreshold) / 20.0
                            }

                            // Background Track for Bar
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.small
                                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.15)
                            }

                            // Active Fill Bar
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * barDelegate.fillRatio
                                radius: Appearance.rounding.small
                                color: root.activeAccentColor

                                Behavior on height {
                                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Bottom Estimated Time Text
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.hoursRemaining > 0 ? ("~ " + root.hoursRemaining + " " + Translation.tr("hours")) : Translation.tr("Calculating...")
                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.70)
                font {
                    pixelSize: Math.max(10, Math.min(16, Math.round(root.surface.height * 0.10)))
                    weight: Font.Medium
                    family: "Google Sans Flex"
                }
            }
        }
    }
}
