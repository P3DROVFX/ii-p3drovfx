.pragma library

function clamp(value, minValue, maxValue) {
    return Math.max(minValue, Math.min(maxValue, value));
}

function logicalWidth(monitor) {
    if (!monitor || typeof monitor.width !== "number" || typeof monitor.height !== "number")
        return 1920;
    const scale = (typeof monitor.scale === "number" && monitor.scale > 0) ? monitor.scale : 1;
    const w = (monitor.transform === 1 || monitor.transform === 3) ? monitor.height : monitor.width;
    return Math.max(1, Math.round(w / scale));
}

function logicalHeight(monitor) {
    if (!monitor || typeof monitor.width !== "number" || typeof monitor.height !== "number")
        return 1080;
    const scale = (typeof monitor.scale === "number" && monitor.scale > 0) ? monitor.scale : 1;
    const h = (monitor.transform === 1 || monitor.transform === 3) ? monitor.width : monitor.height;
    return Math.max(1, Math.round(h / scale));
}

function monitorPosition(monitor, positionsOverride) {
    if (!monitor)
        return { x: 0, y: 0 };
    const overridePos = (positionsOverride && monitor.name && positionsOverride[monitor.name] !== undefined)
        ? positionsOverride[monitor.name]
        : null;
    const x = (overridePos && typeof overridePos.x === "number")
        ? overridePos.x
        : (typeof monitor.x === "number" ? monitor.x : 0);
    const y = (overridePos && typeof overridePos.y === "number")
        ? overridePos.y
        : (typeof monitor.y === "number" ? monitor.y : 0);
    return { x: x, y: y };
}

function computeBounds(monitors, positionsOverride) {
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;

    const list = monitors || [];
    for (let i = 0; i < list.length; ++i) {
        const m = list[i];
        if (!m || typeof m.width !== "number" || typeof m.height !== "number")
            continue;
        const w = logicalWidth(m);
        const h = logicalHeight(m);
        const pos = monitorPosition(m, positionsOverride);
        minX = Math.min(minX, pos.x);
        minY = Math.min(minY, pos.y);
        maxX = Math.max(maxX, pos.x + w);
        maxY = Math.max(maxY, pos.y + h);
    }

    if (minX === Infinity) {
        return {
            minX: 0,
            minY: 0,
            maxX: 1920,
            maxY: 1080,
            width: 1920,
            height: 1080
        };
    }

    return {
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
        width: Math.max(1, maxX - minX),
        height: Math.max(1, maxY - minY)
    };
}

/**
 * Computes a drag-session bounding box that remains invariant during the drag
 * while guaranteeing full workspace room above, below, left, and right of the
 * stationary monitors so monitors can always be stacked vertically or moved around.
 */
function computeDragBounds(monitors, dragIndex, marginFactor) {
    const list = monitors || [];
    const margin = (typeof marginFactor === "number" && marginFactor > 0) ? marginFactor : 1.15;
    const allBounds = computeBounds(list, null);
    const dragged = (dragIndex >= 0 && dragIndex < list.length) ? list[dragIndex] : null;
    if (!dragged)
        return allBounds;

    const dw = logicalWidth(dragged);
    const dh = logicalHeight(dragged);

    let sMinX = Infinity;
    let sMinY = Infinity;
    let sMaxX = -Infinity;
    let sMaxY = -Infinity;

    for (let i = 0; i < list.length; ++i) {
        if (i === dragIndex)
            continue;
        const m = list[i];
        if (!m || typeof m.width !== "number" || typeof m.height !== "number")
            continue;
        const w = logicalWidth(m);
        const h = logicalHeight(m);
        const pos = monitorPosition(m, null);
        sMinX = Math.min(sMinX, pos.x);
        sMinY = Math.min(sMinY, pos.y);
        sMaxX = Math.max(sMaxX, pos.x + w);
        sMaxY = Math.max(sMaxY, pos.y + h);
    }

    if (sMinX === Infinity) {
        sMinX = allBounds.minX;
        sMinY = allBounds.minY;
        sMaxX = allBounds.maxX;
        sMaxY = allBounds.maxY;
    }

    const minX = Math.min(allBounds.minX, sMinX - dw * margin);
    const minY = Math.min(allBounds.minY, sMinY - dh * margin);
    const maxX = Math.max(allBounds.maxX, sMaxX + dw * margin);
    const maxY = Math.max(allBounds.maxY, sMaxY + dh * margin);

    return {
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
        width: Math.max(1, maxX - minX),
        height: Math.max(1, maxY - minY)
    };
}

