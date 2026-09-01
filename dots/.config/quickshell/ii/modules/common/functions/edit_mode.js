.pragma library
// Ported verbatim from XephyLon/immaterial-impulse (GPL-3.0), v0.32.0:
//   dots/.config/quickshell/imi/modules/common/functions/edit_mode.js
// Original author: XephyLon. Reached from QML through EditModeLogic.qml.
// Ported: the tab names, the Escape ladder, the history-stack arithmetic and
// the viewport/card/chrome geometry. Not ported: `enabledWithout`, which
// belongs to their plugin list.

// Edit Mode's two pieces of arithmetic, kept here because they are the only
// parts of the mode a test can reach: everything else about it is a layer
// surface, a transform and a pointer, and `qmltestrunner` can construct none of
// those.
//
// See docs/superpowers/specs/2026-08-16-edit-mode-design.md §8.2 (the ladder)
// and §1.2 (the inset).

// The tab the mode opens on. A string rather than a boolean because the
// Lockscreen tab sits beside it (spec §1.4) and the ladder has to say which
// tab it returns to.
var DESKTOP_TAB = "desktop";

// The Lockscreen tab - a FILTER on the viewport, not a mode (spec §1.4): the
// same entry, the same exit ladder, the same chrome, one GlobalStates.editMode.
// Declared here so the rung above, GlobalStates' preview derivation and the
// chrome's tab bar all read one spelling; the contract holds the literal to
// this file.
var LOCKSCREEN_TAB = "lockscreen";

// The chrome's tab bar speaks indices and everything else speaks tab names.
// The mapping lives here, in the tab list's own order, so the bar's index and
// the ladder's answers cannot come from two spellings of the same list - the
// contract forbids an `editTab ===` comparison outside GlobalStates for
// exactly that reason. Unknown input lands on the Desktop tab both ways: a
// bad index or a stale stored string must not strand the bar pointing at
// nothing.
var TABS = [DESKTOP_TAB, LOCKSCREEN_TAB];

function tabIndex(tab) {
    const index = TABS.indexOf(tab);
    return index < 0 ? 0 : index;
}

function tabAt(index) {
    return TABS[index] || DESKTOP_TAB;
}

// Escape is overloaded on the desktop before Edit Mode exists: WidgetCanvas
// clears a marquee selection with it and PluginWidget cancels a grip resize
// with it. So the mode may not simply take the key - it resolves in order and
// the first match wins, which is what keeps both of those working while the
// mode is on.
//
// A pure function of three inputs, so the precedence is checkable without a
// canvas, a widget or a compositor. The caller does the work each answer names.
function resolveEscape(state) {
    const s = state || {};
    // The per-widget context menu is the topmost transient the mode draws - it
    // opens over the widget it belongs to and everything else waits behind it
    // until a click lands somewhere else - so it is dismissed before anything
    // under it is touched.
    if (s.menuOpen || s.desktopMenuOpen)
        return "closeMenu";
    // The drawer is the next transient: it slides over the card's edge and
    // is closed before the card's own state is touched.
    if (s.drawerOpen)
        return "closeDrawer";
    if (s.gestureInFlight)
        return "cancelGesture";
    if ((s.selectionCount || 0) > 0)
        return "clearSelection";
    if ((s.tab || DESKTOP_TAB) !== DESKTOP_TAB)
        return "desktopTab";
    return "exit";
}

// Entries are opaque here - at the call sites each one is a closure over the
// store write that reverses a committed mutation, never a diff, because a
// diff needs a serialiser per store and there are three stores.

var UNDO_LIMIT = 50;

// A fresh stack on every operation, never a mutation: the stack sits in a
// `property var`, whose change signal fires on reassignment only, so an
// in-place push would leave every observer reading a depth that never moves.
// Bounded by dropping the OLDEST entry - a stack that refuses new work when
// full has stopped recording exactly the mutations the user is still making.
function undoPush(stack, entry) {
    var next = listCopy(stack);
    next.push(entry);
    if (next.length > UNDO_LIMIT)
        next.shift();
    return next;
}

function undoPop(stack) {
    var next = listCopy(stack);
    if (next.length === 0)
        return { stack: next, entry: null };
    var entry = next.pop();
    return { stack: next, entry: entry };
}

