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

    readonly property bool shelfEmpty: !item?.shown

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
        anchors.fill: parent
    }

    DictationIndicator {
        id: item
        anchors.centerIn: parent
        width: root.pillHeight
        height: root.pillHeight
        disablePopup: true
        vertical: false
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        visible: !root.shelfEmpty
        onClicked: root.shelf?.toggleChipPopup(dictationPopoverComp, 384, 247, root)
    }

    Component {
        id: dictationPopoverComp
        ShelfDictationPanel {
            property var shelf: root.shelf
            anchors.fill: parent
        }
    }
}