import QtQuick
import Quickshell

ShaderEffect {
    property color color: "#000000"
    property real radius: 24
    property real smoothing: 4.0
    property vector2d size: Qt.vector2d(width, height)

    fragmentShader: Quickshell.shellPath("assets/shaders/akebono/squircle.frag.qsb")
}