function computeFitCamera(bounds, canvasWidth, canvasHeight, padding, zoomMultiplier) {
    const pad = (typeof padding === "number" && padding >= 0) ? padding : 24;
    const zoom = (typeof zoomMultiplier === "number" && zoomMultiplier > 0) ? zoomMultiplier : 1.0;

    if (!bounds || isNaN(bounds.width) || isNaN(bounds.height) || bounds.width <= 0 || bounds.height <= 0) {
        return { scale: 0.1, fitScale: 0.1, offsetX: pad, offsetY: pad };
    }
    if (typeof canvasWidth !== "number" || typeof canvasHeight !== "number"
            || canvasWidth <= pad * 2 || canvasHeight <= pad * 2) {
        return { scale: 0.08, fitScale: 0.08, offsetX: pad, offsetY: pad };
    }

    const usableW = canvasWidth - pad * 2;
    const usableH = canvasHeight - pad * 2;
    const scaleX = usableW / bounds.width;
    const scaleY = usableH / bounds.height;
    const fitScale = Math.max(0.005, Math.min(scaleX, scaleY));
    const scale = Math.max(0.005, fitScale * zoom);

    const offsetX = (canvasWidth - bounds.width * scale) / 2 - bounds.minX * scale;
    const offsetY = (canvasHeight - bounds.height * scale) / 2 - bounds.minY * scale;

    return {
        scale: scale,
        fitScale: fitScale,
        offsetX: offsetX,
        offsetY: offsetY
    };
}

function overlapsRect(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}

function checkOverlap(monitors, index) {
    const list = monitors || [];
    const selected = (index >= 0 && index < list.length) ? list[index] : null;
    if (!selected || selected.disabled)
        return false;
    const sw = logicalWidth(selected);
    const sh = logicalHeight(selected);
    const sx = selected.x || 0;
    const sy = selected.y || 0;

    for (let i = 0; i < list.length; ++i) {
        if (i === index)
            continue;
        const other = list[i];
        if (!other || other.disabled)
            continue;
        const ow = logicalWidth(other);
        const oh = logicalHeight(other);
        const ox = other.x || 0;
        const oy = other.y || 0;
        if (sx < ox + ow && sx + sw > ox && sy < oy + oh && sy + sh > oy)
            return true;
    }
    return false;
}

function computeNormalized(monitors, changedIndex, newX, newY) {
    const list = monitors || [];
    const normalized = list.slice().map(monitor => Object.assign({}, monitor));
    if (changedIndex >= 0 && changedIndex < normalized.length && normalized[changedIndex]) {
        normalized[changedIndex].x = Math.round(newX);
        normalized[changedIndex].y = Math.round(newY);
    }

    let minX = Infinity;
    let minY = Infinity;
    for (let i = 0; i < normalized.length; ++i) {
        const m = normalized[i];
        if (!m || m.disabled)
            continue;
        minX = Math.min(minX, m.x || 0);
        minY = Math.min(minY, m.y || 0);
    }

    const offsetX = (minX !== Infinity && minX < 0) ? -minX : 0;
    const offsetY = (minY !== Infinity && minY < 0) ? -minY : 0;
    if (offsetX > 0 || offsetY > 0) {
        for (let i = 0; i < normalized.length; ++i) {
            if (normalized[i]) {
                normalized[i].x = (normalized[i].x || 0) + offsetX;
                normalized[i].y = (normalized[i].y || 0) + offsetY;
            }
        }
    }
    return normalized;
}

function alignToTargets(value, targets, threshold) {
    let bestTarget = null;
    let bestDiff = Infinity;
    for (let i = 0; i < targets.length; ++i) {
        const t = targets[i];
        const diff = Math.abs(value - t);
        if (diff <= threshold && diff < bestDiff) {
            bestDiff = diff;
            bestTarget = t;
        }
    }
    return bestTarget !== null ? Math.round(bestTarget) : Math.round(value);
}

/**
 * Finds the closest non-overlapping edge-adjacent placement for `dragIndex`
 * near `(rawX, rawY)`. Aligns magnetically to stationary edges and centers.
 */
