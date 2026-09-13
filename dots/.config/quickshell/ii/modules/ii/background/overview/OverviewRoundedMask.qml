import QtQuick

// Rounded clipping needs only the radius and the source texture. Rasterizing
// a screen-sized Rectangle mask on every radius change doubles the bandwidth.
ShaderEffect {
    property var source
    property real cornerRadius: 0
    readonly property vector2d screenExtent: Qt.vector2d(width, height)
    fragmentShader: Qt.resolvedUrl("../shaders/overviewRoundedMask.frag.qsb")
}
