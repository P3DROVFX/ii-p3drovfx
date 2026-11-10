import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * Material 3 Expressive wavy circular progress, sized for the bar.
 *
 * The Clock app's `ClockProgressRing` without its style singleton: a wavy
 * indicator, a flat track and a gap between them. The value eases with the
 * expressive spatial curve; the wave flattens instead of switching off.
 */
Item {
    id: root

    property real value: 0
    property real thickness: 2.5
    property int waves: 10
    property bool wavy: true
    property real maxAmplitude: root.thickness * 0.5
    property real gapDegrees: 14
    property color colIndicator: Appearance.colors.colPrimary
    property color colTrack: Appearance.colors.colSecondaryContainer

    readonly property real clampedValue: Math.max(0, Math.min(1, root.value))
    property real animatedValue: root.clampedValue
    Behavior on animatedValue {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }
    property real waveAmount: root.wavy ? 1 : 0
    Behavior on waveAmount {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    readonly property real amplitude: root.maxAmplitude * root.waveAmount
    readonly property real ringRadius: Math.max(0, Math.min(root.width, root.height) / 2 - root.thickness / 2 - root.maxAmplitude)
    readonly property real sweep: root.animatedValue * 360
    readonly property real gap: root.sweep > 0 && root.sweep < 360 ? root.gapDegrees : 0

    readonly property var wavePoints: {
        const points = [];
        const sweep = root.sweep;
        if (sweep <= 0 || root.ringRadius <= 0)
            return points;
        const count = Math.max(2, Math.ceil(sweep / 2));
        const cx = root.width / 2;
        const cy = root.height / 2;
        for (let i = 0; i <= count; i++) {
            const degrees = sweep * i / count;
            const theta = (degrees - 90) * Math.PI / 180;
            const r = root.ringRadius + root.amplitude * Math.sin(degrees * Math.PI / 180 * root.waves);
            points.push(Qt.point(cx + r * Math.cos(theta), cy + r * Math.sin(theta)));
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
