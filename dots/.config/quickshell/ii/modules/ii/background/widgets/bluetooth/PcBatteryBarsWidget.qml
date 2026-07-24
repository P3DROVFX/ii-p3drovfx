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

    configEntryName: "pc_battery_bars"

    implicitWidth: 240
    implicitHeight: 240

    // PC Battery system info
    readonly property real batteryPct: Math.round((Battery.percentage ?? 0.52) * 100)
    readonly property bool isCharging: Battery.isCharging || Battery.isPluggedIn
    readonly property real timeRemainingSec: isCharging ? (Battery.timeToFull ?? 7200) : (Battery.timeToEmpty ?? 7200)
    readonly property int hoursRemaining: Math.floor(timeRemainingSec / 3600)

    // Color definitions per spec:
    // Charging background: Hardcoded light green (#c4f3a6) per request.
    // All accents, text, and bars use strict Appearance design tokens.
    readonly property color lightGreenCharging: "#c4f3a6"

    readonly property color activeCardBg: root.isCharging ? root.lightGreenCharging : WidgetColorScheme.cardBgColor
    readonly property color activeAccentColor: root.isCharging ? Appearance.colors.colPrimary : WidgetColorScheme.accentColor

    StyledRectangularShadow {
        id: bgShadow
        target: cardBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        anchors.margins: 10
        color: root.activeCardBg
        radius: Appearance.rounding.windowRounding

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 0

            // Top Header: Charging Bolt + Percentage
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                MaterialSymbol {
                    visible: root.isCharging
                    text: "bolt"
                    iconSize: 26
                    color: root.activeAccentColor
                }

                Text {
                    text: root.batteryPct + "%"
                    color: root.activeAccentColor
                    font {
                        pixelSize: 34
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
                Layout.preferredWidth: 170
                Layout.preferredHeight: 76
                radius: 18
                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.12)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

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
                                radius: 8
                                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.15)
                            }

                            // Active Fill Bar (Decreasing height from top to bottom)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * barDelegate.fillRatio
                                radius: 8
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
                    pixelSize: 17
                    weight: Font.Medium
                    family: "Google Sans Flex"
                }
            }
        }
    }
}
