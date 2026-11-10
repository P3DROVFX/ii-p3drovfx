import QtQuick
import qs.modules.common
import qs.modules.common.functions

// A glowing spectrum around the edges of the item, meant to fill the screen
// (see shaders/haloVisualizer.frag).
SpectrumShaderEffect {
    id: root

    property color coreColor: "white"
    property color colorA: ColorUtils.colorWithLightness(Appearance.m3colors.m3primary, 0.7)
    property color colorB: ColorUtils.colorWithLightness(Appearance.m3colors.m3tertiary, 0.7)
    property real radius: Appearance.rounding.screenRounding
    readonly property real _unit: Math.min(width, height)
    property real baseWidth: Math.max(1.5, _unit * 0.002)
    property real thickness: _unit * 0.03
    property real glowRadius: _unit * 0.024
    property real spread: Math.max(1, _unit * 0.003)
    property real intensity: 1

    fragmentShader: Qt.resolvedUrl("shaders/haloVisualizer.frag.qsb")
}
