pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.ii.bar.widgets.dashboard.icons

AnimatedIcon {
    id: root

    property bool dark: true
    property bool initialized: false
    // One clock owns both glyphs: reversal continues from their current positions.
    property real transition: dark ? 1 : 0

    Component.onCompleted: initialized = true
    Behavior on transition {
        enabled: root.initialized
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }

    Item {
        anchors.fill: parent
        clip: true

        Item {
            width: 24
            height: 24
            y: -28 * (1 - root.transition)
            visible: root.transition > 0
            Shape {
                y: 24
                width: 960
                height: 960
                scale: 1 / 40
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.color
                    // Material Symbols Rounded bedtime: the filled moon silhouette.
                    PathSvg {
                        path: "M524-40q-84 0-157.5-32t-128-86.5Q184-213 152-286.5T120-444q0-128 72-232t193-146q22-8 41 5.5t18 36.5q-3 85 27 162t90 137q60 60 137 90t162 27q26-1 38.5 17.5T903-305q-44 120-147.5 192.5T524-40Z"
                    }
                }
            }
        }
        Item {
            width: 24
            height: 24
            y: 28 * root.transition
            visible: root.transition < 1
            // Filled disk and eight rounded rays match light_mode's 24-unit grid.
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.color
                    PathAngleArc { centerX: 12; centerY: 12; radiusX: 5; radiusY: 5; startAngle: 0; sweepAngle: 360 }
                }
            }
            Repeater {
                model: 8
                Shape {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 45
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.color
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        startX: 12
                        startY: 2
                        PathLine { x: 12; y: 4 }
                    }
                }
            }
        }
    }
}