// The snapshot an undo closure captures, taken by index and length because a
// store list that has crossed the QML boundary keeps both and loses its
// Array brand (enabledWithout's rule, one shelf up).
function listCopy(list) {
    var out = [];
    var count = list && typeof list.length === "number" ? list.length : 0;
    for (var i = 0; i < count; i++)
        out.push(list[i]);
    return out;
}

// ---- the viewport (spec §1.1-1.3) ------------------------------------------
//
// Where the shrunk desktop sits, as pure arithmetic over the screen, what the
// bar and the dock occupy and a few Appearance tokens. The wallpaper surface,
// the widgets surface and the chrome surface all build their geometry out of
// these on the same animated scalar, which is what keeps three windows in
// three scene graphs framing one rectangle.

// A desktop scaled below this is not an editor any more, it is a thumbnail.
// Only reachable on a screen too narrow to host the drawer at all, where the
// alternative answers are a zero or a negative scale.
var MIN_SCALE = 0.2;

// ...and a desktop scaled ABOVE this is not an object on the screen either: it
// is the screen with four thin strips of blur around it.
//
// The drawer-derived inset below is the right answer while the drawer is a
// meaningful fraction of the width, and it stops being one as the screen
// widens - 380px of drawer plus two 24px margins on a 5120px monitor leaves the
// desktop at 92%, which spends the whole mode signal on a border. The shrink IS
// the signal (spec §1.1: there is no scrim), so it has to be legible at every
// screen size and not only at the one where the arithmetic happens to bite.
//
// A ceiling rather than a second inset, because a ceiling cannot break the
// derivation stage 5 plugs into: the space reserved on the right of the desktop
// is `screenWidth - margin - width`, which the drawer term already holds at or
// above `drawerWidth + margin`, and lowering the scale further can only make it
// larger. So the drawer still opens into space that already exists, and on a
// screen where it is the tighter constraint it still decides.
var MAX_SCALE = 0.86;

// The part of the screen Edit Mode may use: the screen minus what the bar and
// the dock occupy. Those two stay where they are and at full size (spec §12
// stage 8 is editing them in place, and this is not it), so a mode that ignores
// them draws its chrome on top of them - which is what shipped, and what this
// exists to stop.
//
// Insets rather than a rectangle as the input because that is the shape the two
// panels answer in: each occupies one EDGE, across its own axis, and nothing
// about either is a rectangle in the middle of the screen. `EditModeInsets` is
// the one place that turns the bar's and the dock's configuration into these
// four numbers.
function usableArea(input) {
    const screenWidth = (input && input.screenWidth) || 0;
    const screenHeight = (input && input.screenHeight) || 0;
    const top = (input && input.insetTop) || 0;
    const bottom = (input && input.insetBottom) || 0;
    const left = (input && input.insetLeft) || 0;
    const right = (input && input.insetRight) || 0;
    return {
        x: left,
        y: top,
        width: Math.max(0, screenWidth - left - right),
        height: Math.max(0, screenHeight - top - bottom)
    };
}

