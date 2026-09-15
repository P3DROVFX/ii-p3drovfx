pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import qs.modules.ii.bar.popups.bluetooth
import qs.services
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/bluetooth"

// Bluetooth chip on the shelf. Renders the bar variant for the configured
// bluetooth style; "default" sits inside a shelf pill, the expressive variant
// paints its own surface. Hides itself when no device is connected, matching
// the bar. Click still cycles the primary device, like the bar widget, and
// now also opens the device list in the shelf chipPopup slot (the bar popup
// stays disabled here).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: BluetoothStatus.connectedDevices.length < 1

    implicitWidth: (bluetoothHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 18)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Component.onCompleted: {
        if (root.shelf)
            root.shelf.registerChipAnchor(root);
    }
    onXChanged: if (root.shelf?.publishChip) root.shelf.publishChip()
    Component.onDestruction: {
        if (root.shelf)
            root.shelf.unregisterChipAnchor(root);
    }

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: btHover.hovered
    }

    Loader {
        id: bluetoothHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? btExpressive : btDefault
    }

    MouseArea {
        id: btClick
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.shelf)
                root.shelf.toggleChipPopup(btPopoverComp, 360, 460, root, Appearance.rounding.large);
            mouse.accepted = false;
        }
    }

    Component {
        id: btDefault
        BluetoothDevicesWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: btExpressive
        ExpressiveBluetoothDevices {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: btPopoverComp
        ShelfPopupSurface {
            ExpressiveBluetoothDevicesPopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
                active: root.shelf?.chipPopupOpen ?? false
                hoverTarget: root.bluetoothHolder.item
            }
        }
    }

    HoverHandler {
        id: btHover
        cursorShape: Qt.PointingHandCursor
    }
}