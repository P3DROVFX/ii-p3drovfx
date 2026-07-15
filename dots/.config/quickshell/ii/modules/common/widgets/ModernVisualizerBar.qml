import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root

    property real amplitude: 0.0 // 0.0 to 1.0
    property real bgAmplitude: 0.0 // 0.0 to 1.0
    property real barWidth: 8
    property real maxHeight: 32
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

    // Current dynamic heights (animated smoothly)
    property real currentHeight: targetHeight
    property real currentBgHeight: bgTargetHeight

    Behavior on currentHeight {
        NumberAnimation {
            duration: 85
            easing.type: Easing.OutCubic
        }
    }

    Behavior on currentBgHeight {
        NumberAnimation {
            duration: 110
            easing.type: Easing.OutCubic
        }
    }

    // Phase/offset for gradient animation
    property real gradientPhase: 0.0
    NumberAnimation on gradientPhase {
        from: 0.0
        to: 1.0
        duration: 2500
        loops: Animation.Infinite
        running: root.playing && (root.amplitude > 0.01 || root.bgAmplitude > 0.01)
    }

    // 1. Background Capsule (Larger, translucent, blurred)
    Rectangle {
        id: bgCapsule
        width: root.barWidth * 1.5
        height: Math.min(root.maxHeight * 1.25, root.currentBgHeight * 1.25 + 4)
        radius: width / 2
        anchors.centerIn: parent
        opacity: 0.35 + root.bgAmplitude * 0.25 // pulsates with bgAmplitude

        gradient: Gradient {
            GradientStop { position: 0.0; color: root.color }
            GradientStop {
                position: (0.5 + Math.sin(root.gradientPhase * Math.PI * 2) * 0.2)
                color: ColorUtils.transparentize(root.color, 0.3)
            }
            GradientStop { position: 1.0; color: root.color }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 8
            blur: 0.3
        }
    }

    // 2. Foreground Capsule (Inner, bright, with gradient and glow)
    Rectangle {
        id: fgCapsule
        width: root.barWidth
        height: root.currentHeight
        radius: width / 2
        anchors.centerIn: parent

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: ColorUtils.mix(root.glowColor, root.fgColor, 0.4)
            }
            GradientStop {
                position: Math.max(0.1, Math.min(0.9, 0.5 + Math.cos(root.gradientPhase * Math.PI * 2) * 0.3))
                color: root.fgColor
            }
            GradientStop {
                position: 1.0
                color: root.color
            }
        }

        // Soft internal/external glow using layer effects
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 4
            blur: 0.25
            brightness: 0.1
            contrast: 0.1
        }
    }
}
