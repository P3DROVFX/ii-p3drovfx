.pragma library

function integerAtLeastOne(value, fallback) {
    var number = Number(value);
    if (!isFinite(number))
        return fallback;
    return Math.max(1, Math.floor(number));
}

function finiteOrZero(value) {
    var number = Number(value);
    return isFinite(number) ? number : 0;
}

function toArray(value) {
    if (value === null || value === undefined)
        return [];
    if (Array.isArray(value))
        return value.slice();
    var result = [];
    if (typeof value.length === "number") {
        for (var i = 0; i < value.length; i++)
            result.push(value[i]);
    }
    return result;
}
function cloneObject(source) {
    var result = {};
    if (!source || typeof source !== "object")
        return result;
    for (var key in source)
        result[key] = source[key];
    return result;
}

function createOccupancy(columns) {
    var width = integerAtLeastOne(columns, 1);
    return {
        columns: width,
        rows: []
    };
}

function cloneOccupancy(occupancy) {
    var result = {
        columns: occupancy.columns,
        rows: []
    };
    for (var i = 0; i < occupancy.rows.length; i++)
        result.rows.push(occupancy.rows[i].slice());
    return result;
}

function canPlace(occupancy, row, column, width, height) {
    if (!occupancy || row < 0 || column < 0 || width < 1 || height < 1)
        return false;
    if (column + width > occupancy.columns)
        return false;

    for (var rowOffset = 0; rowOffset < height; rowOffset++) {
        var currentRow = occupancy.rows[row + rowOffset];
        if (!currentRow)
            continue;
        for (var columnOffset = 0; columnOffset < width; columnOffset++) {
            if (currentRow[column + columnOffset] === true)
                return false;
        }
    }
    return true;
}

function markOccupied(occupancy, row, column, width, height) {
    var result = cloneOccupancy(occupancy);
    for (var rowOffset = 0; rowOffset < height; rowOffset++) {
        var rowIndex = row + rowOffset;
        while (result.rows.length <= rowIndex)
            result.rows.push(new Array(result.columns).fill(false));
        for (var columnOffset = 0; columnOffset < width; columnOffset++)
            result.rows[rowIndex][column + columnOffset] = true;
    }
    return result;
}

function itemSize(item) {
    var width = Number(item && item.sizeW);
    var height = Number(item && item.sizeH);
    return {
        width: isFinite(width) ? Math.max(1, Math.floor(width)) : 1,
        height: isFinite(height) ? Math.max(1, Math.floor(height)) : 1
    };
}

function firstFit(occupancy, width, height) {
    var row = 0;
    while (true) {
        for (var column = 0; column <= occupancy.columns - width; column++) {
            if (canPlace(occupancy, row, column, width, height))
                return { row: row, column: column };
        }
        row++;
    }
}

function pack(items, columns) {
    var source = toArray(items);
    var occupancy = createOccupancy(columns);
    var result = [];

    for (var index = 0; index < source.length; index++) {
        if (!source[index] || typeof source[index] !== "object")
            continue;

        var dimensions = itemSize(source[index]);
        dimensions.width = Math.min(dimensions.width, occupancy.columns);
        var position = firstFit(occupancy, dimensions.width, dimensions.height);
        occupancy = markOccupied(occupancy, position.row, position.column, dimensions.width, dimensions.height);

        var packedItem = cloneObject(source[index]);
        packedItem.sizeW = dimensions.width;
        packedItem.sizeH = dimensions.height;
        packedItem.row = position.row;
        packedItem.column = position.column;
        packedItem.rowSpan = dimensions.height;
        packedItem.columnSpan = dimensions.width;
        result.push(packedItem);
    }

    return {
        rowsUsed: occupancy.rows.length,
        items: result
    };
}

function rowsUsed(items, columns) {
    return pack(items, columns).rowsUsed;
}

