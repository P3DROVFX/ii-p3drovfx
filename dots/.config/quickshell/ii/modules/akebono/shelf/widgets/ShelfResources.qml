pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/resources"

// Resources chip on the shelf. Renders the same bar variant the bar uses for
// the configured resources style: the "default" one is a capsule of compact
// resource rows inside a shelf pill, the expressive one is the bar's set of
// coloured resource shapes on its own surface. The bar popups stay disabled —
// the click opens the shelf's own resources popup, which anchors to this chip.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (resHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 20)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Item {
        id: anchor
        anchors.fill: parent

        Component.onCompleted: root.shelf.registerResourcesAnchor(anchor)
        Component.onDestruction: root.shelf.unregisterResourcesAnchor(anchor)
        onXChanged: root.shelf.publishResources()
    }

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: resMouse.containsMouse || (root.shelf?.resourcesOpen ?? false)
    }

    Loader {
        id: resHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? resExpressive : resDefault
    }

    Component {
        id: resDefault
        Resources {
            vertical: false
            disablePopup: true
        }
    }

    Component {
        id: resExpressive
        ExpressiveResources {
            vertical: false
            disablePopup: true
        }
    }

    MouseArea {
        id: resMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.shelf.toggleResources()
    }
}