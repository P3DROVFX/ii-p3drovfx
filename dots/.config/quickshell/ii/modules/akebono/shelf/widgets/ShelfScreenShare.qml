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

    readonly property real pillHeight: root.barHeight * 0.7
    readonly property bool shelfEmpty: !shareIndicator.activelyScreenSharing

    implicitWidth: root.shelfEmpty ? 0 : root.pillHeight
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
        id: pill
        anchors.fill: parent
    }

    ScreenShareIndicator {
        id: shareIndicator
        anchors.centerIn: parent
        width: root.pillHeight
        height: root.pillHeight
        disablePopup: true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        visible: !root.shelfEmpty
        onClicked: root.shelf?.toggleChipPopup(screenSharePopoverComp, 394, 170, root)
    }

    Component {
        id: screenSharePopoverComp
        ShelfScreenSharePanel {
            property var shelf: root.shelf
            anchors.fill: parent
        }
    }
}