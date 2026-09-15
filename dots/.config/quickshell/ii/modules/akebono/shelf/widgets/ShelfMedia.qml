pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/widgets/media"

Item {
    id: root
    property real barHeight: 54
    property var shelf
    property string style: "default"

    readonly property bool shelfEmpty: !mediaHolder.item?.hasTrack
    readonly property real pillHeight: Math.max(root.barHeight * 0.7, Appearance.sizes.baseBarHeight)

    implicitWidth: root.shelfEmpty ? 0 : (mediaHolder.item?.implicitWidth ?? 0) + 16
    implicitHeight: root.pillHeight

    Component.onCompleted: {
        if (root.shelf)
            root.shelf.registerMediaAnchor(root);
        if (root.shelf)
            root.shelf.publishMedia();
    }
    onXChanged: if (root.shelf?.publishMedia) root.shelf.publishMedia()
    Component.onDestruction: {
        if (root.shelf && root.shelf.mediaAnchor === root)
            root.shelf.unregisterMediaAnchor(root);
    }

    ShelfPill {
        anchors.fill: parent
        visible: !(mediaHolder.item?.isMaterial ?? false)
    }

    Loader {
        id: mediaHolder
        anchors.centerIn: parent
        height: root.pillHeight
        sourceComponent: root.style === "expressive" ? expressiveComp
            : root.style === "neural" ? neuralComp
            : root.style === "ring" ? ringComp
            : root.style === "tonal" ? tonalComp
            : defaultComp
    }

    Component {
        id: defaultComp
        Media {
            disablePopup: true
        }
    }

    Component {
        id: expressiveComp
        ExpressiveMedia {
            disablePopup: true
        }
    }

    Component {
        id: neuralComp
        NeuralMedia {
            disablePopup: true
        }
    }

    Component {
        id: ringComp
        RingMedia {
            previewMode: true
        }
    }

    Component {
        id: tonalComp
        TonalMedia {
            previewMode: true
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        visible: !root.shelfEmpty
        onClicked: {
            if (!root.shelf)
                return;
            root.shelf.mediaOpen = !root.shelf.mediaOpen;
            root.shelf.publishMedia();
        }
    }
}