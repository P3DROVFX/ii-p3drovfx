.pragma library

// Columns that balance `count` cells over the rows the width needs, so a set never ends
// with a lone straggler: rows = ceil(n / fit), cols = ceil(n / rows).
function columns(count, width, gap, minCell) {
    if (count <= 0)
        return 1;
    const fit = Math.max(1, Math.floor((width + gap) / (minCell + gap)));
    const rows = Math.ceil(count / Math.min(fit, count));
    return Math.ceil(count / rows);
}

// Width of cell `index`: the cells of a short last row share its whole width.
function cellWidth(index, count, width, gap, cols) {
    const rows = Math.ceil(count / cols);
    const lastRow = rows - 1;
    const inRow = Math.floor(index / cols) === lastRow ? count - cols * lastRow : cols;
    return Math.max(0, Math.floor((width - gap * (inRow - 1)) / inRow));
}

function rowCount(count, cols) {
    return Math.ceil(count / cols);
}