// The SIZE is derived, not chosen: the desktop shrinks by at least what the
// drawer will need, so the drawer opens into space that already exists rather
// than covering the desktop or resizing it (spec §1.2, §1.3) - and by at least
// what the CHROME will need above and below it, so the toolbar and the tab bar
// have somewhere to be rather than wherever the ceiling happens to leave them.
//
// That second term is the one that was missing. The band the shrink opened was
// whatever fell out of `MAX_SCALE` - 100.8px at 5120x1440 - and the toolbar is
// 56px centred in it, which starts 22.4px down a screen whose bar occupies the
// first 68. Reserving the chrome's own thickness plus a margin either side of
// it, inside the usable area, is what makes the clearance a property of the
// arithmetic instead of a literal tuned against `Appearance.sizes.barHeight`.
//
// The POSITION is dead centre OF THE USABLE AREA, and the two are deliberately
// separate. Centre of the usable area rather than of the panel, because the
// desktop has to sit in the space the chrome frames and the chrome has to clear
// the bar and the dock; on the machine this was measured against the two
// centres are 3.5px apart on a 1440-tall screen, so "dead centre" survives the
// re-reading rather than being traded away by it.
//
// Entering the mode is a concentric shrink - the desktop gets smaller where it
// is, and nothing slides - because reserving the drawer's width inside the
// resting geometry makes the entry asymmetric from its first frame: it drifts
// toward one edge on the way in, which reads as being shoved aside rather than
// lifted off the wallpaper, and it does it whether or not a drawer exists yet.
// The drawer's width is still what decides how far the desktop moves when the
// drawer OPENS; that is a translation applied at that point, in stage 5, on top
// of the `x` this returns.
//
// The arithmetic that lets those two coexist: a centred desktop has
// `(screenWidth - width) / 2` free on each side, and the scale below holds
// `width <= screenWidth - drawerWidth - 2 * margin`, so each side has at least
// `drawerWidth / 2 + margin`. Opening a drawer of `drawerWidth + margin` on the
// right therefore needs the desktop to travel at most `drawerWidth / 2` left,
// which leaves exactly `margin` on its other side. The reservation is real; it
// is just spent when the drawer arrives instead of being held back from the
// start.
//
// `drawerWidth` is passed whether or not the drawer is open, and this function
// has no input for the open state on purpose. A desktop that was full width
// with the drawer closed would be RESIZED by opening it, and a viewport that
// changes size mid-edit rescales every widget under the cursor: a drag in
// flight finds its target a different size than when it was grabbed, and every
// Behavior carrying the box is handed a moving target, which per b710ef731
// ("fix(plugins): stop the position Behavior swallowing the parallax
// cancellation") means it restarts every frame and never ticks.
//
// `margin` is one token: the gap between the desktop and the screen's edge, and
// the gap between the desktop and the drawer's slot once there is a drawer.
//
// `edgeMargin` is the OTHER gap - between the chrome and the usable area's own
// edge - and it is a second token because the two are not the same distance.
// The desktop's margin is a gap between two pieces of content and wants to be
// generous; the chrome's is a gap between a floating toolbar and the edge of
// the screen and wants to be tight, because every pixel of it is taken off the
// desktop the mode exists to show. It defaults to `margin`, which is the
// symmetric band the geometry had before the two were told apart.
//
// `chromeThickness` is the toolbar's own height, and it is passed rather than
// measured for the same reason `drawerWidth` is: the desktop's transform is
// built out of this function on the BACKGROUND surface, where neither the
// toolbar nor the tab bar exists. `Appearance.sizes.toolbarHeight` is the one
// number both this and the toolbars themselves read.
function viewportGeometry(input) {
    const screenWidth = (input && input.screenWidth) || 0;
    const screenHeight = (input && input.screenHeight) || 0;
    const drawerWidth = (input && input.drawerWidth) || 0;
    const margin = (input && input.margin) || 0;
    const edgeMargin = (input && input.edgeMargin !== undefined)
        ? input.edgeMargin : margin;
    const chromeThickness = (input && input.chromeThickness) || 0;
    if (screenWidth <= 0 || screenHeight <= 0)
        return {
            scale: 1, x: 0, y: 0, width: screenWidth, height: screenHeight,
            area: { x: 0, y: 0, width: screenWidth, height: screenHeight }
        };

    const area = usableArea(input);
    // Two margins horizontally (outside the desktop, and between the desktop
    // and the drawer). Vertically the desktop gives up a whole band on each
    // side, and the band is ASYMMETRIC: an edge margin, the chrome, and a full
    // margin - the tight gap on the outside where the toolbar floats against
    // the screen, the generous one on the inside between it and the desktop.
    //
    // Symmetric was the wrong shape. This axis is the one that binds on a wide
    // screen, so both outer margins come straight off the desktop the mode
    // exists to show: at 5120x1440 the symmetric band cost 24px of desktop
    // height and 85px of width to put air above a toolbar that already floats
    // over the wallpaper. With no chrome the band collapses back to one margin,
    // which is what the geometry was before the chrome existed.
    const band = chromeThickness > 0
        ? edgeMargin + chromeThickness + margin : margin;
    // Horizontally, left to right: a margin, the desktop, a margin, the
    // drawer, and the drawer's own edge gap. The last term is what stops the
    // open drawer sitting flush on the screen's edge - it was missing, so the
    // panel had a rounded right corner against nothing.
    const roomX = area.width - drawerWidth - margin * 2
        - (drawerWidth > 0 ? edgeMargin : 0);
    const roomY = area.height - band * 2;
    const scale = Math.max(MIN_SCALE,
        Math.min(MAX_SCALE, roomX / screenWidth, roomY / screenHeight));
    const width = screenWidth * scale;
    const height = screenHeight * scale;

    return {
        scale: scale,
        // Centred in the usable area on both axes. With no insets that is the
        // screen's centre and `atProgress` is a concentric shrink: the offset
        // is linear in the scale, so `x * t` is exactly the centring offset of
        // the intermediate scale and the four margins stay equal in pairs on
        // every frame. With insets the destination is off the screen's centre
        // by half their difference, so what `atProgress` interpolates is a
        // straight line from the whole screen to the card - every corner still
        // travels straight, and the four margins are equal in pairs against the
        // USABLE AREA at rest.
        x: area.x + (area.width - width) / 2,
        y: area.y + (area.height - height) / 2,
        width: width,
        height: height,
        area: area,
        // Carried on the geometry so `drawerTravel` and `drawerRect` spend the
        // same reservation this size was derived from. Taking them as fresh
        // arguments instead would be two fields that must agree: a caller
        // passing a different width there than here reserves one slot and
        // opens another into it, and only the machine where the two differ
        // ever sees it.
        drawer: drawerWidth,
        margin: margin,
        edgeMargin: edgeMargin
    };
}

