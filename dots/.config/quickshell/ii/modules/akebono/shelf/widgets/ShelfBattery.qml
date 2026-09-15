pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import qs.modules.ii.bar.popups.battery
import qs.services
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/battery"

// Battery chip on the shelf. Renders the bar battery variant for the
// configured style; "default" sits inside a shelf pill, the expressive variant
// paints its own pill. vertical must be false on the shelf: the bar
// BatteryIndicator keeps its horizontal content Loader inactive otherwise and
// reports a NaN implicit width, which collapses the chip. Click opens the
// battery details in the shelf chipPopup slot (the bar popup stays disabled).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: !Battery.available

    implicitWidth: (batteryHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 16)
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
        hovered: batteryHover.hovered
    }

Loader {
        id: batteryHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? batteryExpressive : batteryDefault
    }

    MouseArea {
        id: batteryClick
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.shelf)
                root.shelf.toggleChipPopup(batteryPopoverComp, 380, 430, root);
            mouse.accepted = false;
        }
    }

    Component {
        id: batteryDefault
        BatteryIndicator {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: batteryExpressive
        ExpressiveBattery {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: batteryPopoverComp
        ShelfPopupSurface {
            BatteryPopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
            }
        }
    }

    HoverHandler {
        id: batteryHover
        cursorShape: Qt.PointingHandCursor
    }
}