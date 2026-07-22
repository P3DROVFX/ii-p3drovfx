import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Canvas { // High-performance silky-smooth liquid wave visualizer
    id: root
    property list<var> points: []
    property list<var> renderedPoints: []
    property real maxVisualizerValue: 1000
    property int smoothing: 3
    property bool live: true
    property color color: Appearance.m3colors.m3primary
    property real animTime: 0.0

    // Frame animation loop for continuous time & LERP interpolation
    FrameAnimation {
        running: root.live
        onTriggered: {
            root.animTime += 0.04;
            var n = root.points.length;
            if (n > 0) {
                if (root.renderedPoints.length !== n) {
                    root.renderedPoints = root.points.slice();
                } else {
                    var lerpSpeed = 0.12; // Continuous smooth liquid LERP
                    var arr = root.renderedPoints.slice();
                    for (var i = 0; i < n; i++) {
                        var target = root.live ? (root.points[i] || 0) : 0;
                        arr[i] += (target - arr[i]) * lerpSpeed;
                    }
                    root.renderedPoints = arr;
                }
            }
            root.requestPaint();
        }
    }

    anchors.fill: parent
    renderTarget: Canvas.Image

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        var ptsRaw = root.renderedPoints;
        var n = ptsRaw.length;
        if (n < 2) return;

        // Apply spatial 3-point Gaussian filter for rounded wave peaks
        var pts = [];
        for (var i = 0; i < n; i++) {
            var prev = ptsRaw[Math.max(0, i - 1)];
            var curr = ptsRaw[i];
            var next = ptsRaw[Math.min(n - 1, i + 1)];
            pts.push(prev * 0.25 + curr * 0.5 + next * 0.25);
        }

        var maxVal = root.maxVisualizerValue || 1;
        var h = height;
        var w = width;

        ctx.beginPath();
        ctx.moveTo(0, h);

        // Continuous quadratic curve drawing
        for (var i = 0; i < n - 1; ++i) {
            var x1 = i * w / (n - 1);
            var y1 = h - (pts[i] / maxVal) * (h * 0.55);
            var x2 = (i + 1) * w / (n - 1);
            var y2 = h - (pts[i + 1] / maxVal) * (h * 0.55);
            var xc = (x1 + x2) / 2;
            var yc = (y1 + y2) / 2;
            if (i === 0) {
                ctx.lineTo(x1, y1);
            }
            ctx.quadraticCurveTo(x1, y1, xc, yc);
        }
        ctx.lineTo(w, h);
        ctx.closePath();

        ctx.fillStyle = Qt.rgba(
            root.color.r,
            root.color.g,
            root.color.b,
            0.22
        );
        ctx.fill();
    }

    layer.enabled: false
}