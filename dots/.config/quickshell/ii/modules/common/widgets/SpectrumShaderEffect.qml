import QtQuick

// Base for the shader visualizers (HaloVisualizer, CircleSpectrumVisualizer). The
// spectrum reaches the shader as 32 bands of 0..1 packed in vec4 uniforms: the frame
// on screen (p0..p7), the next one (c0..c7) and `blend` between them. A tick only
// computes 32 numbers and the GPU interpolates the frames, so there is no per-frame
// JS loop and no canvas raster like the Canvas visualizers.
ShaderEffect {
    id: root

    property list<var> points: []
    property bool live: true
    property real maxValue: 1000
    // Quick to rise, slow to fall: beats punch, the shape doesn't flicker.
    property real attack: 0.7
    property real release: 0.3

    property vector2d resolution: Qt.vector2d(width, height)
    property real blend: 1
    property vector4d p0
    property vector4d p1
    property vector4d p2
    property vector4d p3
    property vector4d p4
    property vector4d p5
    property vector4d p6
    property vector4d p7
    property vector4d c0
    property vector4d c1
    property vector4d c2
    property vector4d c3
    property vector4d c4
    property vector4d c5
    property vector4d c6
    property vector4d c7

    readonly property int bandCount: 32
    property var _from: new Array(bandCount).fill(0)
    property var _to: new Array(bandCount).fill(0)
    property bool _settled: true

    onPointsChanged: _settled = false
    onLiveChanged: _settled = false

    function _sample(i) {
        const n = root.points.length;
        if (!root.live || n === 0)
            return 0;
        const x = i * (n - 1) / (root.bandCount - 1);
        const a = Math.floor(x);
        const b = Math.min(n - 1, a + 1);
        const v = (root.points[a] ?? 0) + ((root.points[b] ?? 0) - (root.points[a] ?? 0)) * (x - a);
        return Math.max(0, Math.min(1, v / root.maxValue));
    }

    function _tick() {
        const from = [];
        const to = [];
        let moving = false;
        for (let i = 0; i < root.bandCount; i++) {
            const shown = root._from[i] + (root._to[i] - root._from[i]) * root.blend;
            const target = root._sample(i);
            const next = shown + (target - shown) * (target > shown ? root.attack : root.release);
            from.push(shown);
            to.push(next < 0.002 && target === 0 ? 0 : next);
            moving = moving || Math.abs(next - shown) > 0.001;
        }
        root._from = from;
        root._to = to;
        for (let k = 0; k < 8; k++) {
            root["p" + k] = Qt.vector4d(from[k * 4], from[k * 4 + 1], from[k * 4 + 2], from[k * 4 + 3]);
            root["c" + k] = Qt.vector4d(to[k * 4], to[k * 4 + 1], to[k * 4 + 2], to[k * 4 + 3]);
        }
        root.blend = 0;
        blendAnimation.restart();
        if (!moving)
            root._settled = true;
    }

    NumberAnimation {
        id: blendAnimation
        target: root
        property: "blend"
        from: 0
        to: 1
        duration: tickTimer.interval
    }

    Timer {
        id: tickTimer
        interval: 33
        repeat: true
        triggeredOnStart: true
        running: root.visible && !root._settled
        onTriggered: root._tick()
    }
}
