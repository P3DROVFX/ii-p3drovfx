import QtQuick

/**
 * A layer effect that fades its item's own alpha towards two opposite edges.
 *
 * Replaces an OpacityMask over a gradient Rectangle: that drew the gradient into a second
 * texture every time a stop moved (every scroll frame near an edge) and kept a Qt5Compat
 * ShaderEffectSource alive. The ramp is four stops, so the shader computes it per pixel.
 * Property names are the shader's uniforms.
 */
ShaderEffect {
    /// 0 fades along y (top → bottom), 1 along x (left → right).
    property real horizontal: 0
    /// Alpha at the start edge (top or left) and at the end edge (bottom or right).
    property real startAlpha: 1
    property real endAlpha: 0
    /// Normalised positions where the start ramp ends and the end ramp begins.
    property real startStop: 0
    property real endStop: 1

    fragmentShader: Qt.resolvedUrl("shaders/edgeFade.frag.qsb")
}
