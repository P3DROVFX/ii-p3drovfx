import QtQuick
import QtQuick.Effects
import qs.modules.common

RectangularShadow {
    required property var target
    anchors.fill: target
    radius: target.radius
    blur: 0.9 * Appearance.sizes.elevationMargin
    property vector2d shadowOffset: Qt.vector2d(0.0, 1.0)
    offset: shadowOffset
    spread: 1
    color: Appearance.colors.colShadow
    cached: true
    opacity: target ? target.opacity : 1.0
}
