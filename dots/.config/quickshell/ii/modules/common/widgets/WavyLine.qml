pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.modules.common

Item {
    id: root

    property real amplitudeMultiplier: 0.5
    property real frequency: 6
    property color color: Appearance?.colors.colPrimary ?? "#685496"
    property real lineWidth: 4
    property real fullLength: width
    property bool animateWave: false

    property real phase: 0.0

    readonly property real amplitude: root.lineWidth * root.amplitudeMultiplier
    readonly property real centerY: root.height / 2

    readonly property var wavePoints: {
        var pts = [];
        var w = root.width;
        var h = root.height;
        if (w <= 0 || h <= 0)
            return pts;

        var startX = root.lineWidth / 2;
        var endX = w - (root.lineWidth / 2);
        if (endX <= startX)
            return pts;

        var amp = root.amplitude;
        var cY = root.centerY;

        if (amp <= 0.01) {
            pts.push(Qt.point(startX, cY));
            pts.push(Qt.point(endX, cY));
            return pts;
        }

        var len = Math.max(1, root.fullLength);
        var k = (root.frequency * 2 * Math.PI) / len;
        var curPhase = root.phase;
        var step = 1.5;

        pts.push(Qt.point(startX, cY + amp * Math.sin(k * startX + curPhase)));
        for (var x = startX + step; x < endX; x += step) {
            pts.push(Qt.point(x, cY + amp * Math.sin(k * x + curPhase)));
        }
        pts.push(Qt.point(endX, cY + amp * Math.sin(k * endX + curPhase)));

        return pts;
    }

    Shape {
        id: shape
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        asynchronous: false
        antialiasing: true
        layer.enabled: true
        layer.samples: 8
        layer.smooth: true

        ShapePath {
            strokeWidth: root.lineWidth
            strokeColor: root.color
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathPolyline {
                path: root.wavePoints
            }
        }
    }

    Timer {
        id: animTimer
        interval: 66 // ~15 FPS: visually smooth wave flow while saving 90% compositor surface redraws
        running: root.animateWave && root.visible && root.amplitudeMultiplier > 0.01
        repeat: true
        onTriggered: {
            root.phase += 0.16;
            if (root.phase > 6.2831853) {
                root.phase -= 6.2831853;
            }
        }
    }

    onAnimateWaveChanged: {
        if (!animateWave) {
            root.phase = 0;
        }
    }
}
