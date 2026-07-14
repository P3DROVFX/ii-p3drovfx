import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property int batteryPercent: Math.round(Battery.percentage * 100)
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPowerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isPerformance: PowerProfiles.profile === PowerProfile.Performance

    readonly property color accentColor: isCharging ? "#18CC47"
        : isPowerSaving ? "#fbbc04"
        : isPerformance ? "#42A5F5"
        : Appearance.colors.colPrimary

    readonly property string statusText: {
        if (isCharging && Battery.isFull) return Translation.tr("Fully Charged");
        if (isCharging) return Translation.tr("Charging");
        if (isPowerSaving) return Translation.tr("Low Power Mode");
        if (isPerformance) return Translation.tr("Performance Mode");
        return Translation.tr("On Battery");
    }

    readonly property string timeText: {
        if (isCharging && Battery.timeToFull > 0) {
            var h = Math.floor(Battery.timeToFull / 60);
            var m = Math.round(Battery.timeToFull % 60);
            if (h > 0) return (h > 0 ? String(h) + "h " : "") + String(m) + "m " + Translation.tr("to full");
            return String(m) + " min " + Translation.tr("to full");
        }
        if (!isCharging && Battery.timeToEmpty > 0) {
            var h2 = Math.floor(Battery.timeToEmpty / 60);
            var m2 = Math.round(Battery.timeToEmpty % 60);
            if (h2 > 0) return String(h2) + "h " + String(m2) + "m " + Translation.tr("remaining");
            return String(m2) + " min " + Translation.tr("remaining");
        }
        return "";
    }

    readonly property string profileIcon: isPowerSaving ? "energy_savings_leaf"
        : isPerformance ? "local_fire_department"
        : "airwave"

    readonly property string profileLabel: isPowerSaving ? Translation.tr("Power Saver")
        : isPerformance ? Translation.tr("Performance")
        : Translation.tr("Balanced")

    // ── Contracted ──────────────────────────────────────────────────────

    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 8
        visible: !root.isExpanded

        MaterialSymbol {
            id: boltIcon
            text: root.isCharging ? "bolt"
                : root.isPowerSaving ? "energy_savings_leaf"
                : root.isPerformance ? "local_fire_department"
                : "battery_full"
            fill: 1
            iconSize: 16
            color: root.accentColor
            Layout.alignment: Qt.AlignVCenter

            SequentialAnimation on opacity {
                running: root.isCharging && contractedLayout.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 1200; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutQuad }
            }
        }

        StyledText {
            text: String(root.batteryPercent) + "%"
            font.pixelSize: Appearance.font.pixelSize.small
            font.bold: true
            color: root.accentColor
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // ── Expanded ────────────────────────────────────────────────────────

    Item {
        id: expandedLayout
        anchors.fill: parent
        visible: root.isExpanded

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    text: String(root.batteryPercent) + "%"
                    font.pixelSize: 30
                    font.bold: true
                    color: root.accentColor
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 44
                    height: 22
                    radius: 5
                    color: "transparent"
                    clip: true

                    Rectangle {
                        width: 3
                        height: 10
                        radius: 1
                        x: parent.width + 1
                        y: (parent.height - 10) / 2
                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        opacity: 0.35
                        scale: 1 - 2 / parent.height
                        layer.enabled: true
                        layer.smooth: true
                    }

                    Rectangle {
                        id: expFillRect
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, (parent.width - 4) * root.batteryPercent / 100)
                        height: parent.height - 4
                        radius: 3
                        color: root.accentColor

                        Behavior on width {
                            NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            StyledText {
                text: root.statusText
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                text: root.timeText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOutlineVariant
                visible: root.timeText !== ""
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: root.profileIcon
                    iconSize: 14
                    color: root.isPowerSaving ? "#fbbc04"
                        : root.isPerformance ? "#42A5F5"
                        : Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    text: root.profileLabel
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnSurfaceVariant
                    Layout.fillWidth: true
                }

                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: Qt.rgba(Appearance.colors.colOnSurface.r, Appearance.colors.colOnSurface.g, Appearance.colors.colOnSurface.b, 0.08)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (PowerProfiles.hasPerformanceProfile) {
                                if (PowerProfiles.profile === PowerProfile.PowerSaver)
                                    PowerProfiles.profile = PowerProfile.Balanced;
                                else if (PowerProfiles.profile === PowerProfile.Balanced)
                                    PowerProfiles.profile = PowerProfile.Performance;
                                else
                                    PowerProfiles.profile = PowerProfile.PowerSaver;
                            } else {
                                PowerProfiles.profile = PowerProfiles.profile === PowerProfile.PowerSaver
                                    ? PowerProfile.Balanced : PowerProfile.PowerSaver;
                            }
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "swap_horiz"
                        iconSize: 14
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }
}
