pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// Beat shake: phonk-edit camera hits on the kick drum. One engine for the Immersive
// frontend; it only computes the motion, and whoever is on screen applies it: the
// kinetic lyrics' camera when they run, the artwork otherwise (songs without lyrics).
// Hits can also be fired by hand (`punchWord` for "!" words) while not listening.
QtObject {
    id: root

    /// Run the kick detector (its own cava process).
    property bool listening: false
    property real viewWidth: 1920
    property real viewHeight: 1080
    /// The constant sway runs (the shake is on and the music plays).
    property bool swaying: false
    /// Shake energy is live or still settling: drive `step` every frame.
    readonly property bool moving: swaying || _hits.length > 0 || !_shakeIdle || swayX !== 0

    // Sway: the always-on layer of an edit's shake, under the hits. Very low frequency,
    // high amplitude: the frame drifts a few percent and rolls a degree or two, never
    // still. Each axis is a Catmull-Rom curve through random targets (no stop at each
    // target, unlike an eased step), at its own slow rate. A driving beat widens it a
    // little. It fades in and out with `swaying`.
    readonly property real swayMove: 0.065    // view heights
    readonly property real swayTilt: 2.2      // degrees
    readonly property real swayZoomAmount: 0.025
    property real swayX: 0
    property real swayY: 0
    property real swayRoll: 0
    property real swayZoom: 0
    property real _swayGain: 0
    property real _swayTime: 0

    function hash(n) {
        let x = Math.imul(n ^ 0x9e3779b9, 0x85ebca6b);
        x ^= x >>> 13;
        x = Math.imul(x, 0xc2b2ae35);
        x ^= x >>> 16;
        return (x >>> 0) / 4294967296;
    }

    // Config: background.mediaMode.kineticBeatShake (off by default).
    //
    // Detection: a cava of its own (scripts/cava/beat_config.txt: 60 fps, barely
    // smoothed) feeds a kick detector on bars 0-1 (30-76 Hz) only; the bars above carry
    // the bass line and made every note a hit. A hit is a rise of the kick band over the
    // last three frames above an adaptive threshold (running mean + 2.5 σ of that rise,
    // 30% of the recent peak, a floor), at most one every 220 ms.
    //
    // Motion: recipes copied from After Effects shake presets (Brenxdan shake pack:
    // Sapphire S_DissolveShake, Transform and Turbulent Displace keyframes, read from
    // the .ffx files). A Sapphire shake is smooth random motion on X, Y, Z (zoom) and
    // tilt at `freq` new targets a second, under an Amplitude envelope that jumps to
    // its peak on the hit and falls in 0.1-0.33 s; motion blur over half a frame is
    // what makes it read as a hit instead of a tremble. Envelopes are the presets' own
    // keyframes, evaluated as AE temporal béziers: [time s, value, out speed /s, out
    // influence, in speed /s, in influence] (speed and influence on the arriving key
    // shape the segment that ends there). Axis gains are each preset's Rand Amp over
    // the agro preset's X (56).
    readonly property var curveHit: [[0, 1, -7.44, 0.117, 0, 0.333], [0.333, 0, 0, 0.333, 0, 1]]  // agro HIT
    readonly property var curveShort: [[0, 1, 0, 0, 0, 0], [0.1, 0, 0, 0.167, 0, 1]]             // agro shake 1
    readonly property var curveShort2: [[0, 1, 0, 0, 0, 0], [0.141, 0, 0, 0.167, 0, 1]]          // agro shake 2
    readonly property var curveSoft: [[0, 1, 0, 0, 0, 0], [0.333, 0, 0, 0.333, 0, 1]]            // soft / floaty
    readonly property var curveScale: [[0, 1, -5.17, 0.31, 0, 0.333], [0.333, 0, 0, 0.333, 0, 1]] // scale transform soft
    readonly property var curveSnap: [[0, 1, 0, 0, 0, 0], [0.017, 0, 0, 0, 0, 0]]                // exp z bounce
    readonly property var curveFlick: [[0, 1, 0, 0, 0, 0], [0.017, -1, 0, 0, 0, 0], [0.033, 0, 0, 0, 0, 0]] // exp rotate
    readonly property var curveRoll: [[0, 1, -7.2, 0.4, 0, 0.333], [0.167, 0, 0, 0.333, 0, 1]]  // rotate transform soft
    readonly property var curveTurb: [[0, 1, -14.1, 0.06, 0, 0.68], [0.333, 0, 0, 0.06, 0, 0.68]] // agro HIT w turb
    readonly property var shakeRecipes: ({
        "agroHit": { "curve": "curveHit", "peak": 1, "freq": 10, "x": 1, "y": 1, "z": 0.5, "tilt": 2 },
        "agroHitX": { "curve": "curveHit", "peak": 1, "freq": 10, "x": 1, "y": 0.27, "z": 0.5, "tilt": 2 },
        "agroHitY": { "curve": "curveHit", "peak": 1, "freq": 10, "x": 0.45, "y": 1, "z": 0.5, "tilt": 2 },
        "zAgro": { "curve": "curveHit", "peak": 1, "freq": 10, "x": 0.6, "y": 0.6, "z": 0.82, "tilt": 5 },
        "agroShake": { "curve": "curveShort", "peak": 1, "freq": 10, "x": 0.45, "y": 0.45, "z": 0, "tilt": 1 },
        "agroShake2": { "curve": "curveShort2", "peak": 0.6, "freq": 10, "x": 0.45, "y": 1.34, "z": 0.45, "tilt": 3 },
        "softShake": { "curve": "curveSoft", "peak": 0.6, "freq": 3, "freqEnd": 1, "x": 0.45, "y": 1.34, "z": 0, "tilt": 3 },
        "floaty": { "curve": "curveSoft", "peak": 0.6, "freq": 3, "x": 0.45, "y": 1.34, "z": 0, "tilt": 3 }
    })
    // One preset unit on screen: X/Y in view heights, Z in zoom, tilt in degrees.
    readonly property real shakeUnitMove: 0.06
    readonly property real shakeUnitZoom: 0.06
    readonly property real shakeUnitTilt: 0.8

    property real beatPunch: 0     // zoom fraction from the scale presets
    property real beatRoll: 0      // degrees from the rotation presets
    property real beatGlow: 0
    property real beatTurbulence: 0
    property vector2d beatSplit: Qt.vector2d(0, 0)
    property real shakeX: 0
    property real shakeY: 0
    property real shakeZoom: 0
    property real shakeRoll: 0
    // Motion blur of the shake itself, for the shader.
    property vector2d shakeStreak: Qt.vector2d(0, 0)
    property real shakeZoomStreak: 0
    property real turbSeed: 0
    property real rhythm: 0        // 0..1, how steady and fast the kick is
    property var _hits: []         // live instances: { kind, curve, gain, start, ... }
    property string _lastRecipe: ""
    property real _splitAngle: 0
    property real _kick: 0
    property var _kickHistory: [0, 0, 0]
    property real _fluxMean: 0
    property real _fluxVar: 0
    property real _fluxPeak: 0.3
    property double _lastBeatMs: 0
    property var _beatTimes: []

    property Process _cava: Process {
        running: root.listening
        command: ["cava", "-p", FileUtils.trimFileProtocol(Directories.scriptPath) + "/cava/beat_config.txt"]
        stdout: SplitParser {
            onRead: data => root.readBeat(data)
        }
    }
    onListeningChanged: if (!listening) {
        _beatTimes = [];
        rhythm = 0;
    }

    function readBeat(data) {
        const bars = data.split(";");
        if (bars.length < 3)
            return;
        const kick = (parseFloat(bars[0]) + parseFloat(bars[1])) / 2000;
        if (isNaN(kick))
            return;
        root._kick = kick;
        const history = root._kickHistory;
        const flux = Math.max(0, kick - Math.min(history[0], history[1], history[2]));
        root._kickHistory = [history[1], history[2], kick];
        // About 1.5 s of memory at 60 Hz.
        const a = 1 / 90;
        root._fluxMean += (flux - root._fluxMean) * a;
        root._fluxVar += ((flux - root._fluxMean) * (flux - root._fluxMean) - root._fluxVar) * a;
        root._fluxPeak = Math.max(root._fluxPeak * Math.exp(-1 / 240), flux);
        const threshold = Math.max(root._fluxMean + 2.5 * Math.sqrt(root._fluxVar), root._fluxPeak * 0.3, 0.12);
        const now = Date.now();
        if (flux > threshold && now - root._lastBeatMs > 220) {
            root._lastBeatMs = now;
            // Spread over 0..1: a hit at 30% of the recent peak is 0, the peak is 1.
            root.hit(Math.max(0, Math.min(1, (flux / Math.max(0.12, root._fluxPeak) - 0.3) / 0.7)));
            const times = root._beatTimes.filter(t => now - t < 4000);
            times.push(now);
            root._beatTimes = times;
            root.rhythm = Math.max(0, Math.min(1, (times.length / 4 - 1) / 2));
        }
    }

    // AE temporal bézier through the keys, at `t` seconds.
    function curveAt(keys, t) {
        if (t <= keys[0][0])
            return keys[0][1];
        for (let i = 0; i + 1 < keys.length; i++) {
            const a = keys[i], b = keys[i + 1];
            if (t > b[0])
                continue;
            const T = b[0] - a[0];
            if (T <= 0)
                return b[1];
            const oi = Math.max(0.0001, a[3]), ii = Math.max(0.0001, b[5]);
            const x1 = oi * T, y1 = a[1] + a[2] * oi * T;
            const x2 = T - ii * T, y2 = b[1] - b[4] * ii * T;
            const x = t - a[0];
            let lo = 0, hi = 1, u = 0.5;
            for (let k = 0; k < 18; k++) {
                u = (lo + hi) / 2;
                const bx = 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u * T;
                if (bx < x)
                    lo = u;
                else
                    hi = u;
            }
            const v = 1 - u;
            return v * v * v * a[1] + 3 * v * v * u * y1 + 3 * v * u * u * y2 + u * u * u * b[1];
        }
        return keys[keys.length - 1][1];
    }

    // Smooth random in -1..1: a new target every 1/freq s, eased between targets.
    function smoothNoise(seed, phase) {
        const k = Math.floor(phase);
        const f = phase - k;
        const e = f * f * (3 - 2 * f);
        const r0 = root.hash(seed + k * 7919) * 2 - 1;
        const r1 = root.hash(seed + (k + 1) * 7919) * 2 - 1;
        return r0 + (r1 - r0) * e;
    }

    function addHit(kind, curve, gain, extra) {
        const keys = root[curve];
        const list = root._hits.slice();
        list.push(Object.assign({ "kind": kind, "keys": keys, "gain": gain, "start": Date.now(),
                                  "length": keys[keys.length - 1][0],
                                  "seed": Math.floor(Math.random() * 1e6) }, extra ?? {}));
        root._hits = list;
    }

    function shakeWith(name, gain) {
        const recipe = root.shakeRecipes[name];
        root._lastRecipe = name;
        root.addHit("shake", recipe.curve, gain * recipe.peak, { "recipe": recipe });
    }

    // A hit picks its shake by strength (soft and floaty for light kicks, the short
    // agro shakes in between, the agro HITs on the hardest), never the same one twice
    // in a row, and adds the transform presets on top: always a scale hit (soft, or a
    // one-frame snap on hard kicks); a rotation whip or soft roll only on hard kicks;
    // turbulence, glow and an RGB split rarely, on the hardest.
    function hit(s) {
        const pool = s < 0.35 ? ["softShake", "floaty"]
            : (s < 0.7 ? ["agroShake", "agroShake2", "softShake"] : ["agroHit", "agroHitX", "agroHitY", "zAgro"]);
        const choices = pool.filter(name => name !== root._lastRecipe);
        root.shakeWith(choices[Math.floor(Math.random() * choices.length)], 0.45 + 0.55 * s);
        const snap = s > 0.75 && Math.random() < 0.35;
        root.addHit("scale", snap ? "curveSnap" : "curveScale", 0.06 + 0.12 * s);
        const sign = Math.random() < 0.5 ? -1 : 1;
        if (s > 0.6 && Math.random() < 0.2 + (s - 0.6))
            root.addHit("roll", snap || Math.random() < 0.5 ? "curveFlick" : "curveRoll",
                        sign * (snap ? (Math.random() < 0.5 ? 2 : 4) : 3) * (0.6 + 0.4 * s));
        if (s > 0.8 && Math.random() < 0.3) {
            root.turbSeed = Math.random() * 100;
            root.addHit("turb", "curveTurb", 0.012 * s);
        }
        if (s > 0.75 && Math.random() < 0.3)
            root.addHit("glow", "curveHit", 0.4 + 0.5 * s);
        if (s > 0.85 && Math.random() < 0.2) {
            root._splitAngle = Math.random() * Math.PI * 2;
            root.addHit("split", "curveShort", 0.004 + 0.005 * s);
        }
    }

    // A "!" word lands with a short agro shake and a scale snap, beat shake or not.
    function punchWord() {
        root.shakeWith("agroShake", 0.7);
        root.addHit("scale", "curveSnap", 0.08);
    }

    function swayNoise(seed, phase) {
        const k = Math.floor(phase), f = phase - k;
        const r = i => root.hash(seed + i * 7919) * 2 - 1;
        const p0 = r(k - 1), p1 = r(k), p2 = r(k + 1), p3 = r(k + 2);
        return 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f
                      + (3 * p1 - p0 - 3 * p2 + p3) * f * f * f);
    }

    function stepSway(dt) {
        root._swayGain += ((root.swaying ? 1 : 0) - root._swayGain) * (1 - Math.exp(-dt / 0.6));
        if (!root.swaying && root._swayGain < 0.002) {
            root._swayGain = 0;
            root.swayX = root.swayY = root.swayRoll = root.swayZoom = 0;
            return;
        }
        root._swayTime += dt;
        const t = root._swayTime;
        const g = root._swayGain * (1 + 0.3 * root.rhythm);
        root.swayX = g * root.viewHeight * root.swayMove * root.swayNoise(101, t * 0.32);
        root.swayY = g * root.viewHeight * root.swayMove * 0.8 * root.swayNoise(202, t * 0.27);
        root.swayRoll = g * root.swayTilt * root.swayNoise(303, t * 0.22);
        root.swayZoom = g * root.swayZoomAmount * root.swayNoise(404, t * 0.18);
    }

    property bool _shakeIdle: true
    function stepBeat(dt) {
        root.stepSway(dt);
        // Nothing live and everything already at rest: no property writes per frame.
        if (root._hits.length === 0 && root._shakeIdle)
            return;
        root._shakeIdle = root._hits.length === 0;
        const now = Date.now();
        let x = 0, y = 0, z = 0, tilt = 0, scale = 0, roll = 0, turb = 0, glow = 0, split = 0;
        const live = [];
        for (const h of root._hits) {
            const t = (now - h.start) / 1000;
            if (t > h.length)
                continue;
            live.push(h);
            const e = root.curveAt(h.keys, t) * h.gain;
            if (h.kind === "shake") {
                const r = h.recipe;
                const f1 = r.freqEnd ?? r.freq;
                const phase = r.freq * t + (f1 - r.freq) * t * t / (2 * h.length);
                x += e * r.x * root.smoothNoise(h.seed, phase);
                y += e * r.y * root.smoothNoise(h.seed + 1, phase);
                z += e * r.z * root.smoothNoise(h.seed + 2, phase);
                tilt += e * r.tilt * root.smoothNoise(h.seed + 3, phase);
            } else if (h.kind === "scale") {
                scale += e;
            } else if (h.kind === "roll") {
                roll += e;
            } else if (h.kind === "turb") {
                turb += e;
            } else if (h.kind === "glow") {
                glow = Math.max(glow, e);
            } else if (h.kind === "split") {
                split += e;
            }
        }
        if (live.length !== root._hits.length)
            root._hits = live;
        const unit = root.viewHeight * root.shakeUnitMove;
        const nx = x * unit, ny = y * unit, nz = z * root.shakeUnitZoom;
        // Motion blur over half a frame (the presets' Mo Blur Length 0.5).
        const shutter = 0.5 / 60;
        if (dt > 0) {
            const ux = -(nx - root.shakeX) / dt * shutter / Math.max(1, root.viewWidth);
            const uy = -(ny - root.shakeY) / dt * shutter / Math.max(1, root.viewHeight);
            root.shakeStreak = Qt.vector2d(ux, uy);
            const zoomNow = Math.log((1 + scale) * (1 + nz)), zoomBefore = Math.log((1 + root.beatPunch) * (1 + root.shakeZoom));
            root.shakeZoomStreak = (zoomNow - zoomBefore) / dt * shutter;
        }
        root.shakeX = nx;
        root.shakeY = ny;
        root.shakeZoom = nz;
        root.shakeRoll = tilt * root.shakeUnitTilt;
        root.beatPunch = scale;
        root.beatRoll = roll;
        root.beatTurbulence = turb;
        root.beatGlow = glow;
        root.beatSplit = split > 0 ? Qt.vector2d(Math.cos(root._splitAngle) * split, Math.sin(root._splitAngle) * split)
                                   : Qt.vector2d(0, 0);
    }

    property FrameAnimation _driver: FrameAnimation {
        running: root.moving
        onTriggered: root.stepBeat(Math.min(frameTime, 1 / 30))
    }
}
