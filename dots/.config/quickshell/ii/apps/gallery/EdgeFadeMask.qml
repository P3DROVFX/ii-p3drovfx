import QtQuick

// Linear per-pixel edge fade shader matching the shell's CoverMediaWidget / transparent bar blur.
ShaderEffect {
    property var source
    property real startClear: 0
    property real startSolid: 0
    property real endSolid: 1
    property real endClear: 1
    property bool verticalAxis: true
    readonly property real vertical: verticalAxis ? 1 : 0
    fragmentShader: Qt.resolvedUrl("edgeFadeMask.frag.qsb")
}
