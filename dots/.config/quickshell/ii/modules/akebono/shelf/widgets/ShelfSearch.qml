pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../ii/bar/widgets/search"

// Search chip on the shelf. Renders the bar search variant for the configured
// style; "default" sits inside a shelf pill, the expressive/neural variants
// paint their own capsule. The bar widget opens the search overview on press,
// so a top overlay reroutes the click to the shelf's desktop runner.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive" | "neural"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (searchHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 14)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: searchMouse.containsMouse
    }

    Loader {
        id: searchHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? searchExpressive
            : root.style === "neural" ? searchNeural
            : searchDefault
    }

    Component {
        id: searchDefault
        SearchBarWidget {
            vertical: false
        }
    }

    Component {
        id: searchExpressive
        ExpressiveSearchBarWidget {
            vertical: false
        }
    }

    Component {
        id: searchNeural
        NeuralSearchBarWidget {
            vertical: false
        }
    }

    MouseArea {
        id: searchMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.desktopRunnerOpen = !GlobalStates.desktopRunnerOpen
    }
}