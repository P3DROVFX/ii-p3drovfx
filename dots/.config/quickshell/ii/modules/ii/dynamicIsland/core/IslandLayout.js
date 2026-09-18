.pragma library

/**
 * Slot arbitration and cluster geometry for the Dynamic Island.
 *
 * Everything here is a pure function of (activities, options), so the whole policy is
 * checkable without QML, a compositor or a running shell -
 * scripts/tests/test_island_layout.cjs covers it.
 *
 * The island has at most three slots: one centre and two sides. The rules below decide
 * who sits where; the QML side only animates the result.
 */

/**
 * Lower rank wins a contested slot.
 *
 * Announcements deliberately outrank ongoing activities. A transient *is* the thing that
 * just happened and it leaves on its own after a couple of seconds, so letting a running
 * agent or a playing track keep the stage would mean the user never sees the workspace
 * they just switched to. It takes the stage briefly and hands it straight back - which is
 * both what the old notch did and how a phone behaves when an alert interrupts Now
 * Playing.
 */
var TIER_RANK = {
    interrupt: 0,   // demands an answer now: search, OSD, an agent asking for approval
    transient: 1,   // a brief announcement: workspace, keyboard, clipboard
    live: 2,        // ongoing and worth watching: a running agent, a transfer
    ambient: 3,     // ongoing background: media
    idle: 4         // the resting face: the clock
};

var SIDES = ["left", "right"];

function tierRank(activity) {
    var rank = TIER_RANK[activity && activity.tier];
    return rank === undefined ? TIER_RANK.transient : rank;
}

function otherSide(side) {
    return side === "left" ? "right" : "left";
}

function preferredSide(activity) {
    return activity && activity.preferredSide === "left" ? "left" : "right";
}

/**
 * Priority order: tier first, then the most recently arrived.
 *
 * Recency breaks ties deliberately - when two announcements of the same kind land
 * together, the newer one is the one the user just caused.
 */
function byPriority(left, right) {
    var delta = tierRank(left) - tierRank(right);
    if (delta !== 0)
        return delta;
    return (right.arrivedAt || 0) - (left.arrivedAt || 0);
}

/**
 * True while an activity is still in its "arrival" window.
 *
 * New activities appear in the centre and only then detach to a side: that is the beat
 * that makes the movement read as one object splitting, rather than something popping
 * into existence off to the side.
 */
function isSettling(activity, now) {
    if (!activity || !activity.canDetach)
        return false;
    var settle = activity.settleMs === undefined ? 0 : activity.settleMs;
    if (settle <= 0)
        return false;
    return (now - (activity.arrivedAt || 0)) < settle;
}

function findById(activities, id) {
    for (var i = 0; i < activities.length; i++) {
        if (activities[i].id === id)
            return activities[i];
    }
    return null;
}

/**
 * Who owns the centre.
 *
 * The centre is the island's subject, so the order is: something interrupting, then
 * whatever just arrived and is still settling, then anything that cannot live on a side
 * at all, then the resting face, then simply the highest priority left.
 */
function pickCenter(activities, options) {
    if (activities.length === 0)
        return null;

    var now = options.now || 0;
    var sorted = activities.slice().sort(byPriority);
    var maxIslands = options.maxIslands === undefined ? 3 : options.maxIslands;

    // A pinned activity keeps the centre: the user is hovering or has it expanded, and
    // swapping the surface under the pointer would be hostile.
    if (options.pinnedId) {
        var pinned = findById(sorted, options.pinnedId);
        if (pinned && options.pinnedSlot === "center")
            return pinned;
    }

    var i;
    for (i = 0; i < sorted.length; i++) {
        if (tierRank(sorted[i]) === TIER_RANK.interrupt)
            return sorted[i];
    }

    // With a single slot there is nowhere to detach *to*, so the settle-then-detach beat
    // does not apply: the centre simply shows the most important thing, and the resting
    // face only when nothing else is happening. Running the multi-slot rules here let an
    // activity hold the centre for its settle window and then vanish into the pager
    // while the clock took over - the notch flashed a workspace change and dropped it.
    if (maxIslands <= 1) {
        for (i = 0; i < sorted.length; i++) {
            if (tierRank(sorted[i]) !== TIER_RANK.idle)
                return sorted[i];
        }
        return sorted[0];
    }

    for (i = 0; i < sorted.length; i++) {
        if (isSettling(sorted[i], now))
            return sorted[i];
    }
    for (i = 0; i < sorted.length; i++) {
        if (!sorted[i].canDetach && tierRank(sorted[i]) !== TIER_RANK.idle)
            return sorted[i];
    }
    for (i = 0; i < sorted.length; i++) {
        if (tierRank(sorted[i]) === TIER_RANK.idle)
            return sorted[i];
    }
    return sorted[0];
}

