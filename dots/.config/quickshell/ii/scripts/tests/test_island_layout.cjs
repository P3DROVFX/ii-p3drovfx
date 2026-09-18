// Run with node scripts/tests/test_island_layout.cjs
//
// Contract for the Dynamic Island's slot arbitration (core/IslandLayout.js).
//
// The island has one centre and two sides, and the rules that decide who sits where are
// the difference between "the island tells a story" and "widgets flicker between
// positions". These are pure functions, so the whole policy is checked here rather than
// by staring at a running shell.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

// Values built inside the vm context carry that realm's prototypes, so strict deepEqual
// rejects them even when the contents match. Compare by value.
function sameValue(actual, expected, message) {
    assert.equal(JSON.stringify(actual), JSON.stringify(expected), message);
}

const root = path.resolve(__dirname, '../..');
const context = vm.createContext({ Math, Number, JSON });
vm.runInContext(
    fs.readFileSync(path.join(root, 'modules/ii/dynamicIsland/core/IslandLayout.js'), 'utf8')
        .replace(/^\.pragma library\s*/, ''),
    context);
const L = context;

const NOW = 100000;

// Activities as the controller hands them over: descriptor fields plus arrival time.
function activity(id, tier, extra) {
    return Object.assign({
        id,
        tier,
        preferredSide: 'right',
        canDetach: true,
        settleMs: 0,
        arrivedAt: NOW - 60000,   // long settled, unless a test says otherwise
    }, extra || {});
}

const tests = [];
function test(name, fn) { tests.push([name, fn]); }

// ─── The centre ──────────────────────────────────────────────────────────────

test('an empty island assigns nothing', () => {
    const out = L.assignSlots([], { now: NOW });
    assert.equal(out.center, null);
    assert.equal(out.left, null);
    assert.equal(out.right, null);
    sameValue(out.overflow, []);
});

test('the clock holds the centre when it is the only activity', () => {
    const out = L.assignSlots([activity('clock', 'idle', { canDetach: false })], { now: NOW });
    assert.equal(out.center, 'clock');
});

test('an interrupt takes the centre from a settled ambient activity', () => {
    const out = L.assignSlots([
        activity('media', 'ambient'),
        activity('osd', 'interrupt', { canDetach: false }),
    ], { now: NOW });
    assert.equal(out.center, 'osd');
    assert.equal(L.slotOf(out, 'media'), 'right', 'media moves to its side, it is not dropped');
});

test('a newly arrived activity appears in the centre, then detaches', () => {
    const arriving = activity('media', 'ambient', { arrivedAt: NOW, settleMs: 2500 });
    const withClock = [activity('clock', 'idle', { canDetach: false }), arriving];

    const onArrival = L.assignSlots(withClock, { now: NOW + 100 });
    assert.equal(onArrival.center, 'media', 'it is the subject while it settles');
    assert.equal(L.slotOf(onArrival, 'clock'), 'right');

    const afterSettle = L.assignSlots(withClock, { now: NOW + 3000 });
    assert.equal(afterSettle.center, 'clock', 'the clock comes back to the centre');
    assert.equal(L.slotOf(afterSettle, 'media'), 'right', 'media detached to its side');
});

test('an activity that cannot detach keeps the centre over one that can', () => {
    const out = L.assignSlots([
        activity('media', 'ambient'),
        activity('search', 'live', { canDetach: false }),
    ], { now: NOW });
    assert.equal(out.center, 'search');
});

test('the most recent of two equals wins the centre', () => {
    const out = L.assignSlots([
        activity('a', 'transient', { arrivedAt: NOW - 5000, canDetach: false }),
        activity('b', 'transient', { arrivedAt: NOW - 100, canDetach: false }),
    ], { now: NOW });
    assert.equal(out.center, 'b');
});

// ─── The sides ───────────────────────────────────────────────────────────────

test('activities take their preferred side', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient', { preferredSide: 'right' }),
        activity('workspaces', 'transient', { preferredSide: 'left' }),
    ], { now: NOW });
    assert.equal(out.center, 'clock');
    assert.equal(out.right, 'media');
    assert.equal(out.left, 'workspaces');
});

