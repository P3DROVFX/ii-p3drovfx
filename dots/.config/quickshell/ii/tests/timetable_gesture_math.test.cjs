const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const root = path.resolve(__dirname, '..');
const context = vm.createContext({});
vm.runInContext(
    fs.readFileSync(path.join(root, 'modules/ii/cheatsheet/timetable/TimetableGestureMath.js'), 'utf8')
        .replace(/^\.pragma library\s*/, ''),
    context
);
const G = context;

// Results come from another realm; copy them so strict comparison sees plain objects.
const plain = value => JSON.parse(JSON.stringify(value));

const DAY_START = 0;
const DAY_END = 24 * 60;
const STEP = 15;

test('pointer minutes follow the grid scale and start hour', () => {
    // 2 px per minute, grid starting at 08:00.
    assert.equal(G.minutesAtY(0, 8 * 60, 2), 480);
    assert.equal(G.minutesAtY(120, 8 * 60, 2), 540);
});

test('a pointer x resolves to the nearest column, clamped to the grid', () => {
    const stride = 100;
    assert.equal(G.dayIndexAt(0, stride, 7), 0);
    assert.equal(G.dayIndexAt(250, stride, 7), 2);
    assert.equal(G.dayIndexAt(-40, stride, 7), 0);
    assert.equal(G.dayIndexAt(9999, stride, 3), 2);
    assert.equal(G.dayIndexAt(50, stride, 0), -1);
});

test('moving snaps the start to the step and keeps the duration', () => {
    // Grabbed 10 min below the top of a 60 min block, pointer at 10:37.
    const range = G.movedRange(10 * 60 + 37, 10, 60, DAY_START, DAY_END, STEP);
    assert.deepEqual(plain(range), {start: 10 * 60 + 30, end: 11 * 60 + 30});
});

test('moving stops at the grid edges instead of leaving the day', () => {
    assert.deepEqual(plain(G.movedRange(-500, 0, 60, DAY_START, DAY_END, STEP)), {start: 0, end: 60});
    assert.deepEqual(plain(G.movedRange(5000, 0, 60, DAY_START, DAY_END, STEP)), {start: 23 * 60, end: 24 * 60});
});

test('a block longer than the room left still starts at the grid edge', () => {
    const range = G.movedRange(23 * 60, 0, 180, DAY_START, DAY_END, STEP);
    assert.deepEqual(plain(range), {start: 21 * 60, end: 24 * 60});
});

test('resizing the bottom edge never closes a block below one step', () => {
    assert.equal(G.resizedEnd(10 * 60 + 1, 10 * 60, DAY_END, STEP), 10 * 60 + 15);
    assert.equal(G.resizedEnd(11 * 60 + 40, 10 * 60, DAY_END, STEP), 11 * 60 + 45);
    assert.equal(G.resizedEnd(9999, 10 * 60, DAY_END, STEP), DAY_END);
});

test('resizing the top edge never inverts the block', () => {
    // Pointer snaps to 11:00, but the block's top may not pass its own end minus one step.
    assert.equal(G.resizedStart(11 * 60 + 5, 11 * 60, DAY_START, STEP), 10 * 60 + 45);
    assert.equal(G.resizedStart(12 * 60, 11 * 60, DAY_START, STEP), 10 * 60 + 45);
    assert.equal(G.resizedStart(-100, 11 * 60, DAY_START, STEP), DAY_START);
});

test('dragging upwards to create turns the anchor into the end', () => {
    assert.deepEqual(plain(G.createdRange(10 * 60, 9 * 60 + 20, DAY_START, DAY_END, STEP)), {start: 9 * 60 + 15, end: 10 * 60});
});

test('dragging downwards to create keeps the anchor as the start', () => {
    assert.deepEqual(plain(G.createdRange(10 * 60 + 7, 11 * 60 + 40, DAY_START, DAY_END, STEP)), {start: 10 * 60, end: 11 * 60 + 45});
});

test('creating on one slot without moving yields one step, not zero', () => {
    assert.deepEqual(plain(G.createdRange(10 * 60, 10 * 60 + 3, DAY_START, DAY_END, STEP)), {start: 10 * 60, end: 10 * 60 + 15});
});

test('a press without a drag makes an hour block from the snapped slot', () => {
    assert.deepEqual(plain(G.clickedRange(10 * 60 + 5, DAY_START, DAY_END, STEP, 60)), {start: 10 * 60, end: 11 * 60});
    // Past the half-step mark the press rounds up to the next slot.
    assert.deepEqual(plain(G.clickedRange(10 * 60 + 8, DAY_START, DAY_END, STEP, 60)), {start: 10 * 60 + 15, end: 11 * 60 + 15});
    // Right at the end of the day the block is clipped, never past midnight.
    assert.deepEqual(plain(G.clickedRange(23 * 60 + 50, DAY_START, DAY_END, STEP, 60)), {start: 23 * 60 + 45, end: 24 * 60});
});

test('the drag threshold is Manhattan, so a diagonal wobble counts the same as a straight move', () => {
    assert.equal(G.crossedThreshold(3, 0, 5), false);
    assert.equal(G.crossedThreshold(2, 3, 5), true);
    assert.equal(G.crossedThreshold(0, -5, 5), true);
});
