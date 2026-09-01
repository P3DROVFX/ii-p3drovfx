import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property color color: "#ffffff"
    property int dashLength: 6
    property int gapLength: 4
    property int borderWidth: 1
    property real radius: 0

    // A Canvas.Image allocates and uploads a full rectangular texture even
    // though this component only draws a stroke. Under repeated QML reloads
    // that texture could be composed as an opaque, uninitialized rectangle.
    // ShapePath keeps the same dashed outline in scene-graph geometry and has
    // no backing image capable of covering the button content.
    ShapePath {
        id: dashedPath

        readonly property real effectiveStrokeWidth: Math.max(0.001, root.borderWidth)
        readonly property real effectiveRadius: Math.max(0, Math.min(root.radius, Math.max(0, Math.min(root.width - effectiveStrokeWidth, root.height - effectiveStrokeWidth) / 2)))
        readonly property real straightLength: Math.max(0, root.width - effectiveStrokeWidth - effectiveRadius * 2) * 2
            + Math.max(0, root.height - effectiveStrokeWidth - effectiveRadius * 2) * 2
        readonly property real perimeter: straightLength + 2 * Math.PI * effectiveRadius
        readonly property real patternLength: Math.max(0.001, root.dashLength + root.gapLength)
        readonly property int patternRepeats: Math.max(1, Math.round(perimeter / patternLength))
        readonly property real patternScale: perimeter > patternLength ? perimeter / (patternRepeats * patternLength) : 1

        fillColor: "transparent"
        strokeColor: root.borderWidth > 0 ? root.color : "transparent"
        strokeWidth: effectiveStrokeWidth
        strokeStyle: root.gapLength > 0 ? ShapePath.DashLine : ShapePath.SolidLine
        dashPattern: [
            Math.max(0.001, root.dashLength * patternScale / effectiveStrokeWidth),
            Math.max(0.001, root.gapLength * patternScale / effectiveStrokeWidth)
        ]
        capStyle: ShapePath.FlatCap
        joinStyle: ShapePath.RoundJoin

        PathRectangle {
            width: root.width
            height: root.height
            radius: dashedPath.effectiveRadius
            strokeAdjustment: dashedPath.strokeWidth
        }
    }
}