test('a taken side falls back to the other one', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient', { preferredSide: 'right' }),
        activity('ai', 'live', { preferredSide: 'right' }),
    ], { now: NOW });
    assert.equal(out.center, 'clock');
    assert.equal(out.right, 'ai', 'the higher tier gets the side it asked for');
    assert.equal(out.left, 'media');
});

test('an announcement outranks whatever is merely ongoing', () => {
    // Otherwise a running agent or a playing track means the user never sees the
    // workspace they just switched to.
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('ai', 'live'),
        activity('workspaces', 'transient', { preferredSide: 'left' }),
    ], { now: NOW, maxIslands: 1 });
    assert.equal(out.center, 'workspaces');
});

test('nothing is ever dropped: the fourth activity overflows', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient'),
        activity('ai', 'live'),
        activity('timer', 'live'),
    ], { now: NOW });
    const placed = [out.center, out.left, out.right].filter(Boolean);
    assert.equal(placed.length, 3, 'never more than three islands');
    assert.equal(out.overflow.length, 1);
    assert.equal(L.slotOf(out, out.overflow[0]), 'overflow');
});

test('overflow is ordered by priority, so the weakest waits', () => {
    // Media is the weakest here on purpose: it is still playing in a second, while the
    // clipboard announcement is gone in two and has to be seen now.
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('ai', 'live'),
        activity('media', 'ambient'),
        activity('clipboard', 'transient'),
    ], { now: NOW });
    sameValue(out.overflow, ['media']);
});

// ─── Stability ───────────────────────────────────────────────────────────────

test('an activity keeps the side it already had', () => {
    const activities = [
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient', { preferredSide: 'right' }),
    ];
    const out = L.assignSlots(activities, {
        now: NOW,
        previous: { center: 'clock', left: 'media', right: null },
    });
    assert.equal(out.left, 'media', 'it does not hop to its preferred side for no reason');
});

test('a hovered island is never moved out from under the pointer', () => {
    const activities = [
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient'),
        activity('osd', 'interrupt', { canDetach: false }),
    ];
    const out = L.assignSlots(activities, {
        now: NOW,
        pinnedId: 'media',
        pinnedSlot: 'right',
    });
    assert.equal(out.right, 'media');
    assert.equal(out.center, 'osd');
});

test('a pinned centre survives an interrupt', () => {
    const out = L.assignSlots([
        activity('dashboard', 'ambient', { canDetach: false }),
        activity('notification', 'interrupt'),
    ], { now: NOW, pinnedId: 'dashboard', pinnedSlot: 'center' });
    assert.equal(out.center, 'dashboard', 'the dashboard the user opened stays put');
    assert.equal(L.slotOf(out, 'notification'), 'right');
});

// ─── The notch style ─────────────────────────────────────────────────────────

test('one island means centre only, everything else overflows', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient'),
        activity('ai', 'live'),
    ], { now: NOW, maxIslands: 1 });
    assert.equal(out.left, null);
    assert.equal(out.right, null);
    assert.equal(out.overflow.length, 2);
});

test('one island keeps the activity instead of dropping it after settling', () => {
    // There is nowhere to detach to, so the settle window must not hand the centre back
    // to the clock: the notch used to flash a workspace change and then lose it.
    const activities = [
        activity('clock', 'idle', { canDetach: false }),
        activity('workspaces', 'transient', { arrivedAt: NOW, settleMs: 700, preferredSide: 'left' }),
    ];
    const whileSettling = L.assignSlots(activities, { now: NOW + 100, maxIslands: 1 });
    assert.equal(whileSettling.center, 'workspaces');

    const afterSettling = L.assignSlots(activities, { now: NOW + 5000, maxIslands: 1 });
    assert.equal(afterSettling.center, 'workspaces',
        'the only slot must keep showing the activity, not the resting face');
});

test('one island shows the announcement over the ongoing activity', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient'),
        activity('clipboard', 'transient'),
    ], { now: NOW, maxIslands: 1 });
    assert.equal(out.center, 'clipboard');
    assert.deepEqual(L.slotOf(out, 'media'), 'overflow');
});

