import QtQuick
import QtQuick.Shapes
import qs.modules.common

// The grip is a short corner arc, not an outline around the tile. Its ends
// and hit target remain round even when the tile itself uses sharp corners.
Item {
    id: root
    property real cornerRadius: Appearance.rounding.large
    property real thickness: 4
    property real hitSize: Math.max(38, arcRadius + thickness + 12)
    property bool pressed: false
    property bool hovered: false
    readonly property real arcRadius: Math.max(thickness, cornerRadius > 0 ? cornerRadius : 12)
    width: hitSize
    height: hitSize

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.pressed ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width - root.arcRadius - root.thickness / 2
                centerY: root.height - root.arcRadius - root.thickness / 2
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: 20
                sweepAngle: 50
            }
        }
    }
}
