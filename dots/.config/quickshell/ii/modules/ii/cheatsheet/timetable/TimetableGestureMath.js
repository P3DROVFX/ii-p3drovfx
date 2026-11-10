.pragma library

// Pure geometry for the timetable's pointer gestures (move, resize, create).
// No QML types live here so tests/timetable_gesture_math.test.cjs can load it
// directly. Every minute value is minutes since midnight; every range is
// half-open: [start, end).

function clampMinute(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function snapMinutes(minutes, step) {
    return Math.round(minutes / step) * step;
}

// Grid geometry: the time at a pointer position inside the grid, unsnapped.
function minutesAtY(y, gridStart, pixelsPerMinute) {
    return gridStart + y / pixelsPerMinute;
}

// Column under an x coordinate. Columns sit at i * stride; a pointer in the
// gutter or past the last column resolves to the nearest one.
function dayIndexAt(x, stride, dayCount) {
    if (dayCount <= 0 || stride <= 0)
        return -1;
    return clampMinute(Math.floor(x / stride), 0, dayCount - 1);
}

// Moving keeps the duration. The block's top follows the pointer minus the
// offset it had when grabbed, snaps to the step and stops at the grid edges.
function movedRange(pointerMinutes, grabMinutes, duration, gridStart, gridEnd, step) {
    const latest = gridEnd - duration;
    const start = clampMinute(snapMinutes(pointerMinutes - grabMinutes, step), gridStart, Math.max(gridStart, latest));
    return { start: start, end: start + duration };
}

// Dragging the bottom edge: the end follows the pointer, one step at least.
function resizedEnd(pointerMinutes, start, gridEnd, step) {
    return clampMinute(snapMinutes(pointerMinutes, step), start + step, gridEnd);
}

// Dragging the top edge: the start follows the pointer, one step at least.
function resizedStart(pointerMinutes, end, gridStart, step) {
    return clampMinute(snapMinutes(pointerMinutes, step), gridStart, end - step);
}

// Drag-to-create: the pressed slot anchors one edge, the pointer drives the
// other. Dragging upwards turns the anchor into the end.
function createdRange(anchorMinutes, pointerMinutes, gridStart, gridEnd, step) {
    const anchor = clampMinute(snapMinutes(anchorMinutes, step), gridStart, gridEnd - step);
    const pointer = clampMinute(snapMinutes(pointerMinutes, step), gridStart, gridEnd);
    if (pointer >= anchor)
        return { start: anchor, end: Math.max(anchor + step, pointer) };
    return { start: pointer, end: anchor };
}

// A press without a drag on an empty slot: a block of `duration` minutes.
function clickedRange(anchorMinutes, gridStart, gridEnd, step, duration) {
    const start = clampMinute(snapMinutes(anchorMinutes, step), gridStart, gridEnd - step);
    return { start: start, end: Math.min(gridEnd, start + duration) };
}

// Manhattan distance, so a diagonal wobble counts the same as a straight move.
function crossedThreshold(dx, dy, threshold) {
    return Math.abs(dx) + Math.abs(dy) >= threshold;
}
