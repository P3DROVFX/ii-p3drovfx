pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/utilButtons"

// Utility buttons chip on the shelf. Renders the same bar variant the bar uses
// for the configured utilButtons style; only the "default" one sits inside a
// shelf pill (expressive and segments paint their own surface). Buttons keep
// their native actions — no bar popup to replace here.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive" | "segments"
    property string style: "default"

    readonly property bool paddingless: root.style !== "default"
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: (buttonsHolder.item?.implicitWidth ?? 0) + (root.paddingless ? 0 : 14)
    implicitHeight: root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    ShelfPill {
        id: pill
        anchors.fill: parent
        visible: !root.paddingless
        hovered: buttonsHover.hovered
    }

    Loader {
        id: buttonsHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? buttonsExpressive
            : root.style === "segments" ? buttonsSegments
            : buttonsDefault
    }

    Component {
        id: buttonsDefault
        UtilButtons {
            vertical: false
        }
    }

    Component {
        id: buttonsExpressive
        ExpressiveUtilButtons {
            vertical: false
        }
    }

    Component {
        id: buttonsSegments
        SegmentedUtilButtons {
            vertical: false
        }
    }

    HoverHandler {
        id: buttonsHover
        cursorShape: Qt.PointingHandCursor
    }
}