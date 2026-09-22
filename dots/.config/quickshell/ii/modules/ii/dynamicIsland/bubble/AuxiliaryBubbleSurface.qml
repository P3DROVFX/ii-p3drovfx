pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

/**
 * A second, round surface beside the island's body, joined to it by a liquid neck.
 *
 * A port of clavis' SpotlightModeMorphSurface, cut down to one bubble per instance.
 * One linear clock, `progress`, drives everything through damped responses: the bubble
 * travels out of the body with a slight overshoot and grows as it goes, and the liquid
 * neck joining it to the body stretches, thins and lets go. Every value is a pure
 * function of `progress`, so reversing the clock half way (the bubble called back before
 * it settled) retraces the same path, and the resting pose is exact.
 *
 * `side` mirrors the travel, and the body is whatever the bubble hangs from: the
 * island's own rounded box, or another bubble's live circle (a chain of these items
 * reads as one body pulling apart repeatedly). Only the neck and the bubble are drawn;
 * the host keeps drawing its own shapes on top (see bubbleField.frag). All inputs are
 * in the host window's coordinates.
 */
Item {
    id: root

    /** 0 = inside the island, 1 = settled beside it. Animate it linearly. */
    required property real progress

    // The body the bubble hangs from: the island's rounded box, or a parent bubble
    // drawn as a circle (mainWidth == mainHeight == mainRadius * 2).
    required property real mainCenterX
    required property real mainTop
    required property real mainWidth
    required property real mainHeight
    required property real mainRadius

    /** Which side of the body the bubble travels to: "right" or "left". */
    property string side: "right"
    readonly property bool toRight: root.side !== "left"

    /** Where the bubble's centre sits vertically, and its settled size. */
    required property real bubbleCenterY
    required property real diameter
    /**
     * The settled width: `diameter` for a circle, more for a pill. It may change while
     * the bubble is out (a pill growing to show a title); the inner edge stays put and
     * the pill grows away from the island.
     */
    property real bubbleWidth: root.diameter
    /**
     * The settled height: `diameter` for a circle or a pill, more while the bubble is
     * expanded into an island of its own. It grows downwards: the top edge stays on
     * the line the circle's top sits on.
     */
    property real bubbleHeight: root.diameter
    /** Corner radius; a circle and a pill round fully, an expanded bubble is a card. */
    property real bubbleRadius: root.bubbleHeight / 2
    /** Space between the body and the settled bubble. */
    required property real gap

    property color surfaceColor: "black"
    property bool shadowEnabled: false
    property color shadowColor: Qt.rgba(0, 0, 0, 0.45)

    // ── The motion ───────────────────────────────────────────────────────────
    readonly property real mainRight: root.mainCenterX + root.mainWidth / 2
    readonly property real mainLeft: root.mainCenterX - root.mainWidth / 2
    /** Radius of the body's end cap, which the neck grows from. */
    readonly property real mainCap: Math.min(root.mainRadius, root.mainHeight / 2)

    /**
     * The bubble leaves as a drop of the body itself: a full-sized circle starts inside
     * the body's end cap, so the first thing on screen is that end stretching out. A
     * waist forms, pinches off, and the drop springs to rest; only once it is free does
     * a pill widen outwards from it.
     *
     * It used to grow from nothing while it travelled, and a pill grew in proportion,
     * so it came out as a flat bar extruded from the body that snapped off and then
     * inflated on its own - never a piece of the island folding away.
     */
    readonly property real direction: root.toRight ? 1 : -1
    /** The circle's centre: concentric with the end cap, then resting beside the body. */
    readonly property real startX: root.toRight
        ? root.mainRight - root.diameter / 2
        : root.mainLeft + root.diameter / 2
    readonly property real circleEndX: root.startX + root.direction * (root.gap + root.diameter)
    /** The settled shape's centre; a pill's inner end is where the circle rests. */
    readonly property real endX: root.toRight
        ? root.mainRight + root.gap + root.bubbleWidth / 2
        : root.mainLeft - root.gap - root.bubbleWidth / 2
    readonly property real travel: root.response(0.06, 7.2, 8.9, 7.2 / 8.9)
    readonly property real growth: root.growthAt(root.progress)
    /** 0 = a circle, 1 = the full pill; the widening waits for the drop to be free. */
    readonly property real widen: root.widenAt(root.progress)

    /**
     * The earliest clock at which the bubble looks settled: the neck has let go, the
     * drop's spring is within a pixel or two and a pill has finished widening. Past it
     * the clock changes nothing on screen, so a recall starts here, not from 1.
     */
    readonly property real settledClock: root.bubbleWidth > root.diameter + 0.5 ? 0.8 : 0.55

    readonly property real circleX: root.startX + (root.circleEndX - root.startX) * root.travel
    /** The live height of the shape; a circle's diameter, a pill's thickness. */
    readonly property real bubbleDiameter: Math.max(0, root.diameter * root.growth)
    /** The live width: the circle, and whatever of the pill has widened out of it. */
    readonly property real bubbleShapeWidth: Math.max(0,
        root.bubbleDiameter + (root.bubbleWidth - root.diameter) * root.widen)
    readonly property real bubbleX: root.circleX + root.direction * (root.bubbleShapeWidth - root.bubbleDiameter) / 2
    readonly property real bubbleShapeHeight: Math.max(0, root.bubbleHeight * root.growth)
    /** The live shape's vertical centre: below the circle's own when the bubble is taller. */
    readonly property real bubbleShapeCenterY: root.bubbleCenterY + (root.bubbleShapeHeight - root.bubbleDiameter) / 2
    /** The live shape's top edge. */
    readonly property real bubbleTop: root.bubbleCenterY - root.bubbleDiameter / 2
    /** The bubble's outer edges, for whatever has to make room for it. */
    readonly property real bubbleRight: root.bubbleX + root.bubbleShapeWidth / 2
    readonly property real bubbleLeft: root.bubbleX - root.bubbleShapeWidth / 2

    /**
     * Nearly full size from the start - it is hidden in the cap until it moves - with a
     * small jelly overshoot around the moment the waist lets go.
     */
    function growthAt(clock) {
        return 0.55 + 0.45 * root.responseAt(clock, 0, 9, 9, 0);
    }
    function widenAt(clock) {
        return root.smoothstep((clock - 0.42) / 0.38);
    }

    /** The contents fade in once the bubble has mostly left, and out as it returns. */
    readonly property real contentProgress: root.stage(0.36, 0.55)

    /**
     * How far the neck has let go, when the host drives it by distance instead of by the
     * clock (-1: the clock's). A bubble riding the island's size is placed by how much of
     * it is out, and the earliest clock that far out is still joined on the clock's
     * schedule - the neck appeared in one frame.
     */
    property real releaseOverride: -1

    readonly property real neckBlend: {
        // The centre of the body's cap the neck grows from, on the side it travels to.
        const previousCenter = root.toRight ? root.mainRight - root.mainCap : root.mainLeft + root.mainCap;
        // A pill joins through its inner end cap, not its middle.
        const innerCap = root.bubbleX - root.direction * (root.bubbleShapeWidth - root.bubbleDiameter) / 2;
        const distance = Math.abs(innerCap - previousCenter);
        // Never thicker than the ends it joins. Two overlapping circles blended by k bulge
        // k/4 past their own radius at the joint, so while the drop was still half inside
        // the body the neck swelled into a blob taller than both. This is the largest
        // blend whose joint stays within the smaller radius; it is zero while the drop is
        // buried (no inflating body) and the full blend once the two only just touch.
        const radius = Math.min(root.mainCap, root.bubbleDiameter / 2);
        const flush = 4 * (Math.sqrt(radius * radius + distance * distance / 4) - radius);
        // A short fade after it has left, so it cannot reconnect on the way.
        const release = root.releaseOverride >= 0 ? root.releaseOverride : root.stage(0.27, 0.47);
        return Math.min(flush, Math.min(root.bubbleDiameter, root.diameter) * 0.78) * (1 - release);
    }

    function smoothstep(value) {
        const t = Math.max(0, Math.min(1, value));
        return t * t * (3 - 2 * t);
    }

    function stage(start, end) {
        return root.smoothstep((root.progress - start) / (end - start));
    }

    // A damped response normalised at the end point, so the final layout is exact and
    // an interrupted animation stays a pure function of the clock.
    function response(delay, decay, frequency, phase) {
        return root.responseAt(root.progress, delay, decay, frequency, phase);
    }

    function responseAt(clock, delay, decay, frequency, phase) {
        const time = Math.max(0, Math.min(1, clock) - delay);
        const end = 1 - delay;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency * time));
        const terminal = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency * end));
        return value / terminal;
    }

    /**
     * How much of the bubble is out: how far its far edge stands past the body's, as a
     * share of where it rests. This, not its size, is what the eye measures against
     * the island - the bubble grows while it is still inside the body, so half its size
     * is a bubble that has barely shown.
     */
    readonly property real restReach: root.gap + root.bubbleWidth
    function reachAt(clock) {
        const travel = root.responseAt(clock, 0.06, 7.2, 8.9, 7.2 / 8.9);
        const size = root.diameter * root.growthAt(clock);
        const width = size + (root.bubbleWidth - root.diameter) * root.widenAt(clock);
        const circle = -root.diameter / 2 + (root.gap + root.diameter) * travel;
        return (circle - size / 2 + width) / Math.max(1, root.restReach);
    }
    readonly property real reach: Math.max(0, Math.min(1, root.reachAt(root.progress)))

    /**
     * The clock at which that share of the bubble is out, for a host that wants the
     * bubble somewhere rather than at some time: the first clock that reaches it, found
     * by a coarse scan (the drop's spring and the pill's widening overlap, so the reach
     * is not one steady rise) and refined by bisection inside that step.
     */
    function clockForReach(share) {
        if (share <= 0)
            return 0;
        const steps = 32;
        let low = 0;
        let high = 1;
        for (let step = 1; step <= steps; step++) {
            if (root.reachAt(step / steps) >= share) {
                low = (step - 1) / steps;
                high = step / steps;
                break;
            }
        }
        for (let step = 0; step < 10; step++) {
            const middle = (low + high) / 2;
            if (root.reachAt(middle) < share)
                low = middle;
            else
                high = middle;
        }
        return (low + high) / 2;
    }

    // ── Where the field is drawn ─────────────────────────────────────────────
    /**
     * Only the body's end cap and the bubble's travel, never the body itself.
     *
     * Nothing is drawn under the body (the shader cuts it away), so the field only has
     * to reach far enough into it for the neck to join. It used to span half the body
     * at the body's full height, which is nothing for a pill and most of the screen for
     * the launcher: a bubble called back as search opened had its field - and the
     * shadow pass over it - resized to a new, larger texture on every frame of the
     * island's growth. Sized to the bubble, it stays the same few dozen pixels whatever
     * the island becomes.
     */
    readonly property real bleed: 24
    readonly property real innerReach: Math.min(root.mainWidth / 2,
        Math.max(root.mainCap, root.diameter) + root.bleed)
    x: root.toRight ? Math.floor(root.mainRight - root.innerReach)
        : Math.ceil(root.mainLeft + root.innerReach) - root.width
    y: Math.floor(root.bubbleCenterY - root.diameter - root.bleed)
    width: Math.ceil(root.innerReach + root.gap + root.bubbleWidth * 1.1 + root.diameter * 0.3 + root.bleed)
    height: Math.ceil(Math.max(root.bubbleCenterY + root.diameter,
        root.bubbleCenterY - root.diameter / 2 + root.bubbleHeight * 1.1)
        + root.bleed - root.y)
    visible: root.progress > 0.001

    /**
     * The field is the island's own surface, translucency included.
     *
     * Painted at full alpha it was a solid slab next to a see-through island - the
     * bubble read as black - and the 1.5 px the shader tucks under the body (so the
     * neck joins without a seam) showed through it as a dark rim, ending at the
     * island's centre because the field is only drawn on the bubble's half.
     *
     * The alpha therefore rides on the ShaderEffect, as it already does on the shadow
     * pass, and a see-through body asks the shader to cut at its edge instead of
     * beneath it (`bodyCut` 0: it subtracts the body's coverage, which leaves exactly
     * nothing under the island). An opaque body keeps the tuck, where it is invisible
     * and is what makes the neck seamless.
     */
    readonly property real bodyCut: root.surfaceColor.a >= 0.999 ? 1.5 : 0

    ShaderEffect {
        id: field
        anchors.fill: parent
        visible: !root.shadowEnabled
        // The shadow pass fades the whole thing by the same alpha, so the field must
        // not also carry it there - it would be applied twice.
        opacity: root.shadowEnabled ? 1 : root.surfaceColor.a

        property vector2d resolution: Qt.vector2d(width, height)
        property color fillColor: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 1)
        property vector4d mainShape: Qt.vector4d(root.mainCenterX - root.x, root.mainTop + root.mainHeight / 2 - root.y,
            root.mainWidth, root.mainHeight)
        property vector4d bubbleShape: Qt.vector4d(root.bubbleX - root.x, root.bubbleShapeCenterY - root.y,
            root.bubbleShapeWidth, root.bubbleShapeHeight)
        property real bubbleRadius: root.bubbleRadius * root.growth
        property real mainRadius: root.mainRadius
        property real blend: root.neckBlend
        property real bodyCut: root.bodyCut

        fragmentShader: Qt.resolvedUrl("shaders/bubbleField.frag.qsb")
    }

    // The shadow pass only exists while the island draws one: a hidden MultiEffect still
    // keeps its source rendered into a layer.
    Loader {
        anchors.fill: field
        active: root.shadowEnabled
        sourceComponent: MultiEffect {
            source: field
            opacity: root.surfaceColor.a
            autoPaddingEnabled: true
            shadowEnabled: true
            shadowColor: root.shadowColor
            shadowBlur: 1.8
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
        }
    }
}
