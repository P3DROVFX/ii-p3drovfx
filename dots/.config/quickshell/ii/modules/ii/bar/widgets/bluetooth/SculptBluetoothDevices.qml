pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Sculpt Bluetooth devices — three Material 3 Expressive takes on "a device and
 * its battery", chosen in the widget's page (`bar.bluetooth.sculptVariant`):
 *
 *   card    a pass from a wallet app: the device's name set huge and cropped
 *           behind, a scalloped seal with the glyph, the battery in front
 *   ring    the battery as a wavy progress ring around the glyph, and the
 *           percentage in tall condensed digits whose weight follows the charge
 *   badge   the number inside a scalloped cookie that changes shape with the
 *           charge, the glyph on a small disc overlapping it, the name beside
 *
 * This file owns the data, the click and the popup; each variant only draws.
 */
MouseArea {
    id: root

    property bool vertical: false

    // Plain rather than readonly so a preview can hand in devices.
    property var activeDevices: BluetoothStatus.connectedDevices
    property int deviceIndex: 0
    readonly property int deviceCount: root.activeDevices.length
    readonly property var device: root.deviceCount > 0
        ? root.activeDevices[root.deviceIndex % root.deviceCount]
        : null
    readonly property bool hasDevices: root.deviceCount > 0
    readonly property bool hasBattery: root.device?.batteryAvailable ?? false
    readonly property real battery: Math.max(0, Math.min(1, root.device?.battery ?? 0))
    readonly property bool low: root.hasBattery && root.battery <= 0.15
    readonly property string deviceName: root.device?.name ?? ""
    readonly property string glyph: Icons.getBluetoothDeviceMaterialSymbol(root.device?.icon ?? "")

    readonly property string variant: Config.options.bar.bluetooth.sculptVariant ?? "ring"
    readonly property bool showName: Config.options.bar.bluetooth.sculptShowName ?? true

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    BarWidgetPalette {
        id: familyPalette
        colorMode: Config.options.bar.bluetooth.colorMode
    }
    BarWidgetPalette {
        id: alertPalette
        colorMode: "alert"
    }

    implicitWidth: !root.hasDevices ? 0 : root.vertical
        ? Appearance.sizes.verticalBarWidth
        : (variantLoader.item?.implicitWidth ?? 0)
    implicitHeight: !root.hasDevices ? 0 : root.vertical
        ? (variantLoader.item?.implicitHeight ?? 0)
        : Appearance.sizes.baseBarHeight
    visible: root.hasDevices
    hoverEnabled: !BarInteraction.clickToShow
    cursorShape: Qt.PointingHandCursor

    // Click-to-show gives the left click to the popup; cycling moves to the right button.
    readonly property bool rightClickCycles: BarInteraction.cycleOnRightClick
    acceptedButtons: root.rightClickCycles ? (Qt.LeftButton | Qt.RightButton) : Qt.LeftButton

    function syncVisible(): void {
        if (typeof rootItem !== "undefined" && typeof rootItem.toggleVisible === "function")
            rootItem.toggleVisible(BluetoothStatus.connectedDevices.length > 0);
    }

    onHasDevicesChanged: root.syncVisible()
    Component.onCompleted: root.syncVisible()

    onClicked: mouse => {
        if (mouse.button !== (root.rightClickCycles ? Qt.RightButton : Qt.LeftButton))
            return;
        if (root.deviceCount > 1)
            root.deviceIndex = (root.deviceIndex + 1) % root.deviceCount;
    }

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        active: root.hasDevices
        sourceComponent: root.variant === "card"
            ? cardVariant
            : root.variant === "badge" ? badgeVariant : ringVariant
    }

    Component {
        id: cardVariant
        SculptBluetoothCard {
            vertical: root.vertical
            thickness: root.thickness
            hovered: root.containsMouse
            tones: root.low ? alertPalette : familyPalette
            deviceName: root.deviceName
            glyph: root.glyph
            hasBattery: root.hasBattery
            battery: root.battery
            showName: root.showName
            deviceCount: root.deviceCount
            deviceIndex: root.deviceIndex % Math.max(1, root.deviceCount)
        }
    }

    Component {
        id: ringVariant
        SculptBluetoothRing {
            vertical: root.vertical
            thickness: root.thickness
            hovered: root.containsMouse
            tones: familyPalette
            low: root.low
            deviceName: root.deviceName
            glyph: root.glyph
            hasBattery: root.hasBattery
            battery: root.battery
            deviceCount: root.deviceCount
        }
    }

    Component {
        id: badgeVariant
        SculptBluetoothBadge {
            vertical: root.vertical
            thickness: root.thickness
            hovered: root.containsMouse
            tones: root.low ? alertPalette : familyPalette
            low: root.low
            deviceName: root.deviceName
            glyph: root.glyph
            hasBattery: root.hasBattery
            battery: root.battery
            showName: root.showName
            deviceCount: root.deviceCount
        }
    }

    // Lazy: popup controller is only built on approach (same as ExpressiveSports).
    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held)
        source: Config.options.bar.bluetoothDevicesLayout === "expressive"
            ? "../../popups/bluetooth/ExpressiveBluetoothDevicesPopup.qml"
            : "../../popups/bluetooth/BluetoothDevicesPopup.qml"
        onLoaded: item.hoverTarget = root
    }
}
