pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/policies"

// Policies chip on the shelf. Renders the same bar policies variant the bar
// uses for the configured policies style; all variants are paddingless, so
// there is no ShelfPill. The bar button toggles the left policies sidebar and
// the chip keeps that exact behavior (native press).
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive" | "outline"
    property string style: "default"

    readonly property bool paddingless: true
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: policiesHolder.item?.implicitWidth ?? root.pillHeight
    implicitHeight: policiesHolder.item?.implicitHeight ?? root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Loader {
        id: policiesHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? policiesExpressive
            : root.style === "outline" ? policiesOutline
            : policiesDefault
    }

    Component {
        id: policiesDefault
        PoliciesPanelButton {
        }
    }

    Component {
        id: policiesExpressive
        ExpressivePoliciesPanelButton {
            vertical: false
        }
    }

    Component {
        id: policiesOutline
        OutlinePoliciesPanelButton {
            vertical: false
        }
    }
}