// How far LEFT the desktop travels when the drawer is fully open: whatever the
// centred desktop's free side cannot absorb of the drawer's slot.
//
// The slot is `edgeMargin + drawer + margin` against the usable area's right
// edge - the drawer's own gap from the screen edge, the drawer, and the gap
// between it and the desktop, which is exactly the room `viewportGeometry`
// reserved in the SIZE. A centred desktop already has
// `(area.width - width) / 2` free on that side, so the travel is the
// difference, floored at zero for the screens where the ceiling left more
// room than the slot needs.
//
// This is the ONLY thing about the transform the drawer's state may reach
// (spec §1.3): the scale and the size take the drawer's WIDTH whether or not
// it is open, so opening it is a two-number translation and nothing under the
// cursor is rescaled mid-gesture.
function drawerTravel(geometry) {
    if (!geometry || !(geometry.width > 0) || !geometry.area)
        return 0;
    const free = (geometry.area.width - geometry.width) / 2;
    const edge = geometry.edgeMargin !== undefined
        ? geometry.edgeMargin : (geometry.margin || 0);
    return Math.max(0,
        (geometry.drawer || 0) + (geometry.margin || 0) + edge - free);
}

// Where a chrome piece sits in its band, as a FRACTION of the band's slack
// rather than as a pixel offset from the edge.
//
// A fraction because the band has no height at progress 0 - it grows out of
// nothing as the desktop shrinks away from it - and a piece placed at a fixed
// `edgeMargin` from the area's edge would be sitting fully on screen before the
// mode had started. At a fraction it is parked off the edge at 0 and lands at
// exactly `edgeMargin` at 1, with no Behavior of its own; a piece whose target
// moves every frame must not have one (b710ef731).
//
// The band is `edgeMargin + chrome + margin`, so its slack is
// `edgeMargin + margin` and the piece starts `edgeMargin` into it. The BOTTOM
// band is the mirror, which is `1 - this`: from the card's edge it is the
// margin first and the edge gap last.
function chromeBandFraction(geometry) {
    if (!geometry)
        return 0.5;
    const margin = geometry.margin || 0;
    const edge = geometry.edgeMargin !== undefined ? geometry.edgeMargin : margin;
    const slack = edge + margin;
    return slack > 0 ? edge / slack : 0.5;
}

