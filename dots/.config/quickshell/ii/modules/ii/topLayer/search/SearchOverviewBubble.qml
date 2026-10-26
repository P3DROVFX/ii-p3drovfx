pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * The connect-mode overview, pulled out of the search drop as a second drop.
 *
 * The island's AuxiliaryBubbleSurface turned downwards. One linear clock drives the
 * opening through damped responses: a small pill hidden in the search's lower edge
 * travels out with a liquid neck still joining it to the search, the neck pinches off
 * as it reaches its place, and only then does it spread into the overview's card. The
 * resting pose is exact. A recall starts from the pose on screen and takes its own,
 * quicker path back (see `closeAmount`).
 *
 * Nothing here fades. The topLayer is blurred by the compositor with an `ignore_alpha`
 * threshold, and a fade sweeps every pixel's alpha across it: the blur behind the grid
 * switched on in one frame somewhere in the middle of the old entrance. The field and
 * the content mask both have hard edges, so a pixel is either the overview or nothing
 * and the blur moves with the edge.
 *
 * The overview is drawn hosted (no panel, shadow or margin of its own); this item paints
 * its panel colour and radius instead, so at rest it looks as it did. Children are the
 * overview's content, laid out at the overview's resting size.
 *
 * Geometry comes in the host's coordinates; `away` is +1 when the search grows down
 * from a top bar and -1 for a bottom bar.
 */
