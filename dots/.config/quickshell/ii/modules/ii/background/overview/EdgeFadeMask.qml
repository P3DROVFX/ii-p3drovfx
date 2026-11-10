import QtQuick

// Fades a layer's two ends along one axis, per pixel and continuously. Unlike a
// MultiEffect mask there is no threshold on a mask texture, so nothing cut at
// the clear end shows through as a hard edge or a band of different opacity.
// Positions are fractions of the item along the axis.
ShaderEffect {
    property var source
    property real startClear: 0
    property real startSolid: 0
    property real endSolid: 1
    property real endClear: 1
    property bool verticalAxis: true
    readonly property real vertical: verticalAxis ? 1 : 0
    fragmentShader: Qt.resolvedUrl("../shaders/edgeFadeMask.frag.qsb")
}
