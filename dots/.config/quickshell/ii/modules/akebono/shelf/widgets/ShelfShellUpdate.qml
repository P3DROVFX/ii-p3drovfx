pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/indicators"

Item {
    id: root
    property real barHeight: 54
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    readonly property bool shelfEmpty: !item?.available

    implicitWidth: root.shelfEmpty ? 0 : root.pillHeight * 1.4
    implicitHeight: root.pillHeight

    ShelfPill {
        anchors.fill: parent
    }

    ShellUpdateIndicator {
        id: item
        anchors.centerIn: parent
        width: root.pillHeight
        height: root.pillHeight
        vertical: false
    }
}