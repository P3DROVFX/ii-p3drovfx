import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A club crest on a round plate. Crests are drawn for white backgrounds, so the
// plate is the brightest surface in the ladder rather than the pane colour.
Rectangle {
    id: root

    property string source: ""
    property real size: 40
    property color plate: FootballStyle.colField

    implicitWidth: root.size
    implicitHeight: root.size
    radius: root.size / 2
    color: root.plate

    StyledImage {
        anchors.centerIn: parent
        width: Math.round(root.size * 0.66)
        height: width
        source: root.source
        fillMode: Image.PreserveAspectFit
        mipmap: true
        smooth: true
        cache: true
        visible: root.source !== ""
    }

    MaterialSymbol {
        anchors.centerIn: parent
        visible: root.source === ""
        text: "shield"
        iconSize: Math.round(root.size * 0.5)
        color: FootballStyle.colOnSurfaceVariant
    }
}
