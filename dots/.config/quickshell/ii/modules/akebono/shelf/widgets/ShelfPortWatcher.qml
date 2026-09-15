pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import qs.modules.ii.bar.popups.portWatcher
import qs.services
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/portWatcher"

// Port watcher chip on the shelf. Renders the same bar variant the bar uses
// for the configured portWatcher style; "default" sits inside a shelf pill,
// the expressive variant paints its own surface. Click rescans ports, exactly
// like the bar widget, and also opens the port list in the shelf chipPopup
// slot (the bar popup stays disabled here).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: !PortWatcher.enabled

    implicitWidth: (watcherHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 18)
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
        hovered: watcherHover.hovered
    }

    Loader {
        id: watcherHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? watcherExpressive : watcherDefault
    }

    MouseArea {
        id: watcherClick
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.shelf)
                root.shelf.toggleChipPopup(watcherPopoverComp, 384, 560, root);
            mouse.accepted = false;
        }
    }

    Component {
        id: watcherDefault
        PortWatcherWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: watcherExpressive
        ExpressivePortWatcher {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: watcherPopoverComp
        ShelfPopupSurface {
            PortWatcherPopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
            }
        }
    }

    HoverHandler {
        id: watcherHover
        cursorShape: Qt.PointingHandCursor
    }
}