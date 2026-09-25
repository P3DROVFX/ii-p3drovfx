import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * Material 3 Expressive circular progress: a wavy indicator, a flat track, and a gap
 * between them. The wave is static — it moves only when the value does, so a ring on
 * screen costs nothing between ticks.
 */
Item {
    id: root

    property real value: 0
    property real thickness: 10
    property bool wavy: true
    property int waves: 14
    property real amplitude: root.thickness * 0.32
    property real gapDegrees: 8
    property real pointsPerDegree: 1.5
    property color colIndicator: ClockStyle.colPrimary
    property color colTrack: ClockStyle.colSecondaryContainer

    readonly property real clampedValue: Math.max(0, Math.min(1, root.value))
    property real animatedValue: root.clampedValue
    Behavior on animatedValue {
        enabled: !ClockStyle.reducedMotion
        NumberAnimation {
            duration: ClockStyle.motionSpatial.duration
            easing.type: Easing.OutCubic
        }
    }

    readonly property real centre: Math.min(root.width, root.height) / 2
    readonly property real ringRadius: Math.max(0, root.centre - root.thickness / 2 - (root.wavy ? root.amplitude : 0))
    readonly property real sweep: root.animatedValue * 360
    readonly property real gap: root.sweep > 0 && root.sweep < 360 ? root.gapDegrees : 0

    readonly property var wavePoints: {
        const points = [];
        const sweep = root.sweep;
        if (sweep <= 0 || root.ringRadius <= 0)
            return points;
        const count = Math.max(2, Math.ceil(sweep * root.pointsPerDegree));
        for (let i = 0; i <= count; i++) {
            const degrees = sweep * i / count;
            const theta = (degrees - 90) * Math.PI / 180;
            const wave = root.wavy ? root.amplitude * Math.sin(degrees * Math.PI / 180 * root.waves) : 0;
            const r = root.ringRadius + wave;
            points.push(Qt.point(root.width / 2 + r * Math.cos(theta), root.height / 2 + r * Math.sin(theta)));
        }
        return points;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.sweep >= 360 ? "transparent" : root.colTrack
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.ringRadius
                radiusY: root.ringRadius
                startAngle: -90 + root.sweep + root.gap
                sweepAngle: Math.max(0, 360 - root.sweep - root.gap * 2)
            }
        }

        ShapePath {
            strokeColor: root.sweep > 0 ? root.colIndicator : "transparent"
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            fillColor: "transparent"

            PathPolyline {
                path: root.wavePoints
            }
        }
    }
}
