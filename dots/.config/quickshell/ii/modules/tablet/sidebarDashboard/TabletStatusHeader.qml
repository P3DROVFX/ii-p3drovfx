import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The single status line across the top of the shade: clock and date on the left, the
 * same glanceable state the bar shows on the right. Purely informational — nothing here
 * toggles anything or opens a popup, exactly like a phone's status bar inside the shade.
 */
Item {
    id: root

    property real barHeight: 56

    implicitHeight: root.barHeight

    readonly property real iconSize: Math.round(root.barHeight * 0.42)
    readonly property real iconSpacing: Math.round(root.barHeight * 0.28)
    readonly property color colStatus: Appearance.colors.colOnLayer0

    // ── Clock ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
        }
        spacing: Math.round(root.barHeight * 0.24)

        StyledText {
            text: DateTime.time
            color: root.colStatus
            font.pixelSize: Math.round(Appearance.font.pixelSize.huge * 1.25)
            font.family: Appearance.font.family.title
            font.weight: 700
        }

        StyledText {
            text: DateTime.collapsedCalendarFormat
            color: Appearance.colors.colSubtext
            font.pixelSize: Math.round(Appearance.font.pixelSize.large * 1.1)
            font.weight: 500
        }
    }

    // ── Status indicators ───────────────────────────────────────────────────
    RowLayout {
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        spacing: root.iconSpacing

        StatusIcon {
            visible: Idle.inhibit ?? false
            text: "coffee"
        }

        StatusIcon {
            visible: Notifications.silent
            text: "notifications_off"
        }

        StatusIcon {
            visible: Audio.source?.audio?.muted ?? false
            text: "mic_off"
        }

        StatusIcon {
            visible: Audio.sink?.audio?.muted ?? false
            text: "volume_off"
        }

        StyledText {
            visible: HyprlandXkb.layoutCodes.length > 0
            text: {
                const code = HyprlandXkb.currentLayoutCode ?? "";
                const base = code.split('-')[0].slice(0, 2);
                return Config.options.bar.keyboardLayout.uppercaseLayout ? base.toUpperCase() : base.toLowerCase();
            }
            color: root.colStatus
            font.pixelSize: Math.round(root.iconSize * 0.82)
            font.weight: 600
        }

        StatusIcon {
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
        }

        StatusIcon {
            text: Network.materialSymbol
        }

        Android16Battery {
            visible: Battery.available
            Layout.preferredHeight: Math.round(root.iconSize * 0.92)
            Layout.preferredWidth: implicitWidth
            Layout.alignment: Qt.AlignVCenter
            batteryLevel: Math.round(Battery.percentage * 100)
            isCharging: Battery.isCharging || Battery.isPluggedIn
            isPowerSaving: false
            // The level is drawn inside the pill, so the filled half has to invert against it.
            colorFillNormal: root.colStatus
            colorTextEmpty: root.colStatus
            colorTextFilled: Appearance.colors.colLayer0
            textWeightEmpty: Font.DemiBold
            textWeightFilled: Font.DemiBold
        }
    }

    component StatusIcon: MaterialSymbol {
        Layout.alignment: Qt.AlignVCenter
        iconSize: root.iconSize
        color: root.colStatus
    }
}
