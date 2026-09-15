pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/dashboard"

// Quick settings chip on the shelf. Renders the exact same bar dashboard
// variant the bar uses for the configured dashboard style, so the shelf chip
// looks identical to the bar's notification button. There is deliberately no
// ShelfPill: every dashboard variant is paddingless in the bar and paints its
// own glyph. The bar button opens the right sidebar; on the shelf the chip
// must open quick settings instead, so a full-size overlay reroutes the press.
Item {
    id: root
    property real barHeight: 54
    property var shelf
    // "default" | "expressive" | "orbs"
    property string style: "default"

    readonly property bool paddingless: true
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)
    readonly property bool shelfEmpty: false

    implicitWidth: dashboardHolder.item?.implicitWidth ?? root.pillHeight
    implicitHeight: dashboardHolder.item?.implicitHeight ?? root.pillHeight
    Layout.alignment: Qt.AlignVCenter

    Loader {
        id: dashboardHolder
        anchors.centerIn: parent
        sourceComponent: root.style === "expressive" ? dashboardExpressive
            : root.style === "orbs" ? dashboardOrbs
            : dashboardDefault
    }

    Component {
        id: dashboardDefault
        DashboardPanelButton {
        }
    }

    Component {
        id: dashboardExpressive
        ExpressiveDashboardPanelButton {
            vertical: false
        }
    }

    Component {
        id: dashboardOrbs
        OrbsDashboardPanelButton {
            vertical: false
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 99
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.shelf?.toggleQuickSettings()
    }
}