import QtQuick
import Qt5Compat.GraphicalEffects

// A picture cropped to a circle; `ready` once it has loaded, `failed` if it cannot.
Item {
    id: root
    property string source: ""
    readonly property bool ready: image.status === Image.Ready
    readonly property bool failed: image.status === Image.Error

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        // Fixed: sizing from the item would reload the picture on every resize.
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectCrop
        visible: false
        asynchronous: true
    }
    OpacityMask {
        anchors.fill: parent
        source: image
        visible: root.ready
        maskSource: Rectangle {
            width: image.width
            height: image.height
            radius: width / 2
        }
    }
}
