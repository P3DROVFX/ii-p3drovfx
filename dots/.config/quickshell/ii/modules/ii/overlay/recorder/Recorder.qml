pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    minimumWidth: recorderContent.implicitWidth
    minimumHeight: recorderContent.implicitHeight

    contentItem: RecorderContent {
        id: recorderContent
        radius: root.contentRadius
    }
}
