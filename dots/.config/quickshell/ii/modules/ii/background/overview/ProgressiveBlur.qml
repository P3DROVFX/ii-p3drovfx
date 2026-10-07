import QtQuick

// A blur that grows along one axis, per pixel, in a single pass - for a layer
// that has to melt into the edge of its card (the big battery figure of the
// Bluetooth widgets). Use as `layer.effect`; give the layered item room around
// its content, since taps past the texture's edge only see clamped pixels.
// Positions are fractions of the item along the axis; radii are logical pixels.
ShaderEffect {
    property var source
    property real blurStart: 0.5
    property real blurEnd: 1
    property real maxRadius: 16
    property real endOpacity: 1
    property bool verticalAxis: true
    property bool towardStart: false
    readonly property real itemWidth: width
    readonly property real itemHeight: height
    readonly property real vertical: verticalAxis ? 1 : 0
    readonly property real reversed: towardStart ? 1 : 0
    fragmentShader: Qt.resolvedUrl("../shaders/progressiveBlur.frag.qsb")
}
