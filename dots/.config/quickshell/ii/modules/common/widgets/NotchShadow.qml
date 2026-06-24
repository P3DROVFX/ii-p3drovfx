import QtQuick
import QtQuick.Effects
import qs.modules.common

Item {
    id: root

    property real bodyWidth: 185
    property real bodyHeight: 32
    property real topRadius: 6
    property real bottomRadius: 14

    property color tint: Appearance.colors.colLayer0
    property real tintAmount: 0
    property real shadowOpacity: 0.55
    property int blurAmount: 24
    property int verticalOffset: 6

    readonly property color _color: tintAmount > 0
        ? Qt.rgba(
            Appearance.colors.colLayer0.r * (1 - tintAmount) + tint.r * tintAmount,
            Appearance.colors.colLayer0.g * (1 - tintAmount) + tint.g * tintAmount,
            Appearance.colors.colLayer0.b * (1 - tintAmount) + tint.b * tintAmount,
            1)
        : Appearance.colors.colLayer0

    Notch {
        id: shadowShape
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.verticalOffset
        bodyWidth: root.bodyWidth
        bodyHeight: root.bodyHeight
        topRadius: root.topRadius
        bottomRadius: root.bottomRadius
        fillColor: root._color
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: shadowShape
        anchors.horizontalCenterOffset: 0
        source: shadowShape
        blurEnabled: true
        blurMax: 64
        blur: 1.0
        opacity: root.shadowOpacity
    }

    Behavior on tintAmount   { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
    Behavior on shadowOpacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
}
