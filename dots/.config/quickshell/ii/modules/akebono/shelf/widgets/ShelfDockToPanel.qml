pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/dockToPanel"

Item {
    id: root
    property real barHeight: 54
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    readonly property bool shelfEmpty: false

    implicitWidth: Math.max(item.implicitWidth, root.pillHeight)
    implicitHeight: root.pillHeight

    ShelfPill {
        anchors.fill: parent
    }

    DockToPanel {
        id: item
        anchors.centerIn: parent
        height: root.pillHeight
        disablePopup: true
        vertical: false
    }
}