function snapForDrag(monitors, dragIndex, rawX, rawY, scaleFactor) {
    const list = monitors || [];
    const dragged = (dragIndex >= 0 && dragIndex < list.length) ? list[dragIndex] : null;
    if (!dragged)
        return { x: Math.round(rawX), y: Math.round(rawY), valid: false };

    const dw = logicalWidth(dragged);
    const dh = logicalHeight(dragged);

    const others = [];
    for (let i = 0; i < list.length; ++i) {
        if (i === dragIndex)
            continue;
        const m = list[i];
        if (!m || m.disabled)
            continue;
        others.push({
            x: m.x || 0,
            y: m.y || 0,
            w: logicalWidth(m),
            h: logicalHeight(m)
        });
    }

    if (others.length === 0)
        return { x: Math.round(rawX), y: Math.round(rawY), valid: true };

    const xTargets = [];
    const yTargets = [];
    for (let i = 0; i < others.length; ++i) {
        const o = others[i];
        xTargets.push(o.x);
        xTargets.push(o.x + (o.w - dw) / 2);
        xTargets.push(o.x + o.w - dw);
        yTargets.push(o.y);
        yTargets.push(o.y + (o.h - dh) / 2);
        yTargets.push(o.y + o.h - dh);
    }

    const effectiveScale = (typeof scaleFactor === "number" && scaleFactor > 0.005) ? scaleFactor : 0.08;
    const threshold = clamp(14 / effectiveScale, 24, 220);

    let best = null;
    let bestDist = Infinity;

    for (let i = 0; i < others.length; ++i) {
        const o = others[i];
        const xMin = o.x - dw + 1;
        const xMax = o.x + o.w - 1;
        const yMin = o.y - dh + 1;
        const yMax = o.y + o.h - 1;

        const clampedX = Math.round(clamp(rawX, xMin, xMax));
        const clampedY = Math.round(clamp(rawY, yMin, yMax));
        const alignedX = Math.round(clamp(alignToTargets(clampedX, xTargets, threshold), xMin, xMax));
        const alignedY = Math.round(clamp(alignToTargets(clampedY, yTargets, threshold), yMin, yMax));

        const edgeGroups = [
            [{ x: o.x + o.w, y: alignedY }, { x: o.x + o.w, y: clampedY }],
            [{ x: o.x - dw, y: alignedY }, { x: o.x - dw, y: clampedY }],
            [{ x: alignedX, y: o.y + o.h }, { x: clampedX, y: o.y + o.h }],
            [{ x: alignedX, y: o.y - dh }, { x: clampedX, y: o.y - dh }]
        ];

        for (let g = 0; g < edgeGroups.length; ++g) {
            const pair = edgeGroups[g];
            for (let k = 0; k < pair.length; ++k) {
                const candidate = {
                    x: Math.round(pair[k].x),
                    y: Math.round(pair[k].y),
                    w: dw,
                    h: dh
                };
                let blocked = false;
                for (let j = 0; j < others.length; ++j) {
                    if (overlapsRect(candidate, others[j])) {
                        blocked = true;
                        break;
                    }
                }
                if (blocked)
                    continue;
                const dist = Math.hypot(candidate.x - rawX, candidate.y - rawY);
                if (dist < bestDist) {
                    bestDist = dist;
                    best = candidate;
                }
                // Prefer aligned candidate on this edge if it didn't overlap
                break;
            }
        }
    }

    if (!best)
        return { x: Math.round(rawX), y: Math.round(rawY), valid: false };

    return { x: best.x, y: best.y, valid: true };
}

function computeSnapPoints(monitors, positionsOverride) {
    const list = monitors || [];
    const points = [];
    const thresh = 6;

    for (let i = 0; i < list.length; ++i) {
        const a = list[i];
        if (!a || a.disabled)
            continue;
        const aw = logicalWidth(a);
        const ah = logicalHeight(a);
        const aPos = monitorPosition(a, positionsOverride);
        const aR = aPos.x + aw;
        const aB = aPos.y + ah;

        for (let j = i + 1; j < list.length; ++j) {
            const b = list[j];
            if (!b || b.disabled)
                continue;
            const bw = logicalWidth(b);
            const bh = logicalHeight(b);
            const bPos = monitorPosition(b, positionsOverride);
            const bR = bPos.x + bw;
            const bB = bPos.y + bh;

            const hOverlap = Math.min(aR, bR) > Math.max(aPos.x, bPos.x);
            const vOverlap = Math.min(aB, bB) > Math.max(aPos.y, bPos.y);

            if (Math.abs(aR - bPos.x) < thresh && vOverlap) {
                points.push({ x: aR, y: (Math.max(aPos.y, bPos.y) + Math.min(aB, bB)) / 2 });
            } else if (Math.abs(bR - aPos.x) < thresh && vOverlap) {
                points.push({ x: bR, y: (Math.max(aPos.y, bPos.y) + Math.min(aB, bB)) / 2 });
            } else if (Math.abs(aB - bPos.y) < thresh && hOverlap) {
                points.push({ x: (Math.max(aPos.x, bPos.x) + Math.min(aR, bR)) / 2, y: aB });
            } else if (Math.abs(bB - aPos.y) < thresh && hOverlap) {
                points.push({ x: (Math.max(aPos.x, bPos.x) + Math.min(aR, bR)) / 2, y: bB });
            }
        }
    }

    return points;
}
