pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ColumnLayout {
    id: root

    required property BluetoothDevice device

    readonly property string deviceName: {
        const name = root.device?.name ?? "";
        if (name.length > 0)
            return name;
        return root.device?.deviceName ?? root.device?.address ?? "";
    }
    readonly property bool isConnected: root.device?.connected ?? false
    readonly property bool isPaired: root.device?.paired ?? false
    readonly property bool isPairing: root.device?.pairing ?? false

    function primaryAction(): void {
        if (!root.device)
            return;
        if (root.isPairing) {
            root.device.cancelPair();
            return;
        }
        if (!root.isPaired) {
            root.device.pair();
            return;
        }
        if (root.isConnected)
            root.device.disconnect();
        else
            root.device.connect();
    }

    Layout.fillWidth: true
    spacing: 8

    MaterialTextField {
        id: renameField
        Layout.fillWidth: true
        visible: root.isPaired
        placeholderText: Translation.tr("Name shown for this device")
        text: root.deviceName
        onAccepted: {
            if (root.device && renameField.text.length > 0)
                root.device.name = renameField.text;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        RippleButtonWithIcon {
            materialIcon: root.isPairing ? "close"
                : !root.isPaired ? "add_link"
                : root.isConnected ? "link_off" : "link"
            mainText: root.isPairing ? Translation.tr("Cancel")
                : !root.isPaired ? Translation.tr("Pair")
                : root.isConnected ? Translation.tr("Disconnect") : Translation.tr("Connect")
            colBackground: root.isConnected || root.isPairing ? Appearance.colors.colLayer2Hover
                : Appearance.colors.colPrimary
            colText: root.isConnected || root.isPairing ? Appearance.colors.colOnLayer1
                : Appearance.colors.colOnPrimary
            onClicked: root.primaryAction()
        }

        RippleButtonWithIcon {
            visible: root.isPaired && !root.isPairing
            materialIcon: "delete"
            mainText: Translation.tr("Forget")
            onClicked: root.device?.forget()
        }

        Item {
            Layout.fillWidth: true
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.isPaired
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Trusted")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("Reconnects on its own and stops asking for permission.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledSwitch {
            checked: root.device?.trusted ?? false
            onToggled: {
                if (root.device)
                    root.device.trusted = checked;
                checked = Qt.binding(() => root.device?.trusted ?? false);
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                text: Translation.tr("Blocked")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: Translation.tr("Refuses every connection from this device until it is unblocked.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        StyledSwitch {
            checked: root.device?.blocked ?? false
            onToggled: {
                if (root.device)
                    root.device.blocked = checked;
                checked = Qt.binding(() => root.device?.blocked ?? false);
            }
        }
    }
}
