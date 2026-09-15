import qs.modules.common
import QtQuick
import Quickshell

ShaderEffect {
    id: root

    property color color: "#000000"
    property real radius: 24
    property real radiusTop: radius
    property real radiusBottom: radius
    property real smoothing: AkebonoAppearance.squircleSmoothing
    property real inset: 0
    property vector2d size: Qt.vector2d(width, height)

    property real waves: 20
    property real speed: 12
    property real depth: 4
    property int beats: 2
    property int buzzDuration: 900

    property real progress: 0
    readonly property real phase: progress * speed
    readonly property real amp: depth * Math.pow(Math.sin(progress * Math.PI * beats), 2)

    fragmentShader: Quickshell.shellPath("assets/shaders/akebono/edgewave.frag.qsb")

    function buzz(): void {
        buzzAnim.restart();
    }

    NumberAnimation {
        id: buzzAnim
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.buzzDuration
    }
}
