pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common.widgets
import "../../../ii/bar/widgets/visualizer"

Item {
    id: root
    property real barHeight: 54
    readonly property real pillHeight: root.barHeight * 0.7
    readonly property bool shelfEmpty: !root.playing

    readonly property bool playing: vis.isPlaying

    implicitWidth: root.pillHeight * 2.2
    implicitHeight: root.pillHeight

    Visualizer {
        id: vis
        anchors.centerIn: parent
        barCount: Math.round(root.barHeight * 0.24)
        dotSize: 3
        dotSpacing: 3
        width: implicitWidth
        height: root.pillHeight
    }
}