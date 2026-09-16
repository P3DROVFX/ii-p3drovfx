pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.ii.bar.widgets.dashboard.icons

// Material Symbols Rounded night_sight_auto, split into crescent and A.
// Native paths use the font's 960-unit grid; each part remains independently movable.
AnimatedIcon {
    id: root

    property bool active: false
    property bool automatic: false
    property bool initialized: false
    property real activation: active ? 1 : 0
    property real autoProgress: automatic ? 1 : 0

    Component.onCompleted: initialized = true

    Behavior on activation {
        enabled: root.initialized
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    Behavior on autoProgress {
        enabled: root.initialized
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    Item {
        anchors.fill: parent
        opacity: 0.4 + 0.6 * root.activation
        transform: [
            Rotation { origin.x: 11; origin.y: 13; angle: -22 * (1 - root.activation) },
            Translate { x: 1 - root.autoProgress; y: (1 - root.activation) * 1.5 - (1 - root.autoProgress) }
        ]
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
                PathSvg {
                    path: "M440-120q-134 0-227-93t-93-227q0-58 19-110.5t53-94q34-41.5 81.5-69T377-748q25-3 39 17.5t1 42.5q-12 20-14.5 42.5T400-600q0 100 70 170t170 70q12 0 24-.5t24-4.5q21-8 37.5 7.5T735-321q-29 94-112 147.5T440-120Z"
                }
            }
        }
    }
    Shape {
        y: 24 - (1 - root.autoProgress) * 4
        width: 960
        height: 960
        scale: 1 / 40
        transformOrigin: Item.TopLeft
        opacity: root.autoProgress
        visible: opacity > 0
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            fillRule: ShapePath.OddEvenFill
            PathSvg {
                path: "M656-600l-20 56q-4 11-13 17.5t-20 6.5q-19 0-29.5-15.5T569-568l102-287q4-11 14-18t22-7h26q12 0 22 7t14 18l102 287q6 17-4.5 32.5T837-520q-11 0-20-6.5T804-544l-20-56H656Zm18-54h92l-46-146-46 146Z"
            }
        }
    }
}
