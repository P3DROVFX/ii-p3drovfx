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
    /** The bubble chained out of this one, registered by the child itself. */
    property AuxiliaryBubble childBubble: null

    function register() {
        if (bubble.parentBubble !== null)
            bubble.parentBubble.childBubble = bubble;
    }
    onParentBubbleChanged: bubble.register()
    Component.onCompleted: bubble.register()

    // ── What the host says ───────────────────────────────────────────────────
    /** The activity assigned to this slot; "" when the slot is empty. */
    required property string activityId
    /** The activity is holding the island's centre for now: in, but keeping this slot. */
    required property bool away
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
    readonly property bool anchorReady: bubble.parentBubble === null || bubble.parentBubble.holdsPlace
    /** Out, or in only for a moment: what hangs from it stays, hung from its anchor meanwhile. */
    readonly property bool holdsPlace: bubble.shown || (bubble.away && bubble.activityId !== "")
    readonly property bool wanted: bubble.enabledState && bubble.activityId !== ""
        && bubble.pagedId !== bubble.activityId && !bubble.away
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
    onActivityIdChanged: {
        if (bubble.activityId === "")
            bubble.wentAway = false;
        bubble.syncShown();
    }

    /**
     * The morph's one clock, linear as in the reference: the surface shapes it into the
     * travel, the growth and the neck. A reversal runs for the distance left, so calling
     * the bubble back half way takes half the time.
     */
    property real progress: 0
    readonly property int morphMs: Math.round(620 * Appearance.animMultiplier)
    /**
     * Called back because the island is growing over it - expanding, or opening search
     * or the dashboard - a bubble has no clock of its own: it rides the island's.
     *
     * `swallow` is the host's growth, 0 to 1, read off the body's animated size. What
     * is left of the bubble outside the body is what is left of the island's growth:
     * half way there, half the bubble still shows, and it is home on the frame the
     * island reaches its size, whatever it is growing into and at whatever speed.
     *
     * It is how much of the bubble is *out* that follows, not its clock. The clock's
     * second half changes nothing on screen (the travel and the growth have long
     * settled), so a bubble following on the clock sat at full size while the island
     * did most of its growing - pushed a hundred pixels out by the edge - and only then
     * went, in a hurry: one gesture, two movements.
     */
    required property real swallow
    /** How far the body's side moves over that growth, in pixels. */
    required property real swallowSpan
    /**
     * Whether the island is growing over the bubbles. A function, and asked of the parent
     * too: a chained bubble learns its parent went in through `anchorReady`, before its
     * own copy of the host's flags has caught up, and reading those alone sent it home
     * on its own clock while the rest of the chain rode the island.
     */
    function swallowed() {
        return bubble.expanded || bubble.searchActive || bubble.dashboardActive || bubble.away
            || (bubble.parentBubble !== null && bubble.parentBubble.swallowed());
    }
    /**
     * Going into the island, or coming back out of it, because its own activity took the
     * centre: the island grows by what this bubble alone gives it, so this bubble alone
     * is eaten or let out over the whole of that growth, and what hangs beyond it rides
     * along. Latched until it is back out, as the flag flips before the emergence begins.
     */
    property bool wentAway: false
    onAwayChanged: {
        if (!bubble.away)
            return;
        bubble.wentAway = true;
        // The island's face moves to the activity a step before it is marked as holding
        // the centre, so the recall usually began a moment ago, on the bubble's own clock.
        // It rides the island from here instead.
        if (!bubble.shown && !bubble.following && bubble.progress > 0) {
            travel.stop();
            bubble.beginFollowing();
        }
    }
    /** Riding the island's growth home, from however far out the bubble was when it began. */
    property bool following: false
    /**
     * A chain goes home as one piece. The body's edge eats into it from the inside,
     * as deep as the tip stood out when the recall began; every bubble keeps whatever
     * of its own span that depth has not reached yet. Given the same share each, the
     * outer bubbles stayed full size, pushed out by the edge, then went all at once.
     * Distances are in pixels past the body's edge, taken when the recall began.
     */
    property real recallStart: 0
    property real recallFar: 0
    property real recallAnchor: 0
    property real recallTip: 0
    /**
     * The same the other way: the island closing lets the bubbles out, and they grow as
     * it shrinks, full size on the frame it is back to its own. On their own clock they
     * were still on their way out long after the island had settled - the opposite two
     * movements. Only the emergence rides the island; the settle that follows (the rest
     * of the clock, a few pixels of spring) is the bubble's own.
     */
    property bool emerging: false
    /**
     * Whether the glance shows with how far out the shape is, not on the clock's schedule.
     * The schedule drops it in the first tenth of a recall and brings it in after the
     * bubble is out, which on the island's clock is an empty circle either way. Latched
     * until the two agree again, so handing the clock back never blinks the glance.
     */
    property bool glanceBySize: false
    /** How far this bubble's outer edge stands past the body's, through its parents. */
    function pastBody() {
        const own = surface.reach * surface.restReach;
        return own + (bubble.parentBubble === null ? 0 : bubble.parentBubble.pastBody());
    }
    /** The same, with this bubble and its parents at rest. */
    function restPastBody() {
        const own = surface.restReach;
        return own + (bubble.parentBubble === null ? 0 : bubble.parentBubble.restPastBody());
    }
    /** The outermost bubble of this chain that is out, or coming out. */
    function chainTip(coming) {
        let tip = bubble;
        while (tip.childBubble !== null
                && (coming ? tip.childBubble.emerging : tip.childBubble.progress > 0))
            tip = tip.childBubble;
        return tip;
    }
    /** The clock for a span of this bubble in pixels past its anchor. */
    function clockFor(span) {
        return surface.clockForReach(span / Math.max(1, surface.restReach));
    }
    /**
     * Fully eaten while the chain rides the island: folded away, and whatever hangs from
     * it hangs from the body meanwhile. It folds on the frame its outer edge reaches the
     * body's, so the handover does not move anything. Waiting on the edge instead, as a
     * circle half grown, it showed past the launcher's rounded corner as a dot.
     */
    property bool stowed: false
    function follow() {
        const grown = Math.max(0, Math.min(1, bubble.swallow));
        if (bubble.following && bubble.wentAway) {
            const span = bubble.recallFar - bubble.recallAnchor;
            const done = (grown - bubble.recallStart) / Math.max(0.001, 1 - bubble.recallStart);
            const own = span * Math.max(0, 1 - bubble.holdStill(span) * done);
            bubble.rideNeck(own);
            bubble.stowed = own <= 0;
            bubble.progress = Math.min(bubble.progress, bubble.clockFor(own));
        } else if (bubble.following) {
            const eaten = bubble.recallTip * (grown - bubble.recallStart)
                / Math.max(0.001, 1 - bubble.recallStart);
            const own = Math.max(0, bubble.recallFar - eaten) - Math.max(0, bubble.recallAnchor - eaten);
            // Inwards only: the island shrinking again must not push an empty bubble out.
            bubble.stowed = own <= 0;
            bubble.progress = Math.min(bubble.progress, bubble.clockFor(own));
        } else if (bubble.emerging && bubble.wentAway) {
            const own = surface.restReach * (1 - Math.min(1, bubble.holdStill(surface.restReach) * grown));
            bubble.rideNeck(own);
            bubble.stowed = own <= 0;
            bubble.progress = Math.max(bubble.progress, bubble.clockFor(own));
            if (grown <= 0)
                bubble.settle();
        } else if (bubble.emerging) {
            // The reverse, at rest: the tip shows first, the bubbles inside it push it out.
            const eaten = bubble.chainTip(true).restPastBody() * grown;
            const far = bubble.restPastBody();
            const own = Math.max(0, far - eaten) - Math.max(0, far - surface.restReach - eaten);
            bubble.stowed = own <= 0;
            bubble.progress = Math.max(bubble.progress, bubble.clockFor(own));
            if (grown <= 0)
                bubble.settle();
        }
    }
    /**
     * Riding the island, the neck goes by how far out the bubble is: it joins as the
     * bubble closes on its anchor and lets go as it clears it. Handed back to the clock
     * once the clock has let go too (`onProgressChanged`).
     */
    function rideNeck(own) {
        const share = own / Math.max(1, surface.restReach);
        surface.releaseOverride = surface.smoothstep((share - 0.55) / 0.35);
    }
    /**
     * How much faster than the island's growth this bubble goes in, so that it holds
     * still while the body comes to it: the body's side moves `swallowSpan`, and while
     * the bubble gives up the same distance its outer edge does not move at all. Going
     * in, the island grows into a bubble standing where it was, and then on past it;
     * coming out, the island pulls away from a bubble already where it rests, the neck
     * stretching until it lets go. Given a share equal to the island's, it came out as
     * fast as the body's front-loaded curve shrank - out and pinched off in 80 ms, then
     * dragged along. Never slower than the island: an island growing less than the
     * bubble is wide still has to take all of it.
     */
    function holdStill(span) {
        return Math.max(1, bubble.swallowSpan / Math.max(1, span));
    }
    /** Starts riding the island's growth home, from wherever the bubble is now. */
    function beginFollowing() {
        bubble.following = true;
        bubble.recallStart = Math.max(0, Math.min(0.999, bubble.swallow));
        bubble.recallFar = bubble.pastBody();
        bubble.recallAnchor = bubble.parentBubble === null ? 0 : bubble.parentBubble.pastBody();
        bubble.recallTip = bubble.chainTip(false).pastBody();
        bubble.glanceBySize = true;
        bubble.follow();
    }
    /** The island is back to its size: the rest of the way out is the bubble's own. */
    function settle() {
        // Out of the island already standing where it rests: the clock skips its spring,
        // which after the island had stopped was a second movement of its own.
        if (bubble.wentAway && surface.reachAt(bubble.progress) >= 0.97)
            bubble.progress = Math.max(bubble.progress, surface.settledClock);
        bubble.emerging = false;
        bubble.wentAway = false;
        bubble.stowed = false;
        travel.from = bubble.progress;
        travel.to = 1;
        travel.duration = Math.max(1, bubble.morphMs * (1 - bubble.progress));
        travel.start();
    }
    onSwallowChanged: bubble.follow()
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
        // Set here as well: `onAwayChanged` runs after this handler for the same change,
        // and the recall below picks its path from the latch.
        if (bubble.away)
            bubble.wentAway = true;
        travel.stop();
        // Stowed while it stands inside its anchor, so a bubble coming back into the middle
        // of a chain hands its children over on the frame its edge clears the anchor's.
        bubble.stowed = surface.reachAt(bubble.progress) <= 0;
        bubble.following = !bubble.shown && bubble.swallowed() && bubble.progress > 0;
        if (bubble.following) {
            bubble.beginFollowing();
            return;
        }
        bubble.emerging = bubble.shown && !bubble.swallowed() && bubble.swallow > 0.001;
        // Back out on its own clock (the island was not shrinking): nothing to ride.
        if (bubble.shown && !bubble.emerging)
            bubble.wentAway = false;
        if (bubble.emerging) {
            bubble.glanceBySize = true;
            bubble.follow();
            return;
        }
        // Called back on its own clock (its activity took the island's centre, or ended),
        // it starts from where it last looked settled. Reversed from 1, it spent the first
        // ~280 ms still - pushed out by the island growing towards it, showing its glance
        // next to the same activity already on the island - and only then went in.
        if (!bubble.shown)
            bubble.progress = Math.min(bubble.progress, surface.settledClock);
        travel.from = bubble.progress;
        travel.to = target;
        travel.duration = Math.max(1, bubble.morphMs * Math.abs(target - bubble.progress));
        travel.start();
    }
    onProgressChanged: {
        if (surface.releaseOverride >= 0 && !bubble.following && !bubble.emerging
                && (bubble.progress >= 0.47 || bubble.progress <= 0))
            surface.releaseOverride = -1;
        // On its own clock, too, whatever hangs from it rides it until its outer edge is
        // back at its anchor's, and hangs from that anchor from then on - the same
        // handover `follow()` makes.
        if (!bubble.following && !bubble.emerging)
            bubble.stowed = surface.reachAt(bubble.progress) <= 0;
        if (bubble.glanceBySize && !bubble.following && !bubble.emerging
                && (bubble.progress <= 0 || surface.contentProgress >= 1))
            bubble.glanceBySize = false;
        bubble.syncShown();
    }

    // ── Expanded: an island of its own ───────────────────────────────────────
    /**
     * Resting on a bubble opens it into an island-style card beside the island, not
     * the island itself. It grows away from the island - outwards, and down from its
     * own top edge - pushing everything on that side, and hosts the activity's own
     * expanded face. This card is the only host of one: expanding the island opens the
     * dashboard, and LocalSend's drop flow is not a hover view.
     */
    readonly property bool isExpanded: bubble.shown && bubble.shownId !== ""
        && bubble.expandedBubbleId === bubble.shownId
    /**
     * The card's width, like the height below: what the face asks for when it can say.
     * A grid that lays itself out at its own count would otherwise sit inside the
     * descriptor's worst-case width with the slack split as fat side margins.
     */
    property real facePreferredWidth: 0
    readonly property real expandedWidth: bubble.facePreferredWidth > 0
        ? bubble.facePreferredWidth : IslandRegistry.widthFor(bubble.shownId, "expanded")
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
    readonly property real holdSwellScale: 1.12
    readonly property real holdSwell: (bubble.holdPending && !bubble.isExpanded) ? bubble.holdSwellScale : 1

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
        interval: IslandPolicy.collapseGraceMs
        onTriggered: {
            if (!hover.hovered && bubble.isExpanded && !bubble.faceHoldsOpen)
                bubble.collapseRequested(bubble.shownId);
        }
    }
    /**
     * A face that opened something of its own outside the card — the tray's context
     * menu — says so through `holdsOpen`. The pointer leaves for that window, and
     * folding the card under a live menu would take the anchor down with it; the fold
     * waits for the menu instead, restarting the grace the moment the face lets go.
     */
    property bool faceHoldsOpen: false
    onFaceHoldsOpenChanged: {
        if (!bubble.faceHoldsOpen && !hover.hovered && bubble.isExpanded)
            graceTimer.restart();
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

    /**
     * 0 = the glance, 1 = the expanded face: how far the card is open, read off the live
     * shape rather than a clock of its own. On a separate 200 ms fade the face was in
     * long before the card had grown and gone long before it had shrunk - a card showing
     * up behind the bubble, then an empty box folding away. Measured on the shape, the
     * swap is the growth itself, and a reversal half way stays in step.
     *
     * Measured from the swollen size, so the hold's swell never starts the swap, and only
     * while the card is open or folding (`cardOut`): a glance pill narrowing to a new
     * width is a shape bigger than its target too, and read as a card it faded the glance
     * and loaded the face.
     *
     * The latch drops a turn after the shape is home, never from inside the change that
     * got it there: dropping it unloads the face, which resets the card's size, which
     * this measurement reads - a binding loop on every fold.
     */
    property bool cardOut: false
    function dropCardOut() {
        if (!bubble.isExpanded && bubble.cardOpenness <= 0)
            bubble.cardOut = false;
    }
    onIsExpandedChanged: {
        if (bubble.isExpanded)
            bubble.cardOut = true;
        else
            Qt.callLater(bubble.dropCardOut);
    }
    onCardOpennessChanged: {
        if (!bubble.isExpanded && bubble.cardOpenness <= 0)
            Qt.callLater(bubble.dropCardOut);
    }
    readonly property real expandBlend: (bubble.isExpanded || bubble.cardOut) ? bubble.cardOpenness : 0
    /** The shape's openness as measured, whether or not a card is out. */
    readonly property real cardOpenness: {
        const fromH = bubble.diameter * bubble.holdSwellScale;
        const fromW = bubble.collapsedWidth * bubble.holdSwellScale;
        const spanH = bubble.expandedHeight - fromH;
        const spanW = bubble.expandedWidth - fromW;
        if (spanH <= 1 && spanW <= 1)
            return bubble.isExpanded ? 1 : 0;
        let open = 0;
        if (spanH > 1)
            open = Math.max(open, (bubble.pillHeight - fromH) / spanH);
        if (spanW > 1)
            open = Math.max(open, (bubble.pillWidth - fromW) / spanW);
        return Math.max(0, Math.min(1, open));
    }
    /** The glance is gone by a third of the way; the face comes in over the middle. */
    readonly property real glanceOut: surface.smoothstep(bubble.expandBlend / 0.35)
    readonly property real faceIn: surface.smoothstep((bubble.expandBlend - 0.3) / 0.45)
    /**
     * The face grows with the card from its fixed inner top corner, and the glance grows
     * into it from the same corner as it fades: at 1.5x a circle's centred icon lands on
     * a card header's (a 38 px icon 14 px in), so the one icon seems to become the other.
     */
    readonly property real faceScale: 0.85 + 0.15 * bubble.expandBlend
    readonly property real glanceScale: 1 + (1.5 * bubble.faceScale - 1) * bubble.glanceOut

    /**
     * The shared elements. A glance and a face that both list `heroItems` (an icon, a
     * time, a sensor's glyph) hand those over instead of crossfading them: a copy of each
     * glance element rides the card's growth from where it sits to the place and size of
     * the face's element at the same index, read off the face's own layout, while the
     * rest of the glance fades as usual. Crossfaded where they stood, the glance faded
     * out and the header icon faded in 20 px away: one icon vanishing, another appearing.
     * A null on either side, or an index only one side has, is no pair.
     *
     * Each copy carries both elements and turns from one into the other on the way
     * (`heroMorph`), so a pair that differs (a battery ring and a device's avatar, a
     * small time and a big one) lands as the face's own and never pops. Both are textures
     * of the real elements, hidden where they stand while copied, so neither leaves its
     * layout, and they exist only in flight: no layer while the bubble or the card sits
     * still.
     *
     * A face element that says `heroBackdrop` (the media card's album art, grown from the
     * ring) is a backdrop: its copy rides under the face's text instead of over it, and
     * always fills the live shape, which rounds it. Inside it the glance's element grows
     * from where it sits until its middle covers the card, then turns into the card's art.
     */
    readonly property var heroPairs: {
        const from = content.heroItems;
        const face = expandedFace.item;
        const to = face && face.heroItems ? face.heroItems : [];
        const pairs = [];
        for (let i = 0; i < Math.min(from.length, to.length); i++) {
            if (from[i] && to[i])
                pairs.push({ from: from[i], to: to[i], backdrop: to[i].heroBackdrop === true });
        }
        return pairs;
    }
    readonly property bool heroActive: bubble.heroPairs.length > 0
    /** The card is fully open: the face shows its own elements and the copies are gone. */
    readonly property bool heroLanded: bubble.isExpanded && bubble.expandBlend >= 1
    readonly property bool heroFlying: bubble.heroActive && !bubble.heroLanded && bubble.expandBlend > 0
    /**
     * The copies outlive their flight by a moment. A Loader turned off hides its item at
     * once but deletes it later, and until then the copies still hid the real elements:
     * the frame in between drew the card with no art. Past the flight they are hidden and
     * let go of the elements in one step, and are only then unloaded.
     */
    readonly property bool heroLoaded: bubble.heroFlying || heroLinger.running

    onHeroFlyingChanged: {
        if (!bubble.heroFlying)
            heroLinger.restart();
    }

    Timer {
        id: heroLinger
        interval: 150
    }
    /** How far the copies have turned from the glance's elements into the face's. */
    readonly property real heroMorph: surface.smoothstep((bubble.expandBlend - 0.25) / 0.6)
    /** Where a copy starts: the glance's element at rest, in the shape box. */
    function heroFrom(from) {
        const g = from.mapToItem(content, 0, 0, from.width, from.height);
        return Qt.rect(content.x + g.x, content.y + g.y, g.width, g.height);
    }
    /** Where it lands: the face's element, through the face's own scale (its Scale below). */
    function heroTo(to) {
        const f = to.mapToItem(expandedFace, 0, 0, to.width, to.height);
        const ox = surface.toRight ? 0 : expandedFace.width;
        return Qt.rect(expandedFace.x + ox + (f.x - ox) * bubble.faceScale,
            expandedFace.y + f.y * bubble.faceScale,
            f.width * bubble.faceScale, f.height * bubble.faceScale);
    }
    /** A pair's copy at `t` of the way, in the shape box. */
    function heroRect(pair, t) {
        const a = bubble.heroFrom(pair.from);
        const b = bubble.heroTo(pair.to);
        return Qt.rect(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t,
            a.width + (b.width - a.width) * t, a.height + (b.height - a.height) * t);
    }
    /**
     * How far a backdrop has grown: ahead of the card's own pace, since it is the card's
     * fill. Taken linearly, a small ring of art sat in an already large, empty card.
     */
    readonly property real heroBackdropGrowth: 1 - Math.pow(1 - bubble.expandBlend, 3)
    /**
     * A backdrop turns into the card's art sooner than an icon does: blown up from a
     * 30 px ring, the glance's sharp cover would not hold for long.
     */
    readonly property real heroBackdropMorph: surface.smoothstep((bubble.expandBlend - 0.05) / 0.45)
    /**
     * Where a backdrop's glance element is drawn at `t`, in the shape box: from where it
     * sits to a box centred on the shape in which its art (`heroFill` of it: the media
     * ring's cover, inside the rim) is as wide as the card's own art, the same cover
     * filled into the card, which is as wide as the longer side.
     */
    function heroBackdropFrom(pair, t) {
        const a = bubble.heroFrom(pair.from);
        const fill = pair.from.heroFill ?? 1;
        const w = shapeBox.width;
        const h = shapeBox.height;
        const s = Math.max(w, h) / (fill * Math.min(a.width, a.height));
        const bw = a.width * s;
        const bh = a.height * s;
        const bx = (w - bw) / 2;
        const by = (h - bh) / 2;
        return Qt.rect(a.x + (bx - a.x) * t, a.y + (by - a.y) * t,
            a.width + (bw - a.width) * t, a.height + (bh - a.height) * t);
    }
    /**
     * Where the face's backdrop is drawn at `t`: the whole shape at the end, and before
     * that scaled down with the glance element around its centre, so the two arts stay
     * one on the other through the crossfade. Drawn at full size while the ring still
     * moved, the card's planet sat beside the ring's.
     */
    function heroBackdropTo(pair, t) {
        const v = bubble.heroBackdropFrom(pair, t);
        const end = bubble.heroBackdropFrom(pair, 1);
        const k = end.width > 0 ? v.width / end.width : 1;
        const w = shapeBox.width * k;
        const h = shapeBox.height * k;
        return Qt.rect(v.x + v.width / 2 - w / 2, v.y + v.height / 2 - h / 2, w, h);
    }
    /**
     * The `sourceRect` that draws `item` over `r` (in the shape box) in a copy filling
     * the whole shape; what falls outside the item is transparent.
     */
    function heroSourceFor(item, r) {
        if (item.width <= 0 || item.height <= 0 || r.width <= 0 || r.height <= 0)
            return Qt.rect(0, 0, 0, 0);
        const sx = item.width / r.width;
        const sy = item.height / r.height;
        return Qt.rect(-r.x * sx, -r.y * sy, shapeBox.width * sx, shapeBox.height * sy);
    }

    // ── The anchor: the body, or the parent bubble's live circle ─────────────
    /** The live circle this bubble hangs from; null for the body. A stowed one is skipped. */
    readonly property AuxiliaryBubble anchorBubble: bubble.parentBubble === null ? null
        : (bubble.parentBubble.stowed ? bubble.parentBubble.anchorBubble : bubble.parentBubble)
    readonly property real anchorCenterX: bubble.anchorBubble === null
        ? bubble.bodyCenterX : bubble.anchorBubble.view.bubbleX
    readonly property real anchorCenterY: bubble.anchorBubble === null
        ? bubble.centerY : bubble.anchorBubble.view.bubbleCenterY
    readonly property real anchorTop: bubble.anchorBubble === null
        ? bubble.bodyTop
        : bubble.anchorBubble.view.bubbleCenterY - bubble.anchorBubble.view.bubbleDiameter / 2
    readonly property real anchorWidth: bubble.anchorBubble === null
        ? bubble.bodyWidth : bubble.anchorBubble.view.bubbleShapeWidth
    readonly property real anchorHeight: bubble.anchorBubble === null
        ? bubble.bodyHeight : bubble.anchorBubble.view.bubbleDiameter
    readonly property real anchorRadius: bubble.anchorBubble === null
        ? bubble.bodyRadius : bubble.anchorBubble.view.bubbleDiameter / 2
    // An open card draws over the bubbles beside it: a bubble chained off it reaches into
    // it with its field, and drawn after the card its cut left a line across the card.
    z: bubble.isExpanded || bubble.cardOut ? 1 : 0

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
            handOff: bubble.expandBlend
            diameter: bubble.diameter
            revealedWidth: surface.bubbleShapeWidth
            interactive: !bubble.isExpanded
            // Kept in the scene while its element is being copied, faded or not.
            visible: opacity > 0 || bubble.heroFlying
            // On the island's clock the glance goes with the shape (see `glanceBySize`).
            opacity: (bubble.glanceBySize ? Math.min(1, surface.reach * 2)
                : surface.contentProgress) * (1 - bubble.glanceOut)
            scale: surface.growth > 0 ? Math.min(1, surface.bubbleDiameter / bubble.diameter) : 0
            // Into the card's header, from the shape's inner top corner.
            transform: Scale {
                origin.x: surface.toRight ? 0 : content.width
                origin.y: -content.y
                xScale: bubble.glanceScale
                yScale: bubble.glanceScale
            }
        }

        // A backdrop's copy in flight, under the face's text (see `heroPairs`).
        Loader {
            readonly property bool backdrop: true
            active: bubble.heroLoaded && bubble.heroPairs.some(pair => pair.backdrop)
            sourceComponent: heroLayer
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
            active: bubble.shownId !== "" && (bubble.isExpanded || bubble.cardOut)
            visible: bubble.expandBlend > 0.01
            source: bubble.shownId !== "" ? IslandRegistry.faceFor(bubble.shownId, "expanded") : ""
            // Comes in and leaves with the card's growth, grown from the corner it hangs by.
            opacity: bubble.faceIn
            transform: Scale {
                origin.x: surface.toRight ? 0 : expandedFace.width
                origin.y: 0
                xScale: bubble.faceScale
                yScale: bubble.faceScale
            }

            onStatusChanged: {
                if (status === Loader.Error && bubble.shownId !== "") {
                    const fallback = IslandRegistry.legacyContentFor(bubble.shownId);
                    if (source != fallback)
                        source = fallback;
                }
            }

            // For a legacy face that animates its own expansion: this card grows it instead.
            Binding {
                target: expandedFace.item && expandedFace.item.hasOwnProperty("inBubbleCard") ? expandedFace.item : null
                property: "inBubbleCard"
                value: true
            }
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
            // For a face shared by several activities (the Bluetooth devices' card): which
            // one it was opened for.
            Binding {
                target: expandedFace.item && expandedFace.item.hasOwnProperty("activityId") ? expandedFace.item : null
                property: "activityId"
                value: bubble.shownId
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
            Binding {
                target: bubble
                property: "facePreferredWidth"
                value: (expandedFace.item && expandedFace.item.preferredExpandedWidth !== undefined)
                    ? expandedFace.item.preferredExpandedWidth : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
            // The card's open state, for a face that animates its own contents in a
            // cascade. `isExpanded` stays the legacy face's constant; this one tracks
            // the bubble, so the face sees the fold coming while the Loader is still
            // alive fading out.
            Binding {
                target: expandedFace.item && expandedFace.item.hasOwnProperty("cardExpanded") ? expandedFace.item : null
                property: "cardExpanded"
                value: bubble.isExpanded
                restoreMode: Binding.RestoreBindingOrValue
            }

            // The one-way read the height above already uses: whatever the face says.
            Binding {
                target: bubble
                property: "faceHoldsOpen"
                value: expandedFace.item ? expandedFace.item.holdsOpen === true : false
                restoreMode: Binding.RestoreBindingOrValue
            }
        }

        // The heroes' copies in flight, over the face.
        Loader {
            readonly property bool backdrop: false
            active: bubble.heroLoaded && bubble.heroPairs.some(pair => !pair.backdrop)
            sourceComponent: heroLayer
        }

        // The copies in flight, one layer per side of the face. Both elements of a pair
        // are rendered at the larger of their two sizes once for the flight (a backdrop
        // at the card's), so a copy grows without blurring and never reallocates. Each
        // side stays whole until the other is (`min(1, 2x)`): two halves stacked at 0.5
        // would let the card show through.
        Component {
            id: heroLayer

            Item {
                id: heroCopies
                // Which heroes this layer carries: its Loader's.
                readonly property bool backdrop: heroCopies.parent ? heroCopies.parent.backdrop === true : false
                // Hidden with the elements let go, the moment the flight ends (see `heroLoaded`).
                visible: bubble.heroFlying

                Repeater {
                    model: bubble.heroPairs.length

                    Item {
                        id: heroCopy
                        required property int index
                        readonly property var entry: bubble.heroPairs[heroCopy.index] ?? null
                        readonly property var pair: heroCopy.entry && heroCopy.entry.backdrop === heroCopies.backdrop
                            ? heroCopy.entry : null
                        readonly property rect rect: {
                            if (!heroCopy.pair)
                                return Qt.rect(0, 0, 0, 0);
                            return heroCopy.pair.backdrop ? Qt.rect(0, 0, shapeBox.width, shapeBox.height)
                                : bubble.heroRect(heroCopy.pair, bubble.expandBlend);
                        }
                        readonly property real morph: heroCopy.pair && heroCopy.pair.backdrop
                            ? bubble.heroBackdropMorph : bubble.heroMorph
                        readonly property real dpr: Screen.devicePixelRatio || 1
                        readonly property size textureSize: {
                            if (!heroCopy.pair)
                                return Qt.size(0, 0);
                            // A backdrop is the card's size, and its element follows the
                            // growing shape: sized by that, it would reallocate every frame.
                            if (heroCopy.pair.backdrop)
                                return Qt.size(Math.ceil(bubble.expandedWidth * heroCopy.dpr),
                                    Math.ceil(bubble.expandedHeight * heroCopy.dpr));
                            return Qt.size(
                                Math.ceil(Math.max(heroCopy.pair.from.width, heroCopy.pair.to.width) * heroCopy.dpr),
                                Math.ceil(Math.max(heroCopy.pair.from.height, heroCopy.pair.to.height) * heroCopy.dpr));
                        }
                        x: heroCopy.rect.x
                        y: heroCopy.rect.y
                        width: heroCopy.rect.width
                        height: heroCopy.rect.height

                        ShaderEffectSource {
                            anchors.fill: parent
                            sourceItem: heroCopy.pair ? heroCopy.pair.from : null
                            sourceRect: heroCopy.pair && heroCopy.pair.backdrop
                                ? bubble.heroSourceFor(heroCopy.pair.from,
                                    bubble.heroBackdropFrom(heroCopy.pair, bubble.heroBackdropGrowth))
                                : Qt.rect(0, 0, 0, 0)
                            hideSource: bubble.heroFlying
                            live: true
                            smooth: true
                            textureSize: heroCopy.textureSize
                            opacity: Math.min(1, 2 * (1 - heroCopy.morph))
                        }

                        ShaderEffectSource {
                            anchors.fill: parent
                            sourceItem: heroCopy.pair ? heroCopy.pair.to : null
                            sourceRect: heroCopy.pair && heroCopy.pair.backdrop
                                ? bubble.heroSourceFor(heroCopy.pair.to,
                                    bubble.heroBackdropTo(heroCopy.pair, bubble.heroBackdropGrowth))
                                : Qt.rect(0, 0, 0, 0)
                            hideSource: bubble.heroFlying
                            live: true
                            smooth: true
                            textureSize: heroCopy.textureSize
                            opacity: Math.min(1, 2 * heroCopy.morph)
                        }
                    }
                }
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