Item {
    id: root

    default property alias contents: contentHost.data

    /** The search is open, and the overview is wanted beside it. */
    property bool searchOpen: false
    property bool wanted: false
    /**
     * Out and settled beside the search, or tucked back into it. Derived here, so a
     * change reads `searchOpen` already updated: a tuck (a query took the drop, the
     * search stays) is told apart from the search closing.
     */
    readonly property bool open: root.searchOpen && root.wanted
    /** A gesture owns the clock: it follows the search's while the fingers hold it. */
    property bool held: false
    property real heldProgress: 0
    property bool animationsEnabled: true
    property int openDuration: 700
    property int closeDuration: 340
    /** A tuck while the search stays open: slower, so the recall reads as liquid. */
    property int tuckDuration: 440

    // The search drop: the body the overview hangs from.
    property real barEdgeY: 0
    property real away: 1
    property real searchCenterX: 0
    property real searchBodyWidth: 0
    property real searchHeight: 0
    property real searchRadius: 0
    /** Where the search will rest; the overview's place is measured from it. */
    property real searchRestHeight: 0
    property color searchColor: "black"

    // The overview at rest.
    property real overviewCenterX: 0
    property real overviewWidth: 0
    property real overviewHeight: 0
    property real overviewRadius: 0
    property real gap: 10
    property color panelColor: "black"

    // ── The clock ────────────────────────────────────────────────────────────
    property real clock: 0
    property bool opening: true
    readonly property bool active: root.open || root.clock > 0.001
    readonly property bool atRest: !root.held && !clockAnim.running && (root.clock <= 0 || root.clock >= 1)

    // Where a change of direction started, and the pose on screen at that moment.
    property real _fromClock: 0
    property real _fromWidth: 0
    property real _fromHeight: 0
    property real _fromRadius: 0
    property real _fromTop: 0
    property real _fromCenterX: 0
    property real _fromReveal: 0
    property real _fromRelease: 1
    property bool _tucking: false

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
        if (!root.open && root.clock <= 0.001)
            return;
        // The pose on screen, before the direction flips.
        const pose = [root.liveWidth, root.liveHeight, root.liveRadius, root.liveTop, root.liveCenterX,
            root.contentReveal, root.release];
        // Reopened while tucking away: pick up the opening where the card is as spread
        // as it still is, and blend the rest of the pose across.
        const share = (pose[0] - root.seedWidth) / Math.max(1, root.overviewWidth - root.seedWidth);
        const fromClock = !root.open ? root.clock : (root.clock <= 0.001 ? 0 : root.clockForSpread(share));
        // The mode and the snapshot change before the clock does, so no binding ever
        // reads the new clock against the old pose.
        root.opening = root.open;
        root._tucking = !root.open && root.searchOpen;
        root._fromClock = fromClock;
        root._fromWidth = pose[0];
        root._fromHeight = pose[1];
        root._fromRadius = pose[2];
        root._fromTop = pose[3];
        root._fromCenterX = pose[4];
        root._fromReveal = pose[5];
        root._fromRelease = pose[6];
        root.clock = fromClock;
        clockAnim.to = root.open ? 1 : 0;
        clockAnim.duration = Math.max(1, Math.round(root.open
            ? root.openDuration * (1 - root.clock)
            : (root._tucking ? root.tuckDuration : root.closeDuration) * Math.min(1, root.clock / 0.6)));
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
    function smoothstep(value) {
        const t = Math.max(0, Math.min(1, value));
        return t * t * (3 - 2 * t);
    }
    /** Fast out of the start, gentle at the end: what a recall wants. */
    function easeOut(value) {
        const t = Math.max(0, Math.min(1, value));
        return 1 - (1 - t) * (1 - t);
    }
    function stageAt(clock, start, end) {
        return root.smoothstep((clock - start) / (end - start));
    }
    function mix(from, to, amount) {
        return from + (to - from) * amount;
    }
    // A damped response normalised at the end point (see AuxiliaryBubbleSurface).
    // overshoot = exp(-pi * decay / frequency).
    function responseAt(clock, delay, decay, frequency) {
        const phase = decay / frequency;
        const time = Math.max(0, Math.min(1, clock) - delay);
        const end = 1 - delay;
        const value = 1 - Math.exp(-decay * time) * (Math.cos(frequency * time) + phase * Math.sin(frequency * time));
        const terminal = 1 - Math.exp(-decay * end) * (Math.cos(frequency * end) + phase * Math.sin(frequency * end));
        return value / terminal;
    }

    /** The pill it leaves the search as: a drop of the search's own width class. */
    readonly property real seedHeight: Math.min(root.overviewHeight, 40)
    readonly property real seedWidth: Math.min(root.overviewWidth, Math.max(140, root.searchBodyWidth * 0.5))

    /** Distance from the bar's edge to the drop's near edge. */
    readonly property real restTop: root.searchRestHeight + root.gap
    readonly property real startTop: root.searchHeight - root.seedHeight * 0.85

    // Opening, a pure function of the clock: grows out of nothing inside the search,
    // travels to its place about 2% past it, the neck lets go as it arrives, and the
    // card spreads once it is free.
    function spreadAt(clock) {
        return root.responseAt(clock, 0.3, 6.8, 5.8);
    }
    function clockForSpread(share) {
        if (share <= 0)
            return 0.3;
        let low = 0.3;
        let high = 1;
        for (let step = 0; step < 14; step++) {
            const middle = (low + high) / 2;
            if (root.spreadAt(middle) < share)
                low = middle;
            else
                high = middle;
        }
        return (low + high) / 2;
    }
    readonly property real openAppear: root.stageAt(root.clock, 0, 0.14)
    readonly property real openTravel: root.responseAt(root.clock, 0.02, 6.6, 5.6)
    readonly property real openSpread: root.spreadAt(root.clock)

    /** 0 → 1 over a reopening's first stretch, blending from the pose that was there. */
    readonly property real reopenBlend: root._fromClock > 0
        ? root.smoothstep((root.clock - root._fromClock) / 0.2) : 1

    /**
     * 0 → 1 over a recall. It does not retrace the opening: the spread settles well
     * before the clock ends, so running it backwards held the card still for a tenth
     * of a second before anything moved. The recall starts at once - the contents
     * close and the card draws in to the pill - then the pill slips back into the
     * search and the neck forms again on the way.
     */
    readonly property real closeAmount: root.opening ? 0 : 1 - root.clock / Math.max(0.001, root._fromClock)
    // A tuck keeps every stage long enough to be seen: the contents close with the
    // card instead of ahead of it, and the neck forms while the pill is still on its
    // way back, so the search drinks it in rather than it blinking out.
    readonly property real closeShrink: root.easeOut(root.closeAmount / (root._tucking ? 0.62 : 0.55))
    readonly property real closeBack: root._tucking
        ? root.smoothstep((root.closeAmount - 0.2) / 0.65)
        : root.smoothstep((root.closeAmount - 0.3) / 0.6)
    readonly property real closeVanish: root._tucking
        ? root.smoothstep((root.closeAmount - 0.7) / 0.3)
        : root.smoothstep((root.closeAmount - 0.75) / 0.25)

    readonly property real liveTop: root.opening
        ? root.mix(root._fromTop, root.mix(root.startTop, root.restTop, root.openTravel), root.reopenBlend)
        : root.mix(root._fromTop, root.startTop, root.closeBack)
    readonly property real liveCenterX: root.opening
        ? root.mix(root._fromCenterX, root.mix(root.searchCenterX, root.overviewCenterX, root.openTravel), root.reopenBlend)
        : root.mix(root._fromCenterX, root.searchCenterX, root.closeBack)
    readonly property real liveWidth: Math.max(0, root.opening
        ? root.mix(root._fromWidth, root.mix(root.seedWidth, root.overviewWidth, root.openSpread) * root.openAppear, root.reopenBlend)
        : root.mix(root._fromWidth, root.seedWidth, root.closeShrink) * (1 - root.closeVanish))
    readonly property real liveHeight: Math.max(0, root.opening
        ? root.mix(root._fromHeight, root.mix(root.seedHeight, root.overviewHeight, root.openSpread) * root.openAppear, root.reopenBlend)
        : root.mix(root._fromHeight, root.seedHeight, root.closeShrink) * (1 - root.closeVanish))
    readonly property real liveRadius: Math.max(0, Math.min(root.opening
        ? root.mix(root._fromRadius, root.mix(root.seedHeight / 2, root.overviewRadius, root.openSpread), root.reopenBlend)
        : root.mix(root._fromRadius, root.seedHeight / 2, root.closeShrink),
        root.liveHeight / 2, root.liveWidth / 2))

    /** The neck lets go as the drop arrives, and forms again as it is called back. */
    readonly property real release: root.opening
        ? root.mix(root._fromRelease, root.stageAt(root.clock, 0.3, 0.5), root.reopenBlend)
        : root._fromRelease * (1 - (root._tucking
            ? root.smoothstep((root.closeAmount - 0.3) / 0.3)
            : root.smoothstep((root.closeAmount - 0.45) / 0.3)))

    /**
     * The contents open from the drop's middle as it spreads: a slice of the grid in
     * a travelling pill read as a clipped window, not as a drop. An inset, not a fade.
     */
    readonly property real contentReveal: root.opening
        ? root.mix(root._fromReveal, root.stageAt(root.clock, 0.26, 0.62), root.reopenBlend)
        : root._fromReveal * (1 - (root._tucking
            ? root.smoothstep(root.closeAmount / 0.55)
            : root.easeOut(root.closeAmount / 0.35)))
    readonly property real contentInset: (1 - root.contentReveal) * Math.max(root.liveWidth, root.liveHeight) / 2

    readonly property real neckBlend: {
        // Never thicker than the ends it joins: the largest blend whose joint stays
        // within the smaller end's radius (see AuxiliaryBubbleSurface.neckBlend).
        const bodyCap = Math.min(root.searchRadius, root.searchHeight / 2);
        const dropCap = Math.min(root.liveRadius, root.liveHeight / 2);
        const distance = Math.abs((root.liveTop + dropCap) - (root.searchHeight - bodyCap));
        const radius = Math.max(0, Math.min(bodyCap, dropCap));
        const flush = 4 * (Math.sqrt(radius * radius + distance * distance / 4) - radius);
        return Math.min(flush, root.seedHeight * 0.8) * (1 - root.release);
    }

    visible: root.clock > 0.001 && root.liveHeight > 0.25

    // ── The surface ──────────────────────────────────────────────────────────
    /** Room for the neck and the overshoot around both shapes. */
    readonly property real bleed: 32

    function premultiplied(color) {
        return Qt.vector4d(color.r * color.a, color.g * color.a, color.b * color.a, color.a);
    }

    ShaderEffect {
        id: field
        // A frame whose y grows away from the bar; flipped for a bottom bar.
        readonly property real spanLeft: Math.min(root.searchCenterX - root.searchBodyWidth / 2,
            root.overviewCenterX - root.overviewWidth / 2) - root.bleed
        readonly property real spanRight: Math.max(root.searchCenterX + root.searchBodyWidth / 2,
            root.overviewCenterX + root.overviewWidth / 2) + root.bleed
        x: Math.floor(spanLeft)
        width: Math.ceil(spanRight - x)
        height: Math.ceil(Math.max(root.restTop + root.overviewHeight * 1.05,
            root.liveTop + root.liveHeight) + root.bleed)
        y: root.away > 0 ? root.barEdgeY : root.barEdgeY - height
        transform: Scale {
            yScale: root.away > 0 ? 1 : -1
            origin.y: field.height / 2
        }

        property vector2d resolution: Qt.vector2d(width, height)
        property vector4d bodyColor: root.premultiplied(root.searchColor)
        property vector4d bubbleColor: root.premultiplied(root.panelColor)
        // The search reaches above the bar's edge, so only its lower corners count.
        readonly property real bodyReach: root.searchRadius * 2 + 4
        property vector4d bodyShape: Qt.vector4d(root.searchCenterX - x,
            (root.searchHeight - bodyReach) / 2, root.searchBodyWidth, root.searchHeight + bodyReach)
        property vector4d bubbleShape: Qt.vector4d(root.liveCenterX - x,
            root.liveTop + root.liveHeight / 2, root.liveWidth, root.liveHeight)
        property real bodyRadius: root.searchRadius
        property real bubbleRadius: root.liveRadius
        property real blend: root.neckBlend

        fragmentShader: Qt.resolvedUrl("shaders/overviewBubbleField.frag.qsb")
    }

    // ── The contents ─────────────────────────────────────────────────────────
    /**
     * Laid out at the resting size and carried by the drop's near edge, so the grid
     * arrives with it instead of being uncovered in place. The mask is a layer only
     * while the drop is moving; at rest the contents draw straight to the window.
     */
    Item {
        id: contentHost
        x: root.overviewCenterX - root.overviewWidth / 2
        y: root.away > 0 ? root.barEdgeY + root.liveTop : root.barEdgeY - root.liveTop - root.overviewHeight
        width: root.overviewWidth
        height: root.overviewHeight

        visible: root.contentReveal > 0
        layer.enabled: !root.atRest
        layer.effect: ShaderEffect {
            property vector2d resolution: Qt.vector2d(contentHost.width, contentHost.height)
            property vector4d box: Qt.vector4d(root.liveCenterX - contentHost.x,
                root.away > 0 ? root.liveHeight / 2 : root.overviewHeight - root.liveHeight / 2,
                Math.max(0, root.liveWidth - root.contentInset * 2), Math.max(0, root.liveHeight - root.contentInset * 2))
            property real radius: Math.max(0, root.liveRadius - root.contentInset * 0.5)
            fragmentShader: Qt.resolvedUrl("shaders/roundedRevealMask.frag.qsb")
        }
    }
}
