.pragma library
.import "QuickToggleCatalog.js" as Catalog

var sizeCache = Object.create(null);
function sizes(type, columns) {
    var key = type + ":" + columns;
    if (sizeCache[key]) return sizeCache[key];
    var result = [];
    var minW = Catalog.kind(type) === "toggle" ? 0 : 1;
    for (var h = 1; h <= 8; h++) {
        for (var w = minW; w <= columns; w++) {
            if (Catalog.isSizeAllowed(type, w, h, columns))
                result.push([w, h]);
        }
    }
    if (result.length === 0)
        result.push(Catalog.normalizeSize(type, 1, 1, columns));
    sizeCache[key] = result;
    return result;
}

function bounds(type, columns) {
    var allowed = sizes(type, columns);
    var result = { minW: columns, maxW: 1, minH: 8, maxH: 1 };
    allowed.forEach(function(size) {
        result.minW = Math.min(result.minW, size[0]);
        result.maxW = Math.max(result.maxW, size[0]);
        result.minH = Math.min(result.minH, size[1]);
        result.maxH = Math.max(result.maxH, size[1]);
    });
    return result;
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

function pixels(startWidth, startHeight, dx, dy, cellWidth, cellHeight, spacing, limits, minHeight) {
    var minPixelWidth = limits.minW === 0 ? cellHeight : limits.minW * (cellWidth + spacing) - spacing;
    var maxPixelWidth = limits.maxW * (cellWidth + spacing) - spacing;
    var minPixelHeight = limits.minH === 1 ? minHeight : limits.minH * (cellHeight + spacing) - spacing;
    var maxPixelHeight = limits.maxH * (cellHeight + spacing) - spacing;
    return {
        width: clamp(startWidth + dx, minPixelWidth, maxPixelWidth),
        height: clamp(startHeight + dy, minPixelHeight, maxPixelHeight)
    };
}

function spanFromPixelWidth(pixelWidth, cellWidth, cellHeight, spacing) {
    if (pixelWidth <= cellHeight)
        return 0;
    if (pixelWidth <= cellWidth)
        return (pixelWidth - cellHeight) / Math.max(1, cellWidth - cellHeight);
    return 1 + (pixelWidth - cellWidth) / Math.max(1, cellWidth + spacing);
}

function spanFromPixelHeight(pixelHeight, cellHeight, spacing) {
    if (pixelHeight <= cellHeight)
        return 1;
    return 1 + (pixelHeight - cellHeight) / Math.max(1, cellHeight + spacing);
}

// Hysteresis affects only packing. The visible surface is never quantized.
function candidate(type, width, height, columns, current) {
    var allowed = sizes(type, columns);
    function distance(size) {
        return Math.pow(width - size[0], 2) + Math.pow(height - size[1], 2);
    }
    var best = current;
    var cost = distance(current);
    allowed.forEach(function(size) {
        var nextCost = distance(size);
        var band = 0.24 * (Math.abs(size[0] - current[0]) + Math.abs(size[1] - current[1]));
        if (nextCost + band < cost) {
            best = size;
            cost = nextCost;
        }
    });
    return best;
}

function mix(a, b, progress) {
    return a + (b - a) * progress;
}

function progress(value, start, end) {
    var t = clamp((value - start) / Math.max(0.001, end - start), 0, 1);
    return t * t * (3 - 2 * t);
}