// The entry and exit animation, expressed as one scalar the shell can put a
// single `Behavior` on. Interpolating the geometry rather than animating three
// properties separately is what keeps the desktop's corner travelling in a
// straight line, and it means the transform's inputs move together or not at
// all - there is no frame in which the scale has arrived and the offset has
// not.
//
// The offset is scaled by the SAME t as the scale. With no insets that makes
// the shrink concentric rather than merely centred at the end: a centred
// geometry's `x` is `screenWidth * (1 - scale) / 2`, which is linear in
// `(1 - scale)`, so `x * t` is the exact centring offset for the intermediate
// scale `1 + (scale - 1) * t`, and the desktop's four margins are equal in
// pairs at every point of the animation. With insets the destination is not the
// screen's centre, so that particular symmetry cannot hold mid-flight and is
// not claimed; what does hold either way, and is what the eye follows, is that
// every corner of the desktop travels in a straight line, because both terms of
// each corner's position are linear in `t`.
// `drawerShift` is the CURRENT applied travel - `drawerTravel` times the
// drawer's own animated scalar, multiplied in by the caller - and it reaches
// only `x`. It rides the same `t` as everything else, so at progress 0 the
// transform is the identity whatever the drawer's scalar still holds: the exit
// lands on the untransformed desktop even if the two animations are mid-flight
// together.
function atProgress(geometry, progress, drawerShift) {
    const t = Math.max(0, Math.min(1, progress || 0));
    return {
        scale: 1 + (geometry.scale - 1) * t,
        x: (geometry.x - (drawerShift || 0)) * t,
        y: geometry.y * t
    };
}

// Where the desktop is ON SCREEN at a given progress - the rectangle the mode's
// chrome frames.
//
// It comes from the same `atProgress` the transform is built out of rather than
// from the transform's own terms, so the card's corner, its border and its
// shadow cannot end up a pixel off the desktop they belong to. That is the same
// rule ClockDepthCutout is one component for: two hand-written copies of a
// registration drift, and the drift is invisible because both look plausible.
//
// At progress 0 this is the whole screen at 0,0, which is what makes "the
// chrome stands down completely on exit" a property of the arithmetic rather
// than of a `visible` binding someone has to remember.
function cardRect(geometry, progress, screenWidth, screenHeight, drawerShift) {
    const applied = atProgress(geometry, progress, drawerShift);
    return {
        x: applied.x,
        y: applied.y,
        width: screenWidth * applied.scale,
        height: screenHeight * applied.scale
    };
}

// Where the chrome's two bands live at a given progress: the usable area,
// closing in from the whole screen at the same rate the desktop shrinks out of
// it. The toolbar is centred between this rectangle's top edge and the card's,
// the tab bar between the card's bottom edge and this one's.
//
// Interpolated rather than fixed at the usable area for the same reason the
// card is: at progress 0 the two rectangles coincide, so both bands have zero
// height and both pieces of chrome are parked half off screen and arrive WITH
// the desktop rather than sliding in from wherever the bar happens to end. A
// fixed usable area would park the toolbar just below the bar, visible from the
// first frame of the entry if either stand-down gate were ever lost.
function areaRect(geometry, progress, screenWidth, screenHeight) {
    const t = Math.max(0, Math.min(1, progress || 0));
    const area = geometry.area || { x: 0, y: 0, width: screenWidth, height: screenHeight };
    return {
        x: area.x * t,
        y: area.y * t,
        width: screenWidth + (area.width - screenWidth) * t,
        height: screenHeight + (area.height - screenHeight) * t
    };
}