// Quantize from the gesture's immutable origin. Callers must provide a delta
// measured in a stable ancestor coordinate system; measuring inside a resize
// handle that moves with the item creates a resize feedback loop.
function resizeSpanFromDelta(startSpan, deltaPixels, cellSize, spacing, maximumSpan) {
    var start = integerAtLeastOne(startSpan, 1);
    var maximum = Math.max(start, integerAtLeastOne(maximumSpan, start));
    var step = Math.max(1, Number(cellSize) + Number(spacing));
    var delta = Number(deltaPixels);
    if (!isFinite(delta))
        delta = 0;
    return Math.max(1, Math.min(maximum, start + Math.round(delta / step)));
}

// Keep the delegate model in its persisted order and attach only geometry from
// a packed preview. This is deliberately separate from pack(): reordering a
// draft must move existing delegates, never replace/retype them while a mouse
// grab is active.
function positionedItems(items, packed, cellWidth, cellHeight, spacing) {
    var source = toArray(items);
    var packedItems = packed && packed.items ? toArray(packed.items) : [];
    var byId = Object.create(null);
    var stepX = Math.max(1, Number(cellWidth) + Number(spacing));
    var stepY = Math.max(1, Number(cellHeight) + Number(spacing));
    var result = [];

    for (var packedIndex = 0; packedIndex < packedItems.length; packedIndex++) {
        var placement = packedItems[packedIndex];
        if (placement && typeof placement.id === "string")
            byId[placement.id] = placement;
    }

    for (var index = 0; index < source.length; index++) {
        var item = source[index];
        if (!item || typeof item !== "object")
            continue;
        var positioned = cloneObject(item);
        var geometry = byId[item.id];
        if (geometry) {
            positioned.sizeW = geometry.sizeW;
            positioned.sizeH = geometry.sizeH;
            positioned.layoutX = geometry.column * stepX;
            positioned.layoutY = geometry.row * stepY;
        }
        result.push(positioned);
    }
    return result;
}

function findItem(items, id) {
    var source = toArray(items);
    for (var i = 0; i < source.length; i++) {
        if (source[i] && source[i].id === id)
            return i;
    }
    return -1;
}

function copyItems(items) {
    var result = [];
    var source = toArray(items);
    for (var i = 0; i < source.length; i++)
        result.push(cloneObject(source[i]));
    return result;
}

function moveItem(items, fromIndex, toIndex) {
    var result = copyItems(items);
    if (fromIndex < 0 || fromIndex >= result.length || result.length === 0)
        return result;
    var target = Math.max(0, Math.min(integerAtLeastOne(toIndex + 1, 1) - 1, result.length - 1));
    var moved = result.splice(fromIndex, 1)[0];
    result.splice(target, 0, moved);
    return result;
}

function removeItem(items, id) {
    var result = copyItems(items);
    var index = findItem(result, id);
    if (index >= 0)
        result.splice(index, 1);
    return result;
}

function insertItem(items, item, index) {
    var result = copyItems(items);
    var target = Math.max(0, Math.min(integerAtLeastOne(index + 1, 1) - 1, result.length));
    result.splice(target, 0, cloneObject(item));
    return result;
}

function rectanglesOverlap(a, b) {
    return a.row < b.row + b.rowSpan
        && a.row + a.rowSpan > b.row
        && a.column < b.column + b.columnSpan
        && a.column + a.columnSpan > b.column;
}

function validateNoOverlap(packed, columns) {
    if (!packed || !Array.isArray(packed.items))
        return false;
    var cols = integerAtLeastOne(columns, 1);
    var ids = Object.create(null);
    for (var i = 0; i < packed.items.length; i++) {
        var item = packed.items[i];
        if (!item || item.row < 0 || item.column < 0 || item.column + item.columnSpan > cols)
            return false;
        if (item.id !== undefined) {
            if (ids[item.id])
                return false;
            ids[item.id] = true;
        }
        for (var j = i + 1; j < packed.items.length; j++) {
            if (rectanglesOverlap(item, packed.items[j]))
                return false;
        }
    }
    return true;
}

