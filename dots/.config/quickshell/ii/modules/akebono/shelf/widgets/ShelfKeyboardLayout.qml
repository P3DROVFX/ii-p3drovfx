pragma ComponentBehavior: Bound
import qs.modules.akebono
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.keyboard
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../../ii/bar/widgets/keyboard"

// Keyboard layout chip on the shelf. Renders the same bar variant the bar uses
// for the configured keyboard style; "default" sits inside a shelf pill, the
// expressive variant draws its own outline. Click switches the layout, exactly
// like the bar widget, and also opens the layout list in the shelf chipPopup
// slot (the bar popup stays disabled here).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: HyprlandXkb.layoutCodes.length < 1

    implicitWidth: (kbHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 14)
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
        hovered: kbHover.hovered
    }

    Loader {
        id: kbHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? kbExpressive : kbDefault
    }

    MouseArea {
        id: kbClick
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.shelf)
                root.shelf.toggleChipPopup(kbPopoverComp, 400, 140, root);
            mouse.accepted = false;
        }
    }

    Component {
        id: kbDefault
        KeyboardLayoutWidget {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: kbExpressive
        ExpressiveKeyboardLayout {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: kbPopoverComp
        ShelfPopupSurface {
            KeyboardLayoutPopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
            }
        }
    }

    HoverHandler {
        id: kbHover
        cursorShape: Qt.PointingHandCursor
    }
}