import QtQuick
import qs.modules.common
import qs.modules.common.functions

// A glowing ring with its spectrum growing outward, the inverse of
// RadialWaveVisualizer (see shaders/circleSpectrum.frag). Size it as a square; the
// ring, spikes and glow all fit inside.
SpectrumShaderEffect {
    id: root

    property color coreColor: "white"
    property color colorA: ColorUtils.colorWithLightness(Appearance.m3colors.m3primary, 0.7)
    property color colorB: ColorUtils.colorWithLightness(Appearance.m3colors.m3tertiary, 0.7)
    readonly property real _unit: Math.min(width, height) / 2
    property real ringRadius: _unit * 0.5
    property real lineWidth: Math.max(1.5, _unit * 0.012)
    property real spikeHeight: _unit * 0.36
    property real glowRadius: _unit * 0.04
    property real spread: Math.max(1, _unit * 0.014)
    property real intensity: 1

    fragmentShader: Qt.resolvedUrl("shaders/circleSpectrum.frag.qsb")
}
