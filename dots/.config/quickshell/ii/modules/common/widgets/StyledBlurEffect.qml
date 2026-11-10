import QtQuick
import QtQuick.Effects

// Used as a `layer.effect`: the layer assigns `source` itself.
MultiEffect {
    id: root
    anchors.fill: source
    saturation: 0.2
    blurEnabled: true
    blurMax: 100
    blur: 1
}