test('one island still prefers the more important activity', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient'),
        activity('osd', 'interrupt', { canDetach: false }),
    ], { now: NOW, maxIslands: 1 });
    assert.equal(out.center, 'osd');
});

test('one island falls back to the resting face when nothing is happening', () => {
    const out = L.assignSlots([activity('clock', 'idle', { canDetach: false })],
                              { now: NOW, maxIslands: 1 });
    assert.equal(out.center, 'clock');
});

test('two islands keep the centre and a single side', () => {
    const out = L.assignSlots([
        activity('clock', 'idle', { canDetach: false }),
        activity('media', 'ambient'),
        activity('ai', 'live'),
    ], { now: NOW, maxIslands: 2 });
    assert.equal([out.left, out.right].filter(Boolean).length, 1);
    assert.equal(out.overflow.length, 1);
});

// ─── Movement ────────────────────────────────────────────────────────────────

test('transitions name the slot change the surface has to animate', () => {
    const before = { center: 'media', left: null, right: null, overflow: [] };
    const after = { center: 'clock', left: null, right: 'media', overflow: [] };
    const moves = L.transitions(before, after, ['media', 'clock']);
    sameValue(moves.find(m => m.id === 'media'), { id: 'media', from: 'center', to: 'right' });
    sameValue(moves.find(m => m.id === 'clock'), { id: 'clock', from: null, to: 'center' });
});

// ─── Geometry ────────────────────────────────────────────────────────────────

test('the cluster is centred on screen', () => {
    const geo = L.clusterGeometry({ center: 200 }, { screenWidth: 1000, gap: 8 });
    assert.equal(geo.totalWidth, 200);
    assert.equal(geo.center.x, 400);
});

test('three islands sit in order with the gap between them', () => {
    const geo = L.clusterGeometry({ left: 40, center: 200, right: 40 }, { screenWidth: 1000, gap: 10 });
    assert.equal(geo.totalWidth, 40 + 10 + 200 + 10 + 40);
    assert.equal(geo.left.x, (1000 - geo.totalWidth) / 2);
    assert.equal(geo.center.x, geo.left.x + 50);
    assert.equal(geo.right.x, geo.center.x + 210);
});

test('an island growing pushes its neighbours outward', () => {
    const before = L.clusterGeometry({ left: 40, center: 200, right: 40 }, { screenWidth: 1000, gap: 10 });
    const after = L.clusterGeometry({ left: 40, center: 200, right: 320 }, { screenWidth: 1000, gap: 10 });
    assert.ok(after.left.x < before.left.x, 'the left island is pushed left');
    assert.ok(after.center.x < before.center.x, 'the centre shifts too, the cluster stays centred');
});

test('an absent slot still reports a collapse point at the cluster centre', () => {
    const geo = L.clusterGeometry({ center: 200 }, { screenWidth: 1000, gap: 8 });
    assert.equal(geo.left.width, 0);
    assert.ok(geo.left.x > 400 && geo.left.x < 600, 'it collapses into the centre, not to x=0');
});

// ─── The liquid neck ─────────────────────────────────────────────────────────

test('the neck is strongest when the shapes touch and gone once they part', () => {
    assert.equal(L.gooStrength(0, { threshold: 26, maximum: 18 }), 18);
    assert.equal(L.gooStrength(26, { threshold: 26, maximum: 18 }), 0);
    assert.equal(L.gooStrength(100, { threshold: 26, maximum: 18 }), 0);
    const half = L.gooStrength(13, { threshold: 26, maximum: 18 });
    assert.ok(half > 8 && half < 10, `expected roughly half strength, got ${half}`);
});

test('the neck weakens monotonically as the gap opens', () => {
    let last = Infinity;
    for (let gap = 0; gap <= 30; gap += 2) {
        const value = L.gooStrength(gap);
        assert.ok(value <= last, `strength rose at gap ${gap}`);
        last = value;
    }
});

let failed = 0;
for (const [name, fn] of tests) {
    try {
        fn();
        console.log(`  ok   ${name}`);
    } catch (error) {
        failed++;
        console.log(`  FAIL ${name}\n       ${error.message}`);
    }
}
console.log(`\n${tests.length - failed}/${tests.length} passed`);
process.exit(failed === 0 ? 0 : 1);
