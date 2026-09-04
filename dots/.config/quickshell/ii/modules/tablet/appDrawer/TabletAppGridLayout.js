.pragma library

// How wide the app grid is and where it sits.
//
// A GridView lays its cells out from its own left edge and leaves whatever does not
// divide evenly as dead space on the right. Anchored across the whole drawer that
// produced a block of icons pushed to one side, with a ragged gap beside the A–Z rail
// that grew and shrank with the tile size — the drawer looked left-aligned because it
// was. The view has to be sized to a whole number of columns, and that block placed.

/// How many whole columns fit in the space left after the rail and the side column.
function columnCount(availableWidth, cellWidth) {
    var cell = Math.max(1, Number(cellWidth) || 1);
    var space = Math.max(0, Number(availableWidth) || 0);
    return Math.max(1, Math.floor(space / cell));
}

/// The grid's own width: whole columns, never wider than the space it has.
function gridWidth(availableWidth, cellWidth) {
    var cell = Math.max(1, Number(cellWidth) || 1);
    var space = Math.max(0, Number(availableWidth) || 0);
    return Math.min(space, columnCount(space, cell) * cell);
}

/// Where that block starts, measured from the body's left edge.
///
/// Centred against the whole body rather than against what the rail leaves, because the
/// rail is a thin overlay on the edge and the eye centres the block against the screen.
/// Clamped so that when the slack is smaller than the reserve — a side column open, a
/// very wide tile — the grid slides left just far enough to clear it rather than running
/// underneath.
function originX(bodyWidth, availableWidth, width) {
    var body = Math.max(0, Number(bodyWidth) || 0);
    var space = Math.max(0, Number(availableWidth) || 0);
    var block = Math.max(0, Number(width) || 0);
    return Math.max(0, Math.min(space - block, Math.round((body - block) / 2)));
}
