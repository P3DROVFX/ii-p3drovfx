pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * One auxiliary bubble: its slot, its clock, its shape, its contents and its hit target.
 *
 * The decision of *whether* this bubble is out comes from the host as plain state;
 * everything about *how* it leaves and comes back lives here, so any number of slots
 * can share one implementation without a second copy of the morph.
 *
 * The bubble hangs off the island's body (`parentBubble` null), or off another bubble's
 * live circle - the case where more activities are out than there are sides. The clock
 * is the surface's: linear, reversible, every pose a pure function of it.
 */
Item {
    id: bubble

    // ── The slot (static per index) ──────────────────────────────────────────
    /** The Repeater's slot number: it fixes the side and the chain position. */
    required property int index
    /** "right" or "left": the side of the body this slot travels to. */
    required property string side
    /** The bubble this one chains out of; null when the island's body is the anchor. */
    property AuxiliaryBubble parentBubble: null

    // ── What the host says ───────────────────────────────────────────────────
    /** The activity assigned to this slot; "" when the slot is empty. */
    required property string activityId
    required property bool enabledState
    required property bool islandHidden
    required property bool expanded
    required property bool searchActive
    required property bool dashboardActive
    /** The activity the island is showing: the one holding a bubble back. */
    required property string pagedId
    /** The activity a pointer opened from a bubble; keeps its hit target alive. */
    required property string claimedActivity

    /** Sizes and anchors, in the host window's coordinates. */
    required property real diameter
    required property real gap
    /** The height line a body-hung bubble rests on. */
    required property real centerY
    required property real bodyCenterX
    required property real bodyTop
    required property real bodyWidth
    required property real bodyHeight
    required property real bodyRadius
    /** The island's reserved edges, so the bar's clearances measure against them. */
    required property real reservedRight
    required property real reservedLeft
    required property color surfaceColor
    required property bool shadowEnabled

    /** The pointer opened this bubble's activity in the island. */
    signal opened(string activityId)
    /** The pointer entered or left this bubble's hit target. */
    signal pointerChanged(bool over)
    /** This bubble's reach past its side's reserved edge, live. */
    signal reachChanged(real right, real left)
    /** The bubble just finished coming home: the island takes the hit. */
    signal absorbed()

    readonly property AuxiliaryBubbleSurface view: surface
    /** The mask entry for the hit target; empty while the bubble is away. */
    readonly property Region maskRegion: region

    // ── Wanted, shown, and the one clock ─────────────────────────────────────
    /** A chained bubble waits for its parent to be out: it hangs from its circle. */
    readonly property bool anchorReady: bubble.parentBubble === null || bubble.parentBubble.shown
    readonly property bool wanted: bubble.enabledState && bubble.activityId !== "" && bubble.pagedId !== bubble.activityId && !bubble.islandHidden && !bubble.expanded && !bubble.searchActive && !bubble.dashboardActive && bubble.anchorReady

    /**
     * What the bubble is drawing. It outlives `activityId` for as long as the bubble is
     * going back in, and a different activity only comes out once the old one is home.
     */
    property string shownId: ""
    readonly property bool shown: bubble.wanted && bubble.shownId === bubble.activityId

    function syncShown() {
        if (bubble.progress <= 0)
            bubble.shownId = bubble.wanted ? bubble.activityId : "";
    }
    onWantedChanged: bubble.syncShown()
    onActivityIdChanged: bubble.syncShown()

    /**
     * The morph's one clock, linear as in the reference: the surface shapes it into the
     * travel, the growth and the neck. A reversal runs for the distance left, so calling
     * the bubble back half way takes half the time.
     */
    property real progress: 0
    readonly property int morphMs: Math.round(620 * Appearance.animMultiplier)
    NumberAnimation {
        id: travel
        target: bubble
        property: "progress"
        easing.type: Easing.Linear
    }
    onShownChanged: {
        const target = bubble.shown ? 1 : 0;
        travel.stop();
        travel.from = bubble.progress;
        travel.to = target;
        travel.duration = Math.max(1, bubble.morphMs * Math.abs(target - bubble.progress));
        travel.start();
    }
    property bool _wasOut: false
    onProgressChanged: {
        bubble.syncShown();
        // The absorbed beat is the clock bottoming out on a way home. A bubble that
        // never got far enough out to be seen is not a hit worth answering.
        if (bubble.progress > 0.5) {
            bubble._wasOut = true;
        } else if (bubble.progress <= 0.001 && bubble._wasOut && !bubble.shown) {
            bubble._wasOut = false;
            bubble.absorbed();
        }
    }

    // ── The anchor: the body, or the parent bubble's live circle ─────────────
    readonly property real anchorCenterX: bubble.parentBubble === null ? bubble.bodyCenterX : bubble.parentBubble.view.bubbleX
    readonly property real anchorCenterY: bubble.parentBubble === null ? bubble.centerY : bubble.parentBubble.view.bubbleCenterY
    readonly property real anchorTop: bubble.parentBubble === null ? bubble.bodyTop : bubble.parentBubble.view.bubbleCenterY - bubble.parentBubble.view.bubbleDiameter / 2
    readonly property real anchorWidth: bubble.parentBubble === null ? bubble.bodyWidth : bubble.parentBubble.view.bubbleDiameter
    readonly property real anchorHeight: bubble.parentBubble === null ? bubble.bodyHeight : bubble.parentBubble.view.bubbleDiameter
    readonly property real anchorRadius: bubble.parentBubble === null ? bubble.bodyRadius : bubble.parentBubble.view.bubbleDiameter / 2

    // The shape, beneath the body drawn over it.
    AuxiliaryBubbleSurface {
        id: surface
        progress: bubble.progress
        side: bubble.side
        mainCenterX: bubble.anchorCenterX
        mainTop: bubble.anchorTop
        mainWidth: bubble.anchorWidth
        mainHeight: bubble.anchorHeight
        mainRadius: bubble.anchorRadius
        bubbleCenterY: bubble.anchorCenterY
        diameter: bubble.diameter
        gap: bubble.gap
        surfaceColor: bubble.surfaceColor
        shadowEnabled: bubble.shadowEnabled
    }

    // The glance itself, fading in once the bubble has mostly left.
    AuxiliaryBubbleContent {
        x: surface.bubbleX - width / 2
        y: surface.bubbleCenterY - height / 2
        activityId: bubble.shownId
        diameter: bubble.diameter
        visible: bubble.shownId !== "" && opacity > 0
        opacity: surface.contentProgress
        scale: 0.6 + 0.4 * surface.contentProgress
    }

    /**
     * Where the settled bubble sits. It stays while the island is open from it, even
     * though the bubble has gone back in: the pointer is still here, and losing it
     * would close the island it just opened.
     */
    Item {
        id: hit
        readonly property bool live: (bubble.shown && bubble.progress > 0.5) || (bubble.claimedActivity !== "" && bubble.claimedActivity === bubble.activityId)
        x: surface.endX - bubble.diameter / 2
        y: surface.bubbleCenterY - bubble.diameter / 2
        width: hit.live ? bubble.diameter : 0
        height: hit.live ? bubble.diameter : 0

        HoverHandler {
            id: hover
            enabled: hit.live
            onHoveredChanged: {
                bubble.pointerChanged(hover.hovered);
                if (hover.hovered && bubble.shown && bubble.shownId !== "")
                    bubble.opened(bubble.shownId);
            }
        }
    }

    Region {
        id: region
        item: hit
    }

    // Reach, live: the bar widens its gap for whatever of the travel is on screen.
    readonly property real reachRight: bubble.side === "right" && surface.visible ? Math.max(0, Math.ceil(surface.bubbleRight - bubble.reservedRight)) : 0
    readonly property real reachLeft: bubble.side !== "right" && surface.visible ? Math.max(0, Math.ceil(bubble.reservedLeft - surface.bubbleLeft)) : 0
    onReachRightChanged: bubble.reachChanged(bubble.reachRight, bubble.reachLeft)
    onReachLeftChanged: bubble.reachChanged(bubble.reachRight, bubble.reachLeft)
}
