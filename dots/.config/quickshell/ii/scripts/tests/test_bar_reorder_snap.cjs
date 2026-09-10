// Run with node scripts/tests/test_bar_reorder_snap.cjs
//
// Contract for the bar reorder's frozen-cell target resolver
// (edit_mode.js: buildBarGapCells / resolveBarGap / flushBarGap).
//
// The defect it pins: the drop target used to be re-derived per pointer sample
// from the row's LIVE geometry, and the preview itself moves that geometry —
// the hole opens, a neighbour's centre slides past the pointer, the answer
// flips, the row re-animates. A pointer resting near a boundary flickered
// forever. The gesture now resolves against a table frozen at the press, with
// midpoint-penetration hysteresis and a short accommodation hold (the dock's
// DockReorder pattern). These functions are pure, so the whole policy is
// checkable without QML, a compositor, or a bar widget anywhere.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '../..');
const context = vm.createContext({ Math, Number, JSON, isFinite });
vm.runInContext(
    fs.readFileSync(path.join(root, 'modules/common/functions/edit_mode.js'), 'utf8')
        .replace(/^\.pragma library\s*/, ''),
    context);
const E = context;

// One bucket of three 72px slots, centres at 36/108/180 (storedIndex 0/1/2).
function row(extents = [72, 72, 72]) {
    let at = 0;
    const slots = extents.map((e, i) => {
        at += e / 2;
        const s = { index: i, at, extent: e };
        at += e / 2;
        return s;
    });
    return E.buildBarGapCells([{ bucket: 0, slots }], []);
}

function at(cells, bucket, index) {
    const c = cells.find(x => x.bucket === bucket && x.index === index);
    assert.ok(c, `no cell for bucket ${bucket} index ${index}`);
    return c.at;
}

// ── The table ───────────────────────────────────────────────────────────────

{
    // One cell per physical gap: before the first, between each pair, after
    // the last. Four gaps for three slots.
    const cells = row();
    assert.equal(cells.length, 4);
    // Keys are strings across the vm boundary; compare by identity, not by
    // prototype (assert.deepEqual on vm-created arrays is reference-strict).
    assert.equal(cells.map(c => `${c.bucket}:${c.index}`).join(' '), '0:0 0:1 0:2 0:3');
}

{
    // Sorted along the axis whatever order the groups arrived in — the
    // controller walks buckets 0/1/2, but the row runs left to right.
    const cells = E.buildBarGapCells(
        [{ bucket: 2, slots: [{ index: 0, at: 900, extent: 40 }] }],
        [{ bucket: 0, at: 12 }]);
    assert.ok(cells.every((c, i) => i === 0 || cells[i - 1].at <= c.at));
}

{
    // A bucket with nothing drawn still answers drops, through its stand-in.
    const cells = E.buildBarGapCells(
        [{ bucket: 0, slots: [{ index: 0, at: 36, extent: 72 }] }],
        [{ bucket: 1, at: 480 }]);
    assert.ok(cells.some(c => c.bucket === 1 && c.index === 0));
}

// ── First sample decides, boundary does not flip ────────────────────────────

{
    const cells = row();
    const state = E.createBarDragState();
    const r1 = E.resolveBarGap(cells, 100, state, { now: 0 });
    assert.equal(r1.cell.index, 1); // 100 sits past the 0:1 cell, nearest of them
    const r2 = E.resolveBarGap(cells, 101, state, { now: 4 });
    assert.equal(r2.changed, false); // a sample's jitter must not move anything
}

{
    // A pointer parked exactly on the midpoint between two cells: the nearest
    // match is a coin flip per pixel, so hysteresis decides ONCE and holds.
    const cells = row();
    const state = E.createBarDragState();
    const mid = (at(cells, 0, 1) + at(cells, 0, 2)) / 2;
    let flips = 0;
    let last = null;
    for (let i = 0; i < 40; i++) {
        const jitter = Math.sin(i) * 0.6; // sub-pixel noise, the flicker input
        const r = E.resolveBarGap(cells, mid + jitter, state, { now: i * 16, hysteresis: 0.25, settleMs: 420 });
        if (last !== null && r.cell.index !== last) flips++;
        last = r.cell.index;
    }
    assert.equal(flips, 0, `boundary chatter survived: ${flips} flips`);
}

