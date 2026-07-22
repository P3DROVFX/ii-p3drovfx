import QtQuick
import qs.modules.common
import qs.modules.common.functions

Item { // High-performance lightweight visualizer bar
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

    // Target heights for smooth animation
    readonly property real targetHeight: minHeight + amplitude * (maxHeight - minHeight)
    readonly property real bgTargetHeight: minHeight + bgAmplitude * (maxHeight - minHeight)

    property real currentHeight: targetHeight
    property real currentBgHeight: bgTargetHeight

    Behavior on currentHeight {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutCubic
        }
    }

    Behavior on currentBgHeight {
        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }
    }

    // 1. Background Capsule (Translucent)
    Rectangle {
        id: bgCapsule
        width: root.barWidth * 1.4
        height: Math.min(root.maxHeight * 1.2, root.currentBgHeight * 1.2 + 4)
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
        height: root.currentHeight
        radius: width / 2
        anchors.centerIn: parent
        color: root.fgColor
        layer.enabled: false
    }
}
