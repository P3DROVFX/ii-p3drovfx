import QtQuick
import qs.modules.common
import qs.modules.common.functions

Item { // Lightweight visualizer bar: direct height application
    id: root

    property real amplitude: 0.0 // 0.0 to 1.0
    property real bgAmplitude: 0.0 // 0.0 to 1.0
    property real barWidth: 10
    property real maxHeight: 40
    property real minHeight: 8
    property color color: Appearance.colors.colPrimary
    property color fgColor: Appearance.colors.colTertiary
    property color glowColor: "#FFFFFF"
    property bool playing: true

    implicitWidth: barWidth
    implicitHeight: maxHeight

    // Heights are applied directly from the sample, not retargeted through
    // Behaviors: Cava pushes ~30 samples/s and every instance of this bar
    // used to run two NumberAnimations per bar (eight across Neural Media's
    // four + the notch's four), each restarted ~60x/s — the steady-state CPU
    // the 2026-09-10 pass traced to the visualizer while media played. The
    // Dock Media widget already samples straight into `height` with no
    // animation and looks identical, because 30 Hz *is* the animation; an
    // extra 90 ms tween per sample only adds retarget churn.
    readonly property real targetHeight: minHeight + amplitude * (maxHeight - minHeight)
    readonly property real bgTargetHeight: minHeight + bgAmplitude * (maxHeight - minHeight)

    // 1. Background Capsule (Translucent)
    Rectangle {
        id: bgCapsule
        width: root.barWidth * 1.4
        height: Math.min(root.maxHeight * 1.2, root.bgTargetHeight * 1.2 + 4)
        radius: width / 2
        anchors.centerIn: parent
        opacity: 0.25 + root.bgAmplitude * 0.2
        color: root.color
        layer.enabled: false
    }

    // 2. Foreground Capsule (Solid bright fill)
    Rectangle {
        id: fgCapsule
        width: root.barWidth
        height: root.targetHeight
        radius: width / 2
        anchors.centerIn: parent
        color: root.fgColor
        layer.enabled: false
    }
}