/**
 * Place every activity into { left, center, right, overflow }.
 *
 * `options`:
 *   now        - clock in ms, for the settle window
 *   maxIslands - 1 collapses everything but the centre (the notch style), 2 keeps one
 *                side, 3 is the full cluster
 *   pinnedId / pinnedSlot - an activity the user is interacting with, kept in place
 *   previous   - the last assignment, so nothing moves without a reason
 *
 * Nothing is ever dropped: whatever does not fit is returned in `overflow`, which the
 * centre renders as a dot, and is promoted as soon as a slot frees up.
 */
function assignSlots(activities, options) {
    options = options || {};
    var maxIslands = options.maxIslands === undefined ? 3 : options.maxIslands;
    var previous = options.previous || {};
    var result = { left: null, center: null, right: null, overflow: [] };

    var live = (activities || []).filter(function (activity) {
        return activity && activity.id;
    });
    if (live.length === 0)
        return result;

    var center = pickCenter(live, options);
    result.center = center ? center.id : null;

    var rest = live.filter(function (activity) {
        return !center || activity.id !== center.id;
    }).sort(byPriority);

    if (maxIslands <= 1) {
        result.overflow = rest.map(function (activity) {
            return activity.id;
        });
        return result;
    }

    // A pinned side activity is placed first, so an expanded island never jumps.
    if (options.pinnedId && (options.pinnedSlot === "left" || options.pinnedSlot === "right")) {
        var pinnedSide = findById(rest, options.pinnedId);
        if (pinnedSide) {
            result[options.pinnedSlot] = pinnedSide.id;
            rest = rest.filter(function (activity) {
                return activity.id !== pinnedSide.id;
            });
        }
    }

    var sideBudget = maxIslands - 1;

    function occupiedSides() {
        return (result.left ? 1 : 0) + (result.right ? 1 : 0);
    }

    for (var i = 0; i < rest.length; i++) {
        var activity = rest[i];
        if (occupiedSides() >= sideBudget) {
            result.overflow.push(activity.id);
            continue;
        }

        // Staying put beats being tidy: if it already had a side and that side is free,
        // it keeps it.
        var wanted = null;
        if (previous.left === activity.id && !result.left)
            wanted = "left";
        else if (previous.right === activity.id && !result.right)
            wanted = "right";

        if (!wanted) {
            var first = preferredSide(activity);
            wanted = !result[first] ? first : (!result[otherSide(first)] ? otherSide(first) : null);
        }

        if (wanted)
            result[wanted] = activity.id;
        else
            result.overflow.push(activity.id);
    }

    return result;
}

/**
 * True when the assignment moved an activity between slots, which is what the surface
 * animates as a detach or an absorb.
 */
function slotOf(assignment, id) {
    if (!assignment || !id)
        return null;
    if (assignment.center === id)
        return "center";
    if (assignment.left === id)
        return "left";
    if (assignment.right === id)
        return "right";
    return assignment.overflow && assignment.overflow.indexOf(id) !== -1 ? "overflow" : null;
}

function transitions(previous, next, ids) {
    var moves = [];
    for (var i = 0; i < ids.length; i++) {
        var from = slotOf(previous, ids[i]);
        var to = slotOf(next, ids[i]);
        if (from !== to)
            moves.push({ id: ids[i], from: from, to: to });
    }
    return moves;
}

/**
 * Cluster geometry.
 *
 * Widths are the *target* widths, so the springs in QML always chase a settled layout
 * and never a value that is itself mid-animation. The whole cluster is centred, which is
 * what makes one island growing push its neighbours outward.
 *
 * `sizes` maps slot -> width; a missing or zero width means the slot is absent.
 * Returns a map slot -> { x, width }, plus the cluster's own bounds.
 */
function clusterGeometry(sizes, options) {
    options = options || {};
    var gap = options.gap === undefined ? 8 : options.gap;
    var screenWidth = options.screenWidth || 0;
    var order = ["left", "center", "right"];

    var present = order.filter(function (slot) {
        return sizes && sizes[slot] > 0;
    });
    var total = 0;
    present.forEach(function (slot, index) {
        total += sizes[slot];
        if (index > 0)
            total += gap;
    });

    var geometry = { totalWidth: total, x: Math.round((screenWidth - total) / 2) };
    var cursor = geometry.x;
    present.forEach(function (slot) {
        geometry[slot] = { x: Math.round(cursor), width: sizes[slot] };
        cursor += sizes[slot] + gap;
    });
    order.forEach(function (slot) {
        if (!geometry[slot])
            geometry[slot] = { x: geometry.x + Math.round(total / 2), width: 0 };
    });
    return geometry;
}

/**
 * How strongly two neighbouring shapes bridge into each other.
 *
 * The liquid neck only exists while the shapes are close: at zero gap they are one
 * blob, and past the threshold there is no bridge and therefore nothing to compute.
 */
function gooStrength(gap, options) {
    options = options || {};
    var threshold = options.threshold === undefined ? 26 : options.threshold;
    var maximum = options.maximum === undefined ? 18 : options.maximum;
    if (threshold <= 0 || gap >= threshold)
        return 0;
    if (gap <= 0)
        return maximum;
    return Math.round(maximum * (1 - (gap / threshold)) * 100) / 100;
}
