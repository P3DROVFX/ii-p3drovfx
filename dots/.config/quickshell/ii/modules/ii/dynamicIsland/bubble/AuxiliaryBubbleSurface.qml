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
        ? root.mainRight + root.gap + root.diameter / 2
        : root.mainLeft - root.gap - root.diameter / 2
    readonly property real travel: root.response(0.06, 7.2, 8.9, 7.2 / 8.9)
    readonly property real growth: root.response(0, 3.8, 3.8, 0)

    readonly property real bubbleX: root.startX + (root.endX - root.startX) * root.travel
    readonly property real bubbleDiameter: Math.max(0, root.diameter * root.growth)
    /** The bubble's outer edges, for whatever has to make room for it. */
    readonly property real bubbleRight: root.bubbleX + root.bubbleDiameter / 2
    readonly property real bubbleLeft: root.bubbleX - root.bubbleDiameter / 2

    /** The contents fade in once the bubble has mostly left, and out as it returns. */
    readonly property real contentProgress: root.stage(0.36, 0.55)

    readonly property real neckBlend: {
        // The centre of the body's cap the neck grows from, on the side it travels to.
        const previousCenter = root.toRight ? root.mainRight - root.mainCap : root.mainLeft + root.mainCap;
        const radii = (2 * root.mainCap + root.bubbleDiameter) / 2;
        const separation = radii > 0 ? Math.abs(root.bubbleX - previousCenter) / radii : 0;
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
    // Only the travelled half of the body and the bubble's travel: a field over the
    // whole window would be shaded on every frame the island redraws.
    readonly property real bleed: 24
    x: root.toRight ? Math.floor(root.mainCenterX) : Math.ceil(root.mainCenterX) - root.width
    y: Math.floor(Math.min(root.mainTop, root.bubbleCenterY - root.diameter) - root.bleed)
    width: Math.ceil(root.mainWidth / 2 + root.gap + root.diameter * 1.4 + root.bleed)
    height: Math.ceil(Math.max(root.mainTop + root.mainHeight, root.bubbleCenterY + root.diameter) + root.bleed - root.y)
    visible: root.progress > 0.001

    ShaderEffect {
        id: field
        anchors.fill: parent
        visible: !root.shadowEnabled

        property vector2d resolution: Qt.vector2d(width, height)
        property color fillColor: Qt.rgba(root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, 1)
        property vector4d mainShape: Qt.vector4d(root.mainCenterX - root.x, root.mainTop + root.mainHeight / 2 - root.y,
            root.mainWidth, root.mainHeight)
        property vector4d bubbleShape: Qt.vector4d(root.bubbleX - root.x, root.bubbleCenterY - root.y,
            root.bubbleDiameter, root.bubbleDiameter)
        property real mainRadius: root.mainRadius
        property real blend: root.neckBlend

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
