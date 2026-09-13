pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ColumnLayout {
    id: root

    visible: Battery.available
    spacing: 10

    readonly property int percentage: Math.round(Math.max(0, Math.min(1, Battery.percentage)) * 100)
    readonly property real remainingSeconds: Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty

    readonly property string statusText: {
        if (Battery.chargeLimitReached)
            return Translation.tr("Charge limit reached");
        if (Battery.isCharging)
            return Translation.tr("Charging");
        if (Battery.drainingOnAc)
            return Translation.tr("On AC, still draining");
        if (Battery.isPluggedIn)
            return Translation.tr("Plugged in");
        return Translation.tr("Discharging");
    }

    readonly property string remainingText: {
        if (root.remainingSeconds <= 0)
            return "";
        const hours = Math.floor(root.remainingSeconds / 3600);
        const minutes = Math.floor((root.remainingSeconds % 3600) / 60);
        const duration = hours > 0 ? String(hours) + "h " + String(minutes) + "m" : String(minutes) + "m";
        if (Battery.isCharging)
            return Translation.tr("%1 until charged").arg(duration);
        return Translation.tr("%1 remaining").arg(duration);
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: heroLayout.implicitHeight + 32
        radius: Appearance.rounding.large
        color: Appearance.colors.colPrimaryContainer

        RowLayout {
            id: heroLayout

            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            Android16Battery {
                Layout.preferredWidth: 126
                Layout.preferredHeight: 74
                Layout.alignment: Qt.AlignVCenter
                batteryLevel: root.percentage
                isCharging: Battery.isCharging
                isPowerSaving: false
                colorFillNormal: Appearance.colors.colPrimary
                colorFillCharging: Appearance.colors.colTertiary
                colorFillWarning: Appearance.colors.colError
                colorFillPowerSaving: Appearance.colors.colSecondary
                colorEmptyTrack: Appearance.colors.colSurfaceContainerHighest
                colorTextEmpty: Appearance.colors.colOnPrimaryContainer
                colorTextFilled: Appearance.colors.colOnPrimary
                colorBolt: Appearance.colors.colOnPrimaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Battery")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.75
                }

                StyledText {
                    Layout.fillWidth: true
                    text: String(root.percentage) + "%"
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.hugeass * 1.55
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.statusText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.remainingText.length > 0
                    text: root.remainingText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnPrimaryContainer
                    opacity: 0.75
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 500 ? 3 : (width >= 320 ? 2 : 1)
        columnSpacing: 8
        rowSpacing: 8

        Rectangle {
            visible: Battery.health > 0
            Layout.fillWidth: true
            implicitHeight: 72
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                MaterialSymbol {
                    text: "health_metrics"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Translation.tr("Health")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: String(Math.round(Battery.health)) + "%"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Rectangle {
            visible: Battery.cycles >= 0
            Layout.fillWidth: true
            implicitHeight: 72
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                MaterialSymbol {
                    text: "autorenew"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colTertiary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Translation.tr("Cycles")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: String(Battery.cycles)
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Rectangle {
            visible: Math.abs(Battery.energyRate) > 0.01
            Layout.fillWidth: true
            implicitHeight: 72
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                MaterialSymbol {
                    text: "bolt"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colSecondary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Translation.tr("Power")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: Math.abs(Battery.energyRate).toFixed(1) + " W"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        Rectangle {
            visible: Battery.chargeLimitActive
            Layout.fillWidth: true
            implicitHeight: 72
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                MaterialSymbol {
                    text: "battery_profile"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: Translation.tr("Charge limit")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: String(Battery.chargeLimit) + "%"
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: Battery.chargeLimitStart > 0
                            ? Translation.tr("Charging resumes below %1%").arg(Battery.chargeLimitStart)
                            : Translation.tr("Charging resumes a few points lower")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