// Where the drawer is at a given pair of progresses: the reveal, expressed as
// geometry only.
//
// The right edge is pinned to the usable area's and the WIDTH is what animates,
// so the panel slides in from the edge - and because the chrome surface's input
// mask tracks exactly x/y/width/height, a closed drawer is a zero-width rect
// and takes no clicks from whatever panel lives on that edge. That is the same
// collapse rule BarPopupOverlay's card follows, reached through the reveal
// rather than through a second gate someone has to remember.
//
// The drawer's own scalar is multiplied by the MODE's, so at progress 0 there
// is no drawer whatever `drawerProgress` still holds - "the chrome stands down
// completely on exit" stays a property of the arithmetic for this piece too.
//
// It spans exactly the card's band (same y, same height), which needs no shift
// term: the drawer's travel moves the desktop sideways and sideways does not
// change y or height.
//
// It slides out from `edgeMargin` in from the area's right edge rather than
// from the edge itself, so the panel keeps a gap on the side it opens against.
// Expressed as an offset on the ORIGIN rather than a smaller width, because the
// width is the reveal and the reveal must still reach the drawer's full size.
//
// The drawer's scalar is NOT clamped to 1, and that asymmetry is the whole
// point of this line. `elementMove`'s curve overshoots to 1.0139 at 280ms and
// only comes back inside 1 at the end of its 500ms, so `Math.min(1, ...)` froze
// the panel at its full width for the last 271ms of every open while the
// desktop's own `drawerTravel * editDrawerProgress` - which nothing clamps -
// went on overshooting and settling. One gesture, two halves, two effective
// curves: measured on the real Behavior, the panel's last drawn movement was at
// 226ms and the desktop's was at 497ms. Letting the reveal overshoot with it
// costs ~1.4% of the drawer's width, which lands inside the `edgeMargin` gap
// the panel already keeps against the screen edge.
//
// The floor stays. Run backwards the same curve undershoots to -0.0139, and a
// negative width is not an expressive settle - it is a rect the input mask
// cannot build. The desktop is free to undershoot past its resting x, because
// that IS the settle; the panel simply has nowhere further to go once it is
// gone.
function drawerRect(geometry, progress, drawerProgress, screenWidth, screenHeight) {
    const t = Math.max(0, Math.min(1, progress || 0));
    const p = Math.max(0, drawerProgress || 0) * t;
    const area = areaRect(geometry, progress, screenWidth, screenHeight);
    const card = cardRect(geometry, progress, screenWidth, screenHeight);
    const width = (geometry.drawer || 0) * p;
    const edge = geometry.edgeMargin !== undefined
        ? geometry.edgeMargin : (geometry.margin || 0);
    return {
        x: area.x + area.width - edge - width,
        y: card.y,
        width: width,
        height: card.height
    };
}

// Is a SCREEN point on the drawer's reveal?
//
// One spelling, because the same rectangle answers the two halves of one
// gesture and they run in opposite directions. A row dragged OUT of the drawer
// and let go back over it is the gesture being ABANDONED; a widget dragged in
// off the desktop and let go over it is the widget being REMOVED. Two
// hand-written bounds checks would be two answers to "is the pointer on the
// drawer", and the second one is the one nobody looks at.
//
// "The drawer is open" needs no term of its own: a closed drawer is a
// zero-width rect - `drawerRect` animates the WIDTH precisely so the surface's
// input mask collapses with it - so the emptiness test below is the same
// question asked of the same number.
//
// Written against the four fields rather than against a type, so a caller may
// hand in this module's own answer or the QML `rect` a surface stored it in.
function pointInDrawerReveal(reveal, x, y) {
    if (!reveal)
        return false;
    const width = reveal.width || 0;
    const height = reveal.height || 0;
    if (!(width > 0) || !(height > 0))
        return false;
    return x >= reveal.x && x <= reveal.x + width
        && y >= reveal.y && y <= reveal.y + height;
}

// The inverse of the one transform, for the drop: a release from the drawer
// arrives in SCREEN coordinates and the store speaks canvas ones. Composed out
// of `atProgress` rather than written as its own arithmetic so the two
// directions cannot drift apart - a forward map and a hand-inverted copy of it
// are two fields that must agree.
function canvasPointFromScreen(geometry, progress, drawerShift, screenX, screenY) {
    const applied = atProgress(geometry, progress, drawerShift);
    if (!(applied.scale > 0))
        return { x: screenX, y: screenY };
    return {
        x: (screenX - applied.x) / applied.scale,
        y: (screenY - applied.y) / applied.scale
    };
}

