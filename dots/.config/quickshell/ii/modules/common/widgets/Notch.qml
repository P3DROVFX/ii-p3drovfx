import QtQuick
import QtQuick.Shapes
import qs.modules.common

Item {
    id: root

    property real bodyWidth: 200
    property real bodyHeight: 32
    property real topRadius: 6
    property real bottomRadius: 14
    property color fillColor: Appearance.colors.colLayer0

    implicitWidth: bodyWidth
    implicitHeight: bodyHeight

    Shape {
        anchors.fill: parent
        antialiasing: true
        layer.enabled: true
        layer.samples: 4
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: path
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.fillColor
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.FlatCap

            // Using root.width/root.height instead of bodyWidth/bodyHeight
            // to avoid double-animation when parent's width/height animate.
            readonly property real w:  root.width
            readonly property real h:  root.height
            readonly property real tr: root.topRadius
            readonly property real br: root.bottomRadius

            startX: 0; startY: 0

            PathQuad {
                x: path.tr; y: path.tr
                controlX: path.tr; controlY: 0
            }
            PathLine { x: path.tr; y: path.h - path.br }
            PathQuad {
                x: path.tr + path.br; y: path.h
                controlX: path.tr;    controlY: path.h
            }
            PathLine { x: path.w - path.tr - path.br; y: path.h }
            PathQuad {
                x: path.w - path.tr;     y: path.h - path.br
                controlX: path.w - path.tr; controlY: path.h
            }
            PathLine { x: path.w - path.tr; y: path.tr }
            PathQuad {
                x: path.w; y: 0
                controlX: path.w - path.tr; controlY: 0
            }
            PathLine { x: 0; y: 0 }
        }
    }

    Behavior on bodyWidth     { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on bodyHeight    { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on topRadius     { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on bottomRadius  { NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on fillColor     { ColorAnimation   { duration: Appearance.animation.elementMoveFast.duration; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
}
