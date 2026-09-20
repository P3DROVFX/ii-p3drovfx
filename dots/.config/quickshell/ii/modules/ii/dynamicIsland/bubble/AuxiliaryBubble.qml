pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

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
    /** The activity whose bubble is expanded, anywhere; "" when none is. */
    required property string expandedBubbleId
    /**
     * Whether a bubble may expand now. One thing expands at a time: not while the
     * island itself is expanded, searching or showing the dashboard, and not while
     * another bubble is open.
     */
    required property bool mayExpand

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

    /** The pointer rested on this bubble: it asks to expand into an island of its own. */
    signal expandRequested(string activityId)
    /** The pointer left the expanded bubble: it asks to fold back. */
    signal collapseRequested(string activityId)
    /** The pointer entered or left this bubble's hit target. */
    signal pointerChanged(bool over)
    /** This bubble's reach past its side's reserved edge, live. */
    signal reachChanged(real right, real left)

    readonly property AuxiliaryBubbleSurface view: surface
    /** The mask entry for the hit target; empty while the bubble is away. */
    readonly property Region maskRegion: region

    // ── Wanted, shown, and the one clock ─────────────────────────────────────
    /** A chained bubble waits for its parent to be out: it hangs from its circle. */
    readonly property bool anchorReady: bubble.parentBubble === null || bubble.parentBubble.shown
    readonly property bool wanted: bubble.enabledState && bubble.activityId !== ""
        && bubble.pagedId !== bubble.activityId
        && !bubble.islandHidden && !bubble.expanded
        && !bubble.searchActive && !bubble.dashboardActive
        && bubble.anchorReady

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
        // A recalled bubble drops its own pointer claim: its hit target disables
        // the moment `shown` flips, and a `hovered=false` lost in that transition
        // would leave `anyBubbleHovered` stuck and veto the island's retraction
        // with the bubble frozen half-out at the edge. `noteBubblePointer`
        // deduplicates, so this is safe to fire even when nothing was hovered.
        if (!bubble.shown) {
            bubble.pointerChanged(false);
            bubble.holdPending = false;
        }
        const target = bubble.shown ? 1 : 0;
        travel.stop();
        travel.from = bubble.progress;
        travel.to = target;
        travel.duration = Math.max(1, bubble.morphMs * Math.abs(target - bubble.progress));
        travel.start();
    }
    onProgressChanged: bubble.syncShown()

    // ── Expanded: an island of its own ───────────────────────────────────────
    /**
     * Resting on a bubble opens it into an island-style card beside the island, not
     * the island itself. It grows away from the island - outwards, and down from its
     * own top edge - pushing everything on that side, and hosts the activity's own
     * expanded face (the same widget the island shows expanded).
     */
    readonly property bool isExpanded: bubble.shown && bubble.shownId !== ""
        && bubble.expandedBubbleId === bubble.shownId
    readonly property real expandedWidth: IslandRegistry.widthFor(bubble.shownId, "expanded")
    /**
     * The card's height: what the face asks for, when it can say.
     *
     * A descriptor's height has to cover the worst case - four agents, a long transfer
     * list - so a face that usually holds one row was drawn on a card half of which was
     * empty. A face declaring `preferredExpandedHeight` gets exactly that instead. It
     * has to derive that number from its own content and never from the card it is
     * given, or the two chase each other.
     */
    property real facePreferredHeight: 0
    readonly property real expandedHeight: bubble.facePreferredHeight > 0
        ? bubble.facePreferredHeight : IslandRegistry.heightFor(bubble.shownId, "expanded")
    readonly property bool canExpand: IslandRegistry.hasExpanded(bubble.shownId)

    /** Hover time before a bubble opens: the island's own, hold to reveal included. */
    readonly property int dwellMs: IslandPolicy.revealDwellMs

    /**
     * The hold, answered.
     *
     * A wait the surface does not acknowledge reads as a dead target: the pointer rests
     * on a bubble that does nothing until it suddenly becomes a card. The island swells
     * while it waits, and a bubble does the same through the pill it already animates,
     * so the affordance costs one spring and no new surface. Only when there is a card
     * to open - a glance that cannot expand must not promise one.
     */
    property bool holdPending: false
    readonly property real holdSwell: (bubble.holdPending && !bubble.isExpanded) ? 1.12 : 1

    Timer {
        id: dwellTimer
        interval: bubble.dwellMs
        onTriggered: {
            bubble.holdPending = false;
            if (hover.hovered && bubble.mayExpand && bubble.canExpand && bubble.shown)
                bubble.expandRequested(bubble.shownId);
        }
    }
    // A short grace, so drifting off the edge of the card does not fold it at once.
    Timer {
        id: graceTimer
        interval: 450
        onTriggered: {
            if (!hover.hovered && bubble.isExpanded)
                bubble.collapseRequested(bubble.shownId);
        }
    }

    /** The collapsed width: a circle, or the pill the glance asks for. */
    readonly property real collapsedWidth: Math.max(bubble.diameter, content.preferredWidth)
    property real pillWidth: bubble.isExpanded ? bubble.expandedWidth
        : bubble.collapsedWidth * bubble.holdSwell
    property real pillHeight: bubble.isExpanded ? bubble.expandedHeight
        : bubble.diameter * bubble.holdSwell
    // The island's own spring: a small object settles with a small bounce.
    Behavior on pillWidth {
        NumberAnimation {
            duration: Math.round(460 * Appearance.animMultiplier)
            easing.type: Easing.OutBack
            easing.overshoot: 0.5
        }
    }
    Behavior on pillHeight {
        NumberAnimation {
            duration: Math.round(460 * Appearance.animMultiplier)
            easing.type: Easing.OutBack
            easing.overshoot: 0.35
        }
    }
    /** Round while it is a circle or a pill, the island's card radius once it is taller. */
    readonly property real pillRadius: Math.min(bubble.pillHeight / 2, Appearance.rounding.large)

    /** 0 = the glance, 1 = the expanded face; one clock for the crossfade. */
    property real expandBlend: bubble.isExpanded ? 1 : 0
    Behavior on expandBlend {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(bubble)
    }

    // ── The anchor: the body, or the parent bubble's live circle ─────────────
    readonly property real anchorCenterX: bubble.parentBubble === null
        ? bubble.bodyCenterX : bubble.parentBubble.view.bubbleX
    readonly property real anchorCenterY: bubble.parentBubble === null
        ? bubble.centerY : bubble.parentBubble.view.bubbleCenterY
    readonly property real anchorTop: bubble.parentBubble === null
        ? bubble.bodyTop
        : bubble.parentBubble.view.bubbleCenterY - bubble.parentBubble.view.bubbleDiameter / 2
    readonly property real anchorWidth: bubble.parentBubble === null
        ? bubble.bodyWidth : bubble.parentBubble.view.bubbleShapeWidth
    readonly property real anchorHeight: bubble.parentBubble === null
        ? bubble.bodyHeight : bubble.parentBubble.view.bubbleDiameter
    readonly property real anchorRadius: bubble.parentBubble === null
        ? bubble.bodyRadius : bubble.parentBubble.view.bubbleDiameter / 2

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
        bubbleWidth: bubble.pillWidth
        bubbleHeight: bubble.pillHeight
        bubbleRadius: bubble.pillRadius
        gap: bubble.gap
        surfaceColor: bubble.surfaceColor
        shadowEnabled: bubble.shadowEnabled
    }

    // The glance itself, fading in once the bubble has mostly left.
    // ── What is drawn inside the shape ───────────────────────────────────────
    /**
     * The glance and the expanded face live in one box that follows the *live* shape
     * and is masked to its rounded outline - the same mask the island puts on its own
     * content. Clipped to the target size instead, a pill still growing showed its
     * contents past its edge (the play button before the pill had reached it), and an
     * expanded face drew its own corners, not the card's.
     */
    Item {
        id: shapeBox
        visible: surface.visible && bubble.shownId !== ""
        x: surface.bubbleX - surface.bubbleShapeWidth / 2
        y: surface.bubbleTop
        width: surface.bubbleShapeWidth
        height: surface.bubbleShapeHeight

        layer.enabled: shapeBox.visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shapeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // The glance keeps the collapsed width and sits at the pill's inner end, so a
        // growing pill uncovers it and an expansion carries it along while it fades.
        AuxiliaryBubbleContent {
            id: content
            width: bubble.collapsedWidth
            x: surface.toRight ? 0 : shapeBox.width - width
            // Centred on the circle's line, scaled from the inner end as it emerges.
            y: (surface.bubbleDiameter - height) / 2
            transformOrigin: surface.toRight ? Item.Left : Item.Right
            activityId: bubble.shownId
            diameter: bubble.diameter
            revealedWidth: surface.bubbleShapeWidth
            interactive: !bubble.isExpanded
            visible: opacity > 0
            opacity: surface.contentProgress * (1 - bubble.expandBlend)
            scale: surface.growth > 0 ? Math.min(1, surface.bubbleDiameter / bubble.diameter) : 0
        }

        // The expanded face, laid out once at its final size and revealed by the
        // growing card: sized to the animating shape it would be re-laid out on every
        // frame.
        Loader {
            id: expandedFace
            // Anchored at the inner top corner, the one that does not move.
            x: surface.toRight ? 0 : shapeBox.width - width
            width: bubble.expandedWidth
            height: bubble.expandedHeight
            active: bubble.shownId !== "" && (bubble.isExpanded || bubble.expandBlend > 0)
            visible: bubble.expandBlend > 0.01
            source: bubble.shownId !== "" ? IslandRegistry.legacyContentFor(bubble.shownId) : ""
            // Comes in once the card has mostly grown, leaves at once.
            opacity: Math.max(0, (bubble.expandBlend - 0.4) / 0.6)

            Binding {
                target: expandedFace.item && expandedFace.item.hasOwnProperty("isExpanded") ? expandedFace.item : null
                property: "isExpanded"
                value: true
            }
            Binding {
                target: expandedFace.item && expandedFace.item.hasOwnProperty("panelWidgetsCount") ? expandedFace.item : null
                property: "panelWidgetsCount"
                value: 1
            }

            // Back to the descriptor's height the moment the face is gone, so the next
            // activity to take this bubble is never sized by the last one's card.
            Binding {
                target: bubble
                property: "facePreferredHeight"
                value: (expandedFace.item && expandedFace.item.preferredExpandedHeight !== undefined)
                    ? expandedFace.item.preferredExpandedHeight : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
        }
    }

    // The live shape's outline, rendered only as the box's mask.
    Item {
        id: shapeMask
        x: shapeBox.x
        y: shapeBox.y
        width: shapeBox.width
        height: shapeBox.height
        visible: false
        layer.enabled: shapeBox.visible

        Rectangle {
            anchors.fill: parent
            antialiasing: true
            color: "black"
            radius: Math.min(bubble.pillRadius * surface.growth, Math.min(width, height) / 2)
        }
    }

    /**
     * Where the settled bubble sits. It stays while the island is open from it, even
     * though the bubble has gone back in: the pointer is still here, and losing it
     * would close the island it just opened.
     */
    Item {
        id: hit
        readonly property bool live: bubble.shown && bubble.progress > 0.5
        x: surface.endX - bubble.pillWidth / 2
        y: surface.bubbleCenterY - bubble.diameter / 2
        width: hit.live ? bubble.pillWidth : 0
        height: hit.live ? bubble.pillHeight : 0

        HoverHandler {
            id: hover
            enabled: hit.live
            onHoveredChanged: {
                bubble.pointerChanged(hover.hovered);
                if (hover.hovered) {
                    graceTimer.stop();
                    if (!bubble.isExpanded) {
                        bubble.holdPending = bubble.mayExpand && bubble.canExpand;
                        dwellTimer.restart();
                    }
                } else {
                    dwellTimer.stop();
                    bubble.holdPending = false;
                    if (bubble.isExpanded)
                        graceTimer.restart();
                }
            }
        }
    }

    Region {
        id: region
        item: hit
    }

    // Reach, live: the bar widens its gap for whatever of the travel is on screen.
    readonly property real reachRight: bubble.side === "right" && surface.visible
        ? Math.max(0, Math.ceil(surface.bubbleRight - bubble.reservedRight)) : 0
    readonly property real reachLeft: bubble.side !== "right" && surface.visible
        ? Math.max(0, Math.ceil(bubble.reservedLeft - surface.bubbleLeft)) : 0
    onReachRightChanged: bubble.reachChanged(bubble.reachRight, bubble.reachLeft)
    onReachLeftChanged: bubble.reachChanged(bubble.reachRight, bubble.reachLeft)
}
