pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import qs.modules.ii.bar.popups.sports
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/sports"

// Sports chip on the shelf. Renders the bar variant for the configured sports
// style; "default" sits inside a shelf pill, the expressive variant paints its
// own surface. Hidden unless there is a game on, matching the bar. Click
// advances to the next game, exactly like the bar widget, and also opens the
// game list in the shelf chipPopup slot (its bar popup stays disabled here).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: !(sportsHolder.item?.shouldBeVisible ?? true)

    implicitWidth: (sportsHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 20)
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
        hovered: sportsHover.hovered
    }

    Loader {
        id: sportsHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? sportsExpressive : sportsDefault
    }

    MouseArea {
        id: sportsClick
        anchors.fill: parent
        propagateComposedEvents: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (root.shelf)
                root.shelf.toggleChipPopup(sportsPopoverComp, 485, 300, root, Appearance.rounding.verylarge);
            mouse.accepted = false;
        }
    }

    Component {
        id: sportsDefault
        Sports {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: sportsExpressive
        ExpressiveSports {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: sportsPopoverComp
        ShelfPopupSurface {
            radius: Appearance.rounding.verylarge
            SportsPopupContent {
                anchors.fill: parent
                opened: root.shelf?.chipPopupOpen ?? false
                popupOpenProgress: root.shelf?.chipPopupProgress ?? 0
            }
        }
    }

    HoverHandler {
        id: sportsHover
        cursorShape: Qt.PointingHandCursor
    }
}