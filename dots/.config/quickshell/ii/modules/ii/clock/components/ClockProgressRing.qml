import QtQuick
import QtQuick.Shapes
import qs.modules.common

/**
 * Material 3 Expressive circular progress: a wavy indicator, a flat track, and a gap
 * between them.
 *
 * Two things keep it from looking mechanical. A running countdown moves the value once a
 * second; with `tickDuration` set, each tick glides linearly over exactly that second, so
 * the arc drains continuously instead of stepping and settling. Anything larger than a
 * tick (a reset, +1:00, a new phase) takes the eased spatial curve instead. And the wave
 * never switches off: pausing flattens it and resuming raises it again, over the same
 * motion, so the ring does not swap shapes under you.
 */
Item {
    id: root

    property real value: 0
    property real thickness: 10
    property bool wavy: true
    property int waves: 14
    property real maxAmplitude: root.thickness * 0.32
    property real gapDegrees: 8
    property real pointsPerDegree: 1
    /// Duration of one regular tick of `value`, in ms. 0 eases every change.
    property int tickDuration: 0
    property color colIndicator: ClockStyle.colPrimary
    property color colTrack: ClockStyle.colSecondaryContainer

    readonly property real clampedValue: Math.max(0, Math.min(1, root.value))
    property real animatedValue: 0
    Component.onCompleted: root.animatedValue = root.clampedValue
    property real waveAmount: root.wavy ? 1 : 0

    Behavior on waveAmount {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }
    Behavior on colIndicator {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    NumberAnimation {
        id: glide
        target: root
        property: "animatedValue"
    }

    onClampedValueChanged: {
        glide.stop();
        if (ClockStyle.reducedMotion || !root.visible) {
            root.animatedValue = root.clampedValue;
            return;
        }
        const delta = Math.abs(root.clampedValue - root.animatedValue);
        const tick = root.tickDuration > 0 && delta < 0.05;
        glide.from = root.animatedValue;
        glide.to = root.clampedValue;
        glide.duration = tick ? root.tickDuration : ClockStyle.motionDefault.duration;
        glide.easing.type = tick ? Easing.Linear : Easing.BezierSpline;
        glide.easing.bezierCurve = ClockStyle.motionDefault.bezierCurve;
        glide.start();
    }

    readonly property real amplitude: root.maxAmplitude * root.waveAmount
    readonly property real centre: Math.min(root.width, root.height) / 2
    readonly property real ringRadius: Math.max(0, root.centre - root.thickness / 2 - root.maxAmplitude)
    readonly property real sweep: root.animatedValue * 360
    readonly property real gap: root.sweep > 0 && root.sweep < 360 ? root.gapDegrees : 0

    readonly property var wavePoints: {
        const points = [];
        const sweep = root.sweep;
        if (sweep <= 0 || root.ringRadius <= 0)
            return points;
        const count = Math.max(2, Math.ceil(sweep * root.pointsPerDegree));
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
