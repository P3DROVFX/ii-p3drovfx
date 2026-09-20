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

    // Out of the body's rounded end and away to its side; the same response the
    // reference uses for a button travelling out of its neighbour, mirrored by `side`.
    readonly property real startX: root.toRight
        ? root.mainRight - root.diameter / 2
        : root.mainLeft + root.diameter / 2
    readonly property real endX: root.toRight
        ? root.mainRight + root.gap + root.bubbleWidth / 2
        : root.mainLeft - root.gap - root.bubbleWidth / 2
    readonly property real travel: root.response(0.06, 7.2, 8.9, 7.2 / 8.9)
    readonly property real growth: root.response(0, 3.8, 3.8, 0)

    readonly property real bubbleX: root.startX + (root.endX - root.startX) * root.travel
    /** The live height of the shape; a circle's diameter, a pill's thickness. */
    readonly property real bubbleDiameter: Math.max(0, root.diameter * root.growth)
    /** The live width: a pill grows in proportion, so it rounds off exactly like a circle. */
    readonly property real bubbleShapeWidth: Math.max(0, root.bubbleWidth * root.growth)
    readonly property real bubbleShapeHeight: Math.max(0, root.bubbleHeight * root.growth)
    /** The live shape's vertical centre: below the circle's own when the bubble is taller. */
    readonly property real bubbleShapeCenterY: root.bubbleCenterY + (root.bubbleShapeHeight - root.bubbleDiameter) / 2
    /** The live shape's top edge. */
    readonly property real bubbleTop: root.bubbleCenterY - root.bubbleDiameter / 2
    /** The bubble's outer edges, for whatever has to make room for it. */
    readonly property real bubbleRight: root.bubbleX + root.bubbleShapeWidth / 2
    readonly property real bubbleLeft: root.bubbleX - root.bubbleShapeWidth / 2

    /** The contents fade in once the bubble has mostly left, and out as it returns. */
    readonly property real contentProgress: root.stage(0.36, 0.55)

    readonly property real neckBlend: {
        // The centre of the body's cap the neck grows from, on the side it travels to.
        const previousCenter = root.toRight ? root.mainRight - root.mainCap : root.mainLeft + root.mainCap;
        const radii = (2 * root.mainCap + root.bubbleDiameter) / 2;
        // A pill joins through its inner end cap, not its middle.
        const innerCap = root.bubbleX + (root.toRight ? -1 : 1) * (root.bubbleShapeWidth - root.bubbleDiameter) / 2;
        const separation = radii > 0 ? Math.abs(innerCap - previousCenter) / radii : 0;
        // No neck while the bubble is still buried in the body, or the body would
        // inflate as it emerges; and a short fade after it has left, so it cannot
        // reconnect on the way.
        const exposed = root.smoothstep((separation - 0.5) / 0.5);
        const release = root.stage(0.27, 0.47);
        return Math.min(root.bubbleDiameter, root.diameter) * 0.78 * exposed * (1 - release);
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
        const time = Math.max(0, Math.min(1, root.progress) - delay);
        const end = 1 - delay;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency * time));
        const terminal = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency * end));
        return value / terminal;
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
