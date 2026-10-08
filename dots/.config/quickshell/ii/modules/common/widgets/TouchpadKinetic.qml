import QtQuick
import qs.modules.common

/**
 * Touchpad scrolling for a Flickable. The content follows the fingers through a
 * short ease, and once they stop it carries on for a moment at the speed they had,
 * slowing as it goes. The owner feeds it each touchpad event (ScrollWheel.touchpadStep)
 * and calls stop() when a mouse wheel or a drag takes over.
 */
QtObject {
    id: root

    required property Flickable flickable

    // The content closes most of the gap to its destination in about this long
    readonly property real followTau: 0.02
    // The glide loses its speed over about this long; its length is speed times this
    readonly property real glideTau: 0.25
    // How far back the speed is measured, in ms
    readonly property int windowMs: 100
    // Below this speed a touch is a tap or a resting finger, not a fling: no glide
    readonly property real glideStartSpeed: 40
    // The glide is over once it has slowed below this, px/s
    readonly property real stopSpeed: 8
    // A touch after this much silence lands on the content as it is: a glide stops dead
    readonly property int resumeMs: 60
    readonly property real maxSpeed: 4000
    // Off: the content follows the fingers and stops where they stop
    readonly property bool glide: Config.options?.interactions?.scrolling?.touchpadKinetic ?? true

    // Where the content is heading; the owner reports it as the scroll destination
    readonly property real target: _target

    readonly property real minY: flickable.originY - flickable.topMargin
    readonly property real maxY: Math.max(minY, flickable.originY + flickable.contentHeight - flickable.height + flickable.bottomMargin)

    property real _target: 0
    // Where the events alone put the content; the glide is added on top of it
    property real _eventTarget: 0
    // Content speed at the last event (px/s, positive = down), and when that event came
    property real _glideSpeed: 0
    property double _lastEventMs: 0
    property double _lastTickMs: 0
    // { t, d } for the events of the last windowMs; d is the step fed
    property var _samples: []

    /** One touchpad event. `step` is ScrollWheel's: positive scrolls toward the top. */
    function feed(step) {
        if (step === 0)
            return;
        const now = Date.now();
        if (!frame.running || now - _lastEventMs > resumeMs) {
            // A new touch starts from wherever the content is now
            _eventTarget = flickable.contentY;
            _samples = [];
            _glideSpeed = 0;
            _lastTickMs = now;
            frame.running = true;
        }
        _eventTarget = clamp(_eventTarget - step);
        _samples = trimmed(_samples.concat([{ t: now, d: step }]));
        _lastEventMs = now;
        _glideSpeed = speedOfSamples();
        _target = _eventTarget;
    }

    /** A drag or a mouse wheel took over: the content stays where it is. */
    function stop() {
        if (!frame.running)
            return;
        frame.running = false;
        _glideSpeed = 0;
        _samples = [];
    }

    function clamp(value) {
        return Math.max(minY, Math.min(maxY, value));
    }

    function trimmed(samples) {
        const newest = samples[samples.length - 1].t;
        return samples.filter(s => s.t >= newest - windowMs);
    }

    // The content speed the recent events add up to, zero when too slow to glide
    function speedOfSamples() {
        if (!glide)
            return 0;
        let sum = 0;
        for (const s of _samples)
            sum += s.d;
        // The content moves against the step
        const speed = Math.max(-maxSpeed, Math.min(maxSpeed, -sum / (windowMs / 1000)));
        return Math.abs(speed) < glideStartSpeed ? 0 : speed;
    }

    // How far the glide has carried the content past the last event, at nowMs
    function glideAt(nowMs) {
        const t = Math.max(0, (nowMs - _lastEventMs) / 1000);
        return _glideSpeed * glideTau * (1 - Math.exp(-t / glideTau));
    }

    function tick() {
        const now = Date.now();
        const dt = Math.min(0.05, Math.max(0.001, (now - _lastTickMs) / 1000));
        _lastTickMs = now;
        const destination = clamp(_eventTarget + glideAt(now));
        _target = destination;
        const gap = destination - flickable.contentY;
        const speedNow = Math.abs(_glideSpeed) * Math.exp(-Math.max(0, now - _lastEventMs) / 1000 / glideTau);
        if (speedNow < stopSpeed && Math.abs(gap) < 0.5) {
            flickable.contentY = destination;
            frame.running = false;
            return;
        }
        flickable.contentY += gap * (1 - Math.exp(-dt / followTau));
    }

    // A QtObject has no default property, so its children are declared as typed
    // properties (as TouchpadScrollHandler does). The frame loop runs from a touch
    // until the glide settles, never per event.
    property FrameAnimation _frame: FrameAnimation {
        id: frame
        onTriggered: root.tick()
    }

    property Connections _flickable: Connections {
        target: root.flickable
        function onMovementStarted() {
            root.stop();
        }
    }
}
