import QtQuick
import QtQuick.Effects

// The gesture owns progress; no Behavior may chase its per-frame values.
// Allocate an effect only for the small piece that is actually dissolving.
Item {
    id: root
    property real reveal: 1
    property real directionX: 0
    property real directionY: 1
    property real travel: 12
    property bool entering: false
    opacity: Math.max(0, Math.min(1, reveal))
    visible: opacity > 0.001
    enabled: opacity > 0.95
    transform: Translate {
        x: root.directionX * root.travel * (1 - root.opacity) * (root.entering ? -1 : 1)
        y: root.directionY * root.travel * (1 - root.opacity) * (root.entering ? -1 : 1)
    }
    layer.enabled: opacity > 0.001 && opacity < 0.999
    layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 8
        blur: 1 - root.opacity
        autoPaddingEnabled: true
    }
}