// Where a widget dropped from the drawer is stored: its box centred on the
// pointer, snapped to the drag's own 12px lattice, clamped inside the screen.
//
// Snap first, clamp second - the ordering AbstractWidget spells out, because
// clamp-then-snap rounds an edge drop back off its bound by up to half a cell.
// Clamped at the WRITE because this is a write with no release to clamp it:
// spec §8.3 places an added widget the moment it is added, and an unclamped
// store is 705e9006d's defect (a real store held a widget at x: -852).
//
// A widget with no resolvable size yet - the content-sized path, where the
// pixel size exists only once the widget instantiates - is a point at the
// pointer, but its CLAMP treats it as at least one cell: zero keeps the
// centring exact, while a stored point at exactly the screen's edge is
// guaranteed to disagree with the clamped position the widget is then drawn
// at (705e9006d's store/drawn disagreement, transiently, on every mount until
// the user next drags it). One cell is the least anything on the lattice
// occupies.
function dropPosition(input) {
    const grid = (input && input.gridSize) || 12;
    const width = (input && input.widgetWidth) || 0;
    const height = (input && input.widgetHeight) || 0;
    const screenWidth = (input && input.screenWidth) || 0;
    const screenHeight = (input && input.screenHeight) || 0;
    const snap = value => Math.round(value / grid) * grid;
    const x = snap(((input && input.canvasX) || 0) - width / 2);
    const y = snap(((input && input.canvasY) || 0) - height / 2);
    return {
        x: Math.max(0, Math.min(screenWidth - Math.max(width, grid), x)),
        y: Math.max(0, Math.min(screenHeight - Math.max(height, grid), y))
    };
}

// ── Widget size stepper ─────────────────────────────────────────────────────
// The menu's Size row walks these detents (factors) rather than the grip's
// continuous range: a stepper wants values you can name. The range is the
// grip's own (50-200 %), so the two never disagree about what is allowed.
var SIZE_STEPS = [0.5, 0.75, 1, 1.25, 1.5, 2];

// The next detent from `current` in `direction` (-1 / +1); null at either end.
// An off-detent value (the grip is continuous) first snaps to the nearest one,
// then steps, so a 1.66 widget reads 150 % and "+" makes it 200 %.
function steppedScale(current, direction) {
    var steps = SIZE_STEPS;
    var nearest = 0;
    for (var i = 1; i < steps.length; i++) {
        if (Math.abs(steps[i] - current) < Math.abs(steps[nearest] - current))
            nearest = i;
    }
    var next = nearest + (direction < 0 ? -1 : 1);
    if (next < 0 || next >= steps.length)
        return null;
    return steps[next];
}

// The detent a continuous factor reads as, for the row's label.
function nearestSizeStep(current) {
    var steps = SIZE_STEPS;
    var nearest = steps[0];
    for (var i = 1; i < steps.length; i++) {
        if (Math.abs(steps[i] - current) < Math.abs(nearest - current))
            nearest = steps[i];
    }
    return nearest;
}

// ---- the bar, edited in place (stage 6) ------------------------------------
//
// The bar's three lists are laid out along one axis, and a drag between them
// answers two questions: which list, and which stored insertion index. `slots`
// are the DRAWN widgets other than the dragged one, each with its list, its
// index in the stored list (hidden entries included, so the answer is a
// stored index and needs no visible-to-stored mapping) and its scene centre;
// `anchors` are three stand-in points for a list with nothing drawn in it -
// without one an empty list could never win a drop. Nearest is decided along
// the axis only: every slot in a vertical bar has the same x.
function barDropTarget(slots, anchors, point, axis) {
    if (!point) return null;
    var best = null;
    var bestDistance = Infinity;
    var seen = [false, false, false];
    var list = slots || [];
    for (var i = 0; i < list.length; i++) {
        var slot = list[i];
        if (!slot || !slot.centre) continue;
        seen[slot.bucket] = true;
        var distance = Math.abs(point[axis] - slot.centre[axis]);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = { bucket: slot.bucket, index: slot.index + (point[axis] > slot.centre[axis] ? 1 : 0) };
        }
    }
    var stand = anchors || [];
    for (var b = 0; b < 3; b++) {
        if (seen[b] || !stand[b]) continue;
        var anchorDistance = Math.abs(point[axis] - stand[b][axis]);
        if (anchorDistance < bestDistance) {
            bestDistance = anchorDistance;
            best = { bucket: b, index: 0 };
        }
    }
    return best;
}

// An insertion index counts a GAP and a move destination counts a SLOT: taking
// the dragged item out first shifts every gap past it one place down.
function moveTargetForInsertion(from, insertion) {
    return insertion > from ? insertion - 1 : insertion;
}
