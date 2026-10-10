import QtQuick
import qs.modules.common

/**
 * Touchpad scrolling for a Flickable. The content follows the fingers through a
 * short ease, and once they lift it carries on for a moment at the speed they had,
 * slowing as it goes. Fingers that stop but stay on the pad hold the content still.
 * The owner feeds it each touchpad event (ScrollWheel.touchpadStep, with the event's
 * phase) and calls stop() when a mouse wheel or a drag takes over.
 */
QtObject {
    id: root

    required property Flickable flickable

    // The content closes most of the gap to its destination in about this long
    readonly property real followTau: 0.02
    // The glide loses its speed over about this long; its length is speed times this
    readonly property real glideTau: 0.25
    // How far back from the lift the speed is measured, in ms
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
    // Content speed at the lift (px/s, positive = down), 0 while the fingers are down;
    // _lastEventMs is the last event, or the lift once gliding
    property real _glideSpeed: 0
    property double _lastEventMs: 0
    property double _lastTickMs: 0
    // { t, d } for the events of the last windowMs; d is the step fed
    property var _samples: []

    /**
     * One touchpad event. `step` is ScrollWheel's: positive scrolls toward the top.
     * `phase` is the WheelEvent's: the glide starts at Qt.ScrollEnd, which Qt sends
     * (with no delta) when the fingers lift. Resting fingers send nothing, so they
     * hold the content; a lift after a rest finds no recent speed and doesn't glide.
     */
    function feed(step, phase) {
        const now = Date.now();
        if (step !== 0) {
            if (!frame.running || _glideSpeed !== 0 || now - _lastEventMs > resumeMs) {
                // A new touch starts from wherever the content is now, a glide included
                _eventTarget = flickable.contentY;
                _samples = [];
                _glideSpeed = 0;
                _lastTickMs = now;
                frame.running = true;
            }
            _eventTarget = clamp(_eventTarget - step);
            _samples = _samples.concat([{ t: now, d: step }]).filter(s => s.t >= now - windowMs);
            _lastEventMs = now;
            _target = _eventTarget;
        }
        if (phase === Qt.ScrollEnd)
            lift(now);
    }

    // The fingers left the pad: glide on at the speed of their last windowMs
    function lift(now) {
        const speed = speedSince(now - windowMs);
        _samples = [];
        if (speed === 0)
            return;
        if (!frame.running) {
            _eventTarget = flickable.contentY;
            _lastTickMs = now;
            frame.running = true;
        }
        _glideSpeed = speed;
        _lastEventMs = now;
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

    // The content speed the events since `fromMs` add up to, zero when too slow to glide
    function speedSince(fromMs) {
        if (!glide)
            return 0;
        let sum = 0;
        for (const s of _samples)
            if (s.t >= fromMs)
                sum += s.d;
        // The content moves against the step
        const speed = Math.max(-maxSpeed, Math.min(maxSpeed, -sum / (windowMs / 1000)));
        return Math.abs(speed) < glideStartSpeed ? 0 : speed;
    }

    // How far the glide has carried the content past the lift, at nowMs
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
