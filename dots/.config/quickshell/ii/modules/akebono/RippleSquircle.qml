import QtQuick
import Quickshell

ShaderEffect {
    id: root

    property color color: "#000000"
    property real radius: 24
    property real radiusTop: radius
    property real radiusBottom: radius
    property real smoothing: 4.0
    property real inset: 6
    property vector2d size: Qt.vector2d(width, height)
    property vector2d rippleOrigin: Qt.vector2d(width / 2, height)
    property real rippleProgress: 1
    property real rippleAmp: 8.0

    fragmentShader: Quickshell.shellPath("assets/shaders/akebono/runner.frag.qsb")

    function ripple(): void {
        rippleAnim.restart();
    }

    NumberAnimation {
        id: rippleAnim
        target: root
        property: "rippleProgress"
        from: 0
        to: 1
        duration: 650
    }
}
