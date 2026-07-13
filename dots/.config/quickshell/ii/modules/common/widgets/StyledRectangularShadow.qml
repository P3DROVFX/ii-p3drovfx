import QtQuick
import QtQuick.Effects
import qs.modules.common

RectangularShadow {
    id: shadow
    required property var target
    anchors.fill: (target && shadow.parent && (target.parent === shadow.parent || target === shadow.parent)) ? target : parent
    radius: (target && typeof target.radius === "number") ? target.radius : 0
    blur: 0.9 * Appearance.sizes.elevationMargin
    offset: Qt.vector2d(0.0, 1.0)
    spread: 1
    color: Appearance.colors.colShadow
    cached: true
    opacity: target ? target.opacity : 1.0
}
