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
    property var shelf

    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    readonly property bool shelfEmpty: !item?.active

    implicitWidth: root.shelfEmpty ? 0 : Math.max(item?.implicitWidth ?? root.pillHeight, root.pillHeight) + 6
    implicitHeight: root.pillHeight

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
        anchors.fill: parent
    }

    ModeIndicator {
        id: item
        anchors.centerIn: parent
        height: root.pillHeight
        disablePopup: true
        vertical: false
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        visible: !root.shelfEmpty
        onClicked: root.shelf?.toggleChipPopup(modePopoverComp, 344, root.modePopoverH, root)
    }

    readonly property real modePopoverH: {
        let h = 125 + 16 + 12 + 38;
        if (item?.active ?? false)
            h += 30 + 12;
        return h;
    }

    Component {
        id: modePopoverComp
        ShelfPopupSurface {
            ShelfModePanel {
                anchors.fill: parent
                shelf: root.shelf
            }
        }
    }
}