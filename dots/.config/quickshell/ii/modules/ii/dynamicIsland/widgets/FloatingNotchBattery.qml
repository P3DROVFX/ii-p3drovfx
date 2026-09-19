import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell.Services.UPower

Item {
    id: root
    anchors.fill: parent


    readonly property int batteryPercent: Math.round(Battery.percentage * 100)
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isFull: Battery.isFullyCharged || Battery.chargeLimitReached
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property bool isPowerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isPerformance: PowerProfiles.profile === PowerProfile.Performance

    readonly property color accentColor: (isCharging || isFull) ? "#18CC47"
        : isPowerSaving ? "#fbbc04"
        : isPerformance ? "#42A5F5"
        : Appearance.colors.colPrimary

    readonly property string statusText: {
        if (Battery.chargeLimitReached) return Translation.tr("Held at %1%").arg(Battery.chargeLimit);
        if (isFull) return Translation.tr("Fully Charged");
        if (isCharging) return Translation.tr("Charging");
        if (isPluggedIn) return Translation.tr("Plugged In");
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
        if (!isPluggedIn && Battery.timeToEmpty > 0) {
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

        MaterialSymbol {
            id: boltIcon
            text: root.isCharging ? "bolt"
                : root.isFull ? "check_circle"
                : root.isPowerSaving ? "energy_savings_leaf"
                : root.isPerformance ? "local_fire_department"
                : "battery_full"
            fill: 1
            iconSize: 16
            color: root.accentColor
            Layout.alignment: Qt.AlignVCenter

            SequentialAnimation on opacity {
                running: root.isCharging && contractedLayout.visible
                // A value source keeps whatever opacity it stopped at, so the icon would stay faded
                onRunningChanged: if (!running) boltIcon.opacity = 1.0
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

}