// ── A decided sweep does move ───────────────────────────────────────────────

{
    // A decided sweep: crossing the boundary AND travelling a full cell gap
    // from the anchor is already deliberate, so the hold window must not
    // swallow it. The anchor travels with the last applied decision.
    const cells = row();
    const state = E.createBarDragState();
    E.resolveBarGap(cells, 20, state, { now: 0, hysteresis: 0.25, settleMs: 420 });
    const r = E.resolveBarGap(cells, 100, state, { now: 32, hysteresis: 0.25, settleMs: 420 });
    assert.equal(r.changed, true);
    assert.equal(r.cell.index, 1);
}

{
    // Slow creep across a boundary inside the hold: the decision waits, then
    // the release takes it — the pointer aimed there, so that is where it lands.
    const cells = row();
    const state = E.createBarDragState();
    E.resolveBarGap(cells, 30, state, { now: 0, hysteresis: 0.25, settleMs: 420 });
    const boundary = (at(cells, 0, 0) + at(cells, 0, 1)) / 2 + (at(cells, 0, 1) - at(cells, 0, 0)) * 0.25;
    const held = E.resolveBarGap(cells, boundary + 1, state, { now: 100, hysteresis: 0.25, settleMs: 420 });
    assert.equal(held.cell.index, 0, 'hold window must keep the previous decision on screen');
    assert.ok(state.pending, 'the crossed cell must be remembered, not dropped');
    assert.equal(E.flushBarGap(state), true);
    assert.equal(state.chosen.index, 1, 'flush must land where the pointer last aimed');
    assert.equal(E.flushBarGap(state), false, 'and only once');
}

{
    // Past the hold window the same crossing applies immediately: accommodation
    // is a debounce, never a lock.
    const cells = row();
    const state = E.createBarDragState();
    E.resolveBarGap(cells, 30, state, { now: 0, hysteresis: 0.25, settleMs: 420 });
    const boundary = (at(cells, 0, 0) + at(cells, 0, 1)) / 2 + (at(cells, 0, 1) - at(cells, 0, 0)) * 0.25;
    const late = E.resolveBarGap(cells, boundary + 1, state, { now: 500, hysteresis: 0.25, settleMs: 420 });
    assert.equal(late.changed, true);
    assert.equal(late.cell.index, 1);
}

// ── Uneven cells (a wide widget beside icons) ───────────────────────────────

{
    // An icon (44px), a wide widget (140px), an icon (44px). Crossing INTO the
    // wide neighbour's territory must be measured by ITS own penetration, not
    // a fixed pixel margin: the same 30px that decides an icon is a drift for
    // a widget.
    const cells = E.buildBarGapCells([{
        bucket: 0,
        slots: [
            { index: 0, at: 22, extent: 44 },
            { index: 1, at: 114, extent: 140 },
            { index: 2, at: 246, extent: 44 },
        ],
    }], []);
    const state = E.createBarDragState();
    E.resolveBarGap(cells, 22, state, { now: 0, hysteresis: 0.25, settleMs: 0 });
    const mid = (at(cells, 0, 1) + at(cells, 0, 2)) / 2;
    const step = at(cells, 0, 2) - at(cells, 0, 1);
    // Midpoint + 25% of THIS pair's distance (the short icon-to-icon step).
    const r = E.resolveBarGap(cells, mid + step * 0.25 + 0.5, state, { now: 16, hysteresis: 0.25, settleMs: 0 });
    assert.equal(r.changed, true);
    assert.equal(r.cell.index, 2);
}

// ── Degenerate input never crashes a gesture ────────────────────────────────

{
    assert.equal(E.resolveBarGap([], 10, E.createBarDragState(), { now: 0 }), null);
    assert.equal(E.resolveBarGap(null, NaN, E.createBarDragState(), { now: 0 }), null);
    assert.equal(E.flushBarGap(null), false);
    // No state object: an anonymous answer, decided from the geometry alone.
    const cells = row();
    const r = E.resolveBarGap(cells, at(cells, 0, 2), null, {});
    assert.equal(r.cell.index, 2);
}

console.log('bar reorder snap: all assertions passed');
