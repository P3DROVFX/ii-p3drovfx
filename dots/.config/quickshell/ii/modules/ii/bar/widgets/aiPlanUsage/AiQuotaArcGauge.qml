import QtQuick
import QtQuick.Shapes
import qs.modules.common

Item {
    id: root

    property real value: 0
    property int implicitSize: Math.max(24, Appearance.sizes.baseBarHeight - 16)
    property int lineWidth: Math.max(2, Appearance.rounding.unsharpen)
    property color highlightColor: Appearance.colors.colPrimary
    property color trackColor: Appearance.colors.colPrimaryContainer

    readonly property real clampedValue: Math.max(0, Math.min(1, root.value))
    property real animatedValue: root.clampedValue
    readonly property real radiusValue: (root.implicitSize - root.lineWidth) / 2

    implicitWidth: root.implicitSize
    implicitHeight: Math.round(root.implicitSize * 0.58)

    Behavior on animatedValue {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.smooth: true

        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height - root.lineWidth / 2
                radiusX: root.radiusValue
                radiusY: root.radiusValue
                startAngle: 180
                sweepAngle: 180
            }
        }

        ShapePath {
            strokeColor: root.highlightColor
            strokeWidth: root.lineWidth
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height - root.lineWidth / 2
                radiusX: root.radiusValue
                radiusY: root.radiusValue
                startAngle: 180
                sweepAngle: 180 * root.animatedValue
            }
        }
    }
}
