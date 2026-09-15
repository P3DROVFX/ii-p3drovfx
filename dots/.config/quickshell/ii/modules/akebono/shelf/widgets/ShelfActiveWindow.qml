pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import qs.modules.ii.bar.popups.activeWindow
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/activeWindow"

// Active window chip on the shelf. Renders the bar variant for the configured
// activeWindow style; "default" sits inside a shelf pill, the expressive
// variant draws its own outline capsule. Click opens the window details in the
// shelf chipPopup slot (the bar popup stays disabled here). The press-based
// bar popup has no click action of its own, so a transparent click area opens
// the chip popup without stealing the widget's hover styling.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    readonly property string popAppClass: winHolder.item?.appClassText ?? ""
    readonly property string popAppTitle: winHolder.item?.appTitleText ?? ""
    readonly property string popAddress: winHolder.item?.activeWindowAddress ?? ""
    readonly property var popMonitor: winHolder.item?.monitor ?? null
    readonly property int popWidth: winHolder.item?.popupWidth ?? 350
    readonly property int popMaxWidth: winHolder.item?.maxPopupWidth ?? 600

    implicitWidth: (winHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 20)
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
        hovered: winHover.hovered
    }

    Loader {
        id: winHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? winExpressive : winDefault
    }

    Component {
        id: winDefault
        ActiveWindow {
            vertical: false
            disablePopup: true
            width: Math.min(implicitWidth, Math.max(root.barHeight * 1.6, 160))
        }
    }

    Component {
        id: winExpressive
        ExpressiveActiveWindow {
            vertical: false
            disablePopup: true
        }
    }

    MouseArea {
        id: winClick
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (root.shelf)
                root.shelf.toggleChipPopup(winPopoverComp, 350, 300, root);
        }
    }

    Component {
        id: winPopoverComp
        ShelfPopupSurface {
            ActiveWindowPopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
                appClassText: root.popAppClass
                appTitleText: root.popAppTitle
                activeWindowAddress: root.popAddress
                monitor: root.popMonitor
                popupWidth: root.popWidth
                maxPopupWidth: root.popMaxWidth
            }
        }
    }

    HoverHandler {
        id: winHover
        cursorShape: Qt.PointingHandCursor
    }
}