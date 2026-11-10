pragma ComponentBehavior: Bound

import QtQuick

/**
 * The connect-mode search drop, pulled out of the bar as liquid.
 *
 * Same principle as the island's AuxiliaryBubbleSurface: one linear clock drives the
 * shape through damped responses, and the shader joins it to the bar with a round
 * union. Opening, the drop is already a wide card - most of its width, slightly
 * softer corners - hanging from the bar through a thicker neck; it lengthens, spreads
 * to its full width and the neck thins to the resting shoulders. The responses barely
 * overshoot: it should flow into place, not bounce.
 *
 * Closing does not retrace the opening (its little overshoot would inflate the drop on
 * the way out): the live shape is snapshotted and eased back into the bar, drawing in
 * a little at the sides as it goes. A change of direction mid-way starts from the
 * shape on screen.
 *
 * Coordinates: y = 0 is the bar's edge and the drop grows towards +y; the host flips
 * the item for a bottom bar. The resting shape is exactly the old Notch: `targetWidth`
 * includes the two shoulders of `shoulderRadius`.
 */
Item {
    id: root

    property bool open: false
    /** A gesture owns the clock; `heldProgress` is where the fingers are. */
    property bool held: false
    property real heldProgress: 0
    property bool animationsEnabled: true
    property int openDuration: 600
    property int closeDuration: 360

    property real targetWidth: 0
    property real targetHeight: 0
    property real shoulderRadius: 18
    property real cornerRadius: 18
    property color surfaceColor: "black"

    // ── The clock ────────────────────────────────────────────────────────────
    property real clock: 0
    property bool opening: true
    readonly property bool active: root.open || root.clock > 0.001
    readonly property bool morphing: clockAnim.running || root.held

    // Where a change of direction started, and the shape on screen at that moment.
    property real _fromClock: 0
    property real _fromHeight: 0
    property real _fromWidth: 0
    property real _fromBulge: 0
    property real _fromFillet: 0
    property real _fromContent: 0

    onOpenChanged: root._restart()
    onHeldChanged: {
        if (root.held) {
            clockAnim.stop();
            root.opening = true;
            root._fromClock = 0;
        } else {
            root._restart();
        }
    }

    function _restart() {
        if (root.held)
            return;
        clockAnim.stop();
        if (!root.animationsEnabled) {
            root.opening = root.open;
            root._fromClock = 0;
            root.clock = root.open ? 1 : 0;
            return;
        }
        // The shape on screen, before the direction flips.
        const height = root.liveHeight;
        const width = root.liveBodyWidth;
        const bulge = root.liveBulge;
        const fillet = root.liveFillet;
        const content = root.contentOpacity;
        if (!root.open && root.clock <= 0.001)
            return;
        // Reopened while closing: pick up the opening where it is as tall as the drop
        // already is, and blend the rest of the shape across.
        const fromClock = !root.open ? root.clock
            : (root.clock <= 0.001 ? 0 : root.clockForHeight(height / Math.max(1, root.targetHeight)));
        // The mode and the snapshot change before the clock does, so no binding ever
        // reads the new clock against the old shape.
        root.opening = root.open;
        root._fromClock = fromClock;
        root._fromHeight = height;
        root._fromWidth = width;
        root._fromBulge = bulge;
        root._fromFillet = fillet;
        root._fromContent = content;
        root.clock = fromClock;
        clockAnim.to = root.open ? 1 : 0;
        clockAnim.duration = Math.max(1, Math.round(root.open
            ? root.openDuration * (1 - root.clock)
            : root.closeDuration * root.clock));
        clockAnim.start();
    }

    NumberAnimation {
        id: clockAnim
        target: root
        property: "clock"
        easing.type: Easing.Linear
    }

    Binding {
        target: root
        property: "clock"
        value: Math.max(0, Math.min(1, root.heldProgress))
        when: root.held
        restoreMode: Binding.RestoreNone
    }

    // ── The motion ───────────────────────────────────────────────────────────
    readonly property real bodyWidth: Math.max(0, root.targetWidth - root.shoulderRadius * 2)
    /** The width the drop starts at, and is reabsorbed at: a card, not a bead. */
    readonly property real seedWidth: root.bodyWidth * 0.78

    function smoothstep(value) {
        const t = Math.max(0, Math.min(1, value));
        return t * t * (3 - 2 * t);
    }

    // A damped response normalised at the end point, so the resting shape is exact and
    // the clock alone decides the pose. overshoot = exp(-pi * decay / frequency).
    function responseAt(clock, delay, decay, frequency) {
        const phase = decay / frequency;
        const time = Math.max(0, Math.min(1, clock) - delay);
        const end = 1 - delay;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency * time));
        const terminal = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency * end));
        return value / terminal;
    }

    // Opening: length first, about 2% past rest; the widening trails it by a beat with
    // about 3%; the softer corners and thick neck settle once it has widened.
    function openHeightAt(clock) {
        return root.responseAt(clock, 0, 6.8, 5.6);
    }
    function openWidenAt(clock) {
        return root.responseAt(clock, 0.08, 6.4, 5.8);
    }
    function openSettleAt(clock) {
        return root.smoothstep((clock - 0.1) / 0.55);
    }
    function clockForHeight(share) {
        if (share <= 0)
            return 0;
        let low = 0;
        let high = 1;
        for (let step = 1; step <= 24; step++) {
            if (root.openHeightAt(step / 24) >= share) {
                low = (step - 1) / 24;
                high = step / 24;
                break;
            }
        }
        for (let step = 0; step < 10; step++) {
            const middle = (low + high) / 2;
            if (root.openHeightAt(middle) < share)
                low = middle;
            else
                high = middle;
        }
        return (low + high) / 2;
    }

    /** 0 → 1 over a close, from where it started. */
    readonly property real closeAmount: root.opening ? 0 : 1 - root.clock / Math.max(0.001, root._fromClock)
    /** 0 → 1 over a reopening's first stretch, blending from the shape that was there. */
    readonly property real reopenBlend: root.opening && root._fromClock > 0
        ? root.smoothstep((root.clock - root._fromClock) / 0.25) : 1

    function mix(from, to, amount) {
        return from + (to - from) * amount;
    }

    readonly property real liveHeight: {
        if (!root.opening) {
            // Moves from the first frame and lands gently in the bar. The old curve
            // started at zero speed and held the drop still for its first frames,
            // which read as a slow close.
            return root._fromHeight * Math.pow(1 - root.closeAmount, 1.7);
        }
        return root.mix(root._fromHeight, root.targetHeight * root.openHeightAt(root.clock), root.reopenBlend);
    }
    readonly property real liveBodyWidth: {
        if (!root.opening) {
            const narrow = root.smoothstep(root.closeAmount / 0.6);
            return root.mix(root._fromWidth, Math.min(root._fromWidth, root.seedWidth), narrow);
        }
        const open = root.seedWidth + (root.bodyWidth - root.seedWidth) * root.openWidenAt(root.clock);
        return root.mix(root._fromWidth, open, root.reopenBlend);
    }
    /** 1 = just pulled out: softer corners and a thicker neck; 0 = the resting card. */
    readonly property real liveBulge: {
        if (!root.opening)
            return root.mix(root._fromBulge, 1, root.smoothstep(root.closeAmount / 0.55));
        return root.mix(root._fromBulge, 1 - root.openSettleAt(root.clock), root.reopenBlend);
    }
    readonly property real liveCornerRadius: Math.max(0, root.cornerRadius * (1 + 0.6 * root.liveBulge))
    /**
     * The neck: the resting shoulder, thicker while the drop is pulled out. Never deeper
     * than the drop is long, or the fillet would hang below it as a blob.
     */
    readonly property real liveFillet: Math.max(0, Math.min(
        root.shoulderRadius * (1 + 0.5 * root.liveBulge),
        root.liveHeight * 0.8,
        root.liveBodyWidth * 0.5))

    readonly property real contentOpacity: {
        if (!root.opening)
            return root._fromContent * (1 - root.smoothstep(root.closeAmount / 0.3));
        return root.mix(root._fromContent, root.smoothstep((root.clock - 0.2) / 0.38), root.reopenBlend);
    }

    /** What is on screen, for the host's clip, mask and blur exclusion. */
    readonly property real visibleHeight: Math.max(0, root.liveHeight)
    readonly property real visibleWidth: Math.max(0, root.liveBodyWidth + root.liveFillet * 2)

    // ── Where the field is drawn ─────────────────────────────────────────────
    /** Room for the overshoot and the thick neck around the resting shape. */
    readonly property real bleed: 48
    readonly property real centerX: root.width / 2

    visible: root.clock > 0.001 && root.liveHeight > 0.25

    ShaderEffect {
        id: field
        x: -root.bleed
        width: root.width + root.bleed * 2
        height: Math.ceil(Math.max(root.targetHeight, root.liveHeight) * 1.08 + root.bleed)
        // The alpha rides on the effect, as on the island's bubble, so the colour can
        // go in opaque.
        opacity: root.surfaceColor.a

        property vector2d resolution: Qt.vector2d(width, height)
        property color fillColor: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 1)
        // The box reaches well above the edge, so only its bottom corners are seen.
        readonly property real reachAbove: root.liveCornerRadius * 2 + 4
        property vector4d box: Qt.vector4d(root.centerX + root.bleed,
            (root.liveHeight - reachAbove) / 2,
            root.liveBodyWidth, root.liveHeight + reachAbove)
        property real boxRadius: root.liveCornerRadius
        property real fillet: root.liveFillet

        fragmentShader: Qt.resolvedUrl("shaders/searchDropField.frag.qsb")
    }
}
