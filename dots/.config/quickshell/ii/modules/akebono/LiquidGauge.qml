import qs.modules.common
import QtQuick
import Quickshell

ShaderEffect {
    id: root

    property real level: 0
    property color color: Appearance.colors.colPrimary
    property color bgColor: Appearance.colors.colLayer2
    property real radius: 12
    property real smoothing: AkebonoAppearance.squircleSmoothing
    property real waveAmp: 1.6
    property real wavePhase: 0
    property bool running: false
    property vector2d size: Qt.vector2d(width, height)

    fragmentShader: Quickshell.shellPath("assets/shaders/akebono/gauge.frag.qsb")

    Behavior on level {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }
    Behavior on color {
        ColorAnimation { duration: 350 }
    }

    NumberAnimation on wavePhase {
        running: root.running
        loops: Animation.Infinite
        from: 0
        to: 2 * Math.PI
        duration: 2600
    }
}