// --- Drag stability -------------------------------------------------------
//
// A pointer parked on the seam between two cells used to make the grid
// oscillate: rounding the drag rectangle to the nearest cell flipped on
// sub-pixel jitter, and every flip swapped two toggles. Two guards make the
// decision sticky, and both live here so the policy stays pure and testable.
//
//   * hysteresis — the cell a drag already owns only concedes once the pointer
//     travels past the midpoint by `hysteresis` of a cell, which turns the
//     boundary into a dead band 2 * hysteresis wide;
//   * a settle lock — right after a swap the reflow is still animating, so a
//     further swap waits out `settleMs` unless the pointer covers a whole cell,
//     which only a deliberate drag does.
//
// The state object belongs to the caller (the edit controller owns one per
// gesture); resolveDragCell only reads it, acceptDragCell writes it.

function createDragCellState() {
    return resetDragCellState({});
}

function resetDragCellState(state) {
    var target = state || {};
    target.valid = false;
    target.row = 0;
    target.column = 0;
    target.changed = false;
    target.changedAt = 0;
    target.changedX = 0;
    target.changedY = 0;
    target.pendingValid = false;
    target.pendingRow = 0;
    target.pendingColumn = 0;
    return target;
}

// Round to a cell index, but let `previous` keep the cell it owns until the
// pointer has travelled past the midpoint by `hysteresis` of a cell.
function quantizeWithHysteresis(value, previous, hysteresis) {
    var position = Number(value);
    if (!isFinite(position))
        position = 0;
    var rounded = Math.round(position);
    if (previous === null || previous === undefined || !isFinite(previous))
        return rounded;
    if (rounded === previous)
        return previous;
    var band = 0.5 + Math.max(0, Math.min(0.49, Number(hysteresis) || 0));
    return Math.abs(position - previous) < band ? previous : rounded;
}

// `geometry.pointerX/pointerY` is the centre of the dragged rectangle in grid
// coordinates. Returns the top-left cell it should occupy plus whether that is
// a new decision worth repacking for: `accepted` false means "nothing to do",
// either because the cell did not change or because the settle lock refused it.
function resolveDragCell(geometry, state, options) {
    var source = geometry || {};
    var config = options || {};
    var columns = integerAtLeastOne(source.columns, 1);
    var columnSpan = Math.min(integerAtLeastOne(source.columnSpan, 1), columns);
    var rowSpan = integerAtLeastOne(source.rowSpan, 1);
    var cellWidth = finiteOrZero(source.cellWidth);
    var cellHeight = finiteOrZero(source.cellHeight);
    var spacing = finiteOrZero(source.spacing);
    var stepX = Math.max(1, cellWidth + spacing);
    var stepY = Math.max(1, cellHeight + spacing);
    var pixelWidth = columnSpan * cellWidth + Math.max(0, columnSpan - 1) * spacing;
    var pixelHeight = rowSpan * cellHeight + Math.max(0, rowSpan - 1) * spacing;
    var centerX = finiteOrZero(source.pointerX);
    var centerY = finiteOrZero(source.pointerY);

    var anchored = !!(state && state.valid);
    var column = Math.max(0, Math.min(columns - columnSpan, quantizeWithHysteresis(
        (centerX - pixelWidth / 2) / stepX,
        anchored ? state.column : null,
        config.hysteresis
    )));
    var row = Math.max(0, quantizeWithHysteresis(
        (centerY - pixelHeight / 2) / stepY,
        anchored ? state.row : null,
        config.hysteresis
    ));

    // `row`/`column` is what the caller should act on; the candidate survives a
    // refusal so a gesture that ends inside the settle window can still be
    // flushed instead of silently dropping the user's last aim.
    var result = {
        row: row, column: column,
        candidateRow: row, candidateColumn: column,
        accepted: true, locked: false
    };
    if (!anchored)
        return result;
    if (row === state.row && column === state.column) {
        result.accepted = false;
        return result;
    }

    var settleMs = Math.max(0, finiteOrZero(config.settleMs));
    if (settleMs > 0 && state.changed && finiteOrZero(config.now) - state.changedAt < settleMs) {
        var travelCells = Math.max(
            Math.abs(centerX - state.changedX) / stepX,
            Math.abs(centerY - state.changedY) / stepY
        );
        var requiredTravel = Number(config.settleTravel);
        if (!isFinite(requiredTravel) || requiredTravel < 0)
            requiredTravel = 1;
        if (travelCells < requiredTravel) {
            result.row = state.row;
            result.column = state.column;
            result.accepted = false;
            result.locked = true;
        }
    }
    return result;
}

