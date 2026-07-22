import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Canvas { // High-performance silky-smooth radial wave visualizer
    id: root
    property list<var> points: []
    property list<var> renderedPoints: []
    property list<var> smoothPoints: []
    property real maxVisualizerValue: 800
    property int smoothing: 2
    property bool live: true
    property color color: Appearance.m3colors.m3primary
    property real waveOpacity: 0.20
    property real waveBlur: 0
    property real barThickness: 10

    // Frame animation loop for organic LERP interpolation
    FrameAnimation {
        running: root.live && root.points.length > 0
        onTriggered: {
            var n = root.points.length;
            if (n === 0) return;
            if (root.renderedPoints.length !== n) {
                root.renderedPoints = root.points.slice();
            } else {
                var lerpSpeed = 0.20;
                var arr = root.renderedPoints.slice();
                for (var i = 0; i < n; i++) {
                    var target = root.live ? (root.points[i] || 0) : 0;
                    arr[i] += (target - arr[i]) * lerpSpeed;
                }
                root.renderedPoints = arr;
            }
            root.requestPaint();
        }
    }

    anchors.fill: parent
    renderTarget: Canvas.Image

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        var points = root.renderedPoints;
        var maxVal = root.maxVisualizerValue || 1;
        var w = width;
        var h = height;
        var n = points.length;
        if (n < 3) return;

        var cx = w / 2;
        var cy = h / 2;
        var maxRadius = Math.min(w, h) / 2;
        var inwardOffset = maxRadius * 0.8;

        var smoothWindow = root.smoothing; 
        root.smoothPoints = [];
        for (var i = 0; i < n; ++i) {
            var sum = 0, count = 0;
            for (var j = -smoothWindow; j <= smoothWindow; ++j) {
                var idx = Math.max(0, Math.min(n - 1, i + j));
                sum += points[idx];
                count++;
            }
            root.smoothPoints.push(sum / count);
        }
        if (!root.live) root.smoothPoints.fill(0); 
        
        var plotPoints = root.smoothPoints.slice();
        plotPoints.push(root.smoothPoints[0]);
        var visualN = plotPoints.length;

        ctx.beginPath();

        for (var i = visualN - 1; i >= 0; --i) {
            var normalized = plotPoints[i] / maxVal;
            var angle = (i / (visualN - 1)) * Math.PI * 2 - Math.PI / 2; 

            var currentRadius = maxRadius - (normalized * inwardOffset);
            if (currentRadius < (maxRadius - inwardOffset)) {
                currentRadius = (maxRadius - inwardOffset);
            }
            
            var x = cx + Math.cos(angle) * currentRadius;
            var y = cy + Math.sin(angle) * currentRadius;
            
            if (i === visualN - 1)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        
        ctx.lineTo(cx + maxRadius * Math.cos(Math.PI * 2 * (visualN-1) / (visualN-1) - Math.PI / 2), 
                   cy + maxRadius * Math.sin(Math.PI * 2 * (visualN-1) / (visualN-1) - Math.PI / 2)); 

        for (var i = 0; i < visualN; ++i) {
             var angle = (i / (visualN - 1)) * Math.PI * 2 - Math.PI / 2;
             var x = cx + Math.cos(angle) * maxRadius;
             var y = cy + Math.sin(angle) * maxRadius;
             ctx.lineTo(x, y);
        }

        ctx.closePath(); 
        ctx.fillStyle = Qt.rgba(
            root.color.r,
            root.color.g,
            root.color.b,
            root.waveOpacity
        );
        ctx.fill();
    }

    layer.enabled: false
}