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


    readonly property bool isCharging: Battery.isCharging
    readonly property bool isFull: Battery.isFullyCharged || Battery.chargeLimitReached
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property bool isPowerSaving: PowerProfiles.profile === PowerProfile.PowerSaver
    readonly property bool isPerformance: PowerProfiles.profile === PowerProfile.Performance


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
    // Status text at one edge, the user's own bar battery glyph at the other,
    // with the island's full width of air between them.

    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 14
        spacing: 16

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.statusText
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSurface
        }

        // The wide gap: pushes the glyph to the right edge.
        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
        }

        // The bar's own BatteryIndicator, same component and same user style
        // (android16/oneui/legacy/material), popup off.
        Loader {
            id: barBatteryIcon
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumHeight: contractedLayout.height
            source: Qt.resolvedUrl("../../bar/widgets/battery/BatteryIndicator.qml")

            Binding {
                target: barBatteryIcon.item
                property: "disablePopup"
                value: true
            }
            Binding {
                target: barBatteryIcon.item
                property: "colText"
                value: Appearance.colors.colOnSurface
            }
        }
    }

}
