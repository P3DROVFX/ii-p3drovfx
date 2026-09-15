pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

// Card surface for shelf chip popups (battery, sports, port watcher, ...). The
// bar hosts the same popup bodies inside its StyledPopup window, which paints
// the rounded surface and padding around them. The shelf hosts only the body
// in its in-window chipPopup slot. Attached (popupsDetached off) the swell the
// shelf shader draws around the chip IS the surface, so no card is painted here
// and the popup reads as one piece extending out of the shelf, like the
// weather/resources popups. Detached the chip floats above the shelf with a
// gap and needs the card (mirrors StyledPopup.qml's popupBackground:
// m3surfaceContainer, or colLayer0 with transparency on, large rounding, an
// optional hairline border). Either way the fixed inner padding keeps content
// clear of the rounded swell corners.
Item {
    id: root

    property real pad: 10
    property int radius: Appearance.rounding.large
    readonly property bool detached: Config.options.akebono.shelf.popupsDetached
    default property alias content: slot.data

    readonly property Item firstItem: slot.children.length > 0 ? slot.children[0] : null

    implicitWidth: (root.firstItem?.implicitWidth ?? 0) + root.pad * 2
    implicitHeight: (root.firstItem?.implicitHeight ?? 0) + root.pad * 2

    Rectangle {
        id: bg
        anchors.fill: parent
        visible: root.detached
radius: root.radius
        color: Config.options.appearance.transparency.popups
            ? Appearance.colors.colLayer0
            : Appearance.m3colors.m3surfaceContainer
        border.width: Config.options.appearance.transparency.popups ? 0 : 1
        border.color: Appearance.colors.colLayer0Border
    }

    Item {
        id: slot
        anchors.fill: parent
        anchors.margins: root.pad
    }
}