// Park a resolution the settle lock refused. The gesture may end before the
// window closes, and the placement the pointer last aimed at must still win.
function deferDragCell(state, cell) {
    var target = state || createDragCellState();
    target.pendingValid = true;
    target.pendingRow = cell.candidateRow;
    target.pendingColumn = cell.candidateColumn;
    return target;
}

// Only a resolution that actually moved something arms the settle lock: an
// accepted cell that packs back to the same order must not freeze the grid.
function acceptDragCell(state, cell, pointerX, pointerY, now, layoutChanged) {
    var target = state || createDragCellState();
    target.valid = true;
    target.row = cell.row;
    target.column = cell.column;
    target.pendingValid = false;
    if (layoutChanged) {
        target.changed = true;
        target.changedAt = finiteOrZero(now);
        target.changedX = finiteOrZero(pointerX);
        target.changedY = finiteOrZero(pointerY);
    }
    return target;
}

function findInsertionIndex(packedItems, row, column, draggedId, columns) {
    var source = toArray(packedItems);
    if (source.length === 0)
        return 0;

    var draggedIndex = findItem(source, draggedId);
    var draggedItem = draggedIndex >= 0 ? source[draggedIndex] : null;
    var draggedWidth = integerAtLeastOne(draggedItem && draggedItem.columnSpan, 1);
    var draggedHeight = integerAtLeastOne(draggedItem && draggedItem.rowSpan, 1);
    var gridColumns = Number(columns);
    if (!isFinite(gridColumns) || gridColumns < 1) {
        gridColumns = 1;
        for (var widthIndex = 0; widthIndex < source.length; widthIndex++) {
            var widthItem = source[widthIndex];
            if (widthItem)
                gridColumns = Math.max(gridColumns, widthItem.column + widthItem.columnSpan);
        }
    }
    gridColumns = Math.max(1, Math.floor(gridColumns));

    var targetRect = {
        row: Math.max(0, Math.floor(Number(row) || 0)),
        column: Math.max(0, Math.min(
            Math.max(0, gridColumns - draggedWidth),
            Math.floor(Number(column) || 0)
        )),
        rowSpan: draggedHeight,
        columnSpan: Math.min(draggedWidth, gridColumns)
    };

    // A large delegate targets every item under its prospective footprint.
    // Moving backward inserts before the first overlap; moving forward inserts
    // after the last one. A 4x1 slider therefore exchanges with a whole row.
    var firstHit = source.length;
    var lastHit = -1;
    for (var hitIndex = 0; hitIndex < source.length; hitIndex++) {
        var hitItem = source[hitIndex];
        if (!hitItem || hitItem.id === draggedId)
            continue;
        if (rectanglesOverlap(targetRect, hitItem)) {
            firstHit = Math.min(firstHit, hitIndex);
            lastHit = Math.max(lastHit, hitIndex);
        }
    }

    if (lastHit >= 0) {
        if (draggedIndex >= 0 && draggedIndex < firstHit)
            return lastHit + 1;
        if (draggedIndex > lastHit)
            return firstHit;

        var draggedComesAfterTarget = draggedItem
            && (draggedItem.row > targetRect.row
                || (draggedItem.row === targetRect.row && draggedItem.column > targetRect.column));
        return draggedComesAfterTarget ? firstHit : lastHit + 1;
    }

    for (var i = 0; i < source.length; i++) {
        var item = source[i];
        if (!item || item.id === draggedId)
            continue;
        if (targetRect.row < item.row
                || (targetRect.row === item.row && targetRect.column < item.column))
            return i;
    }
    return source.length;
}
