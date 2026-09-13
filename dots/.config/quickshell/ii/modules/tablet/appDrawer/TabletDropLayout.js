.pragma library

/**
 * Where an app dragged out of the drawer will land, and what it pushes aside.
 *
 * Pure: no Hyprland, no QML. The drop overlay feeds it the workspace as the compositor
 * reports it and draws what comes back, and the tests feed it numbers. Every rect is in
 * layout coordinates, `{ x, y, width, height }`.
 *
 * It predicts, it does not decide. The overlay makes the compositor agree on drop by
 * focusing the window this names and preselecting the side — without that, dwindle would
 * split whatever was focused, in whatever direction the cursor happened to suggest, and the
 * preview would be a guess.
 */

function rect(x, y, width, height) {
    return { x: x, y: y, width: Math.max(0, width), height: Math.max(0, height) };
}

function inset(r, amount) {
    return rect(r.x + amount, r.y + amount, r.width - 2 * amount, r.height - 2 * amount);
}

function contains(r, p) {
    return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height;
}

function distanceTo(r, p) {
    const dx = Math.max(r.x - p.x, 0, p.x - (r.x + r.width));
    const dy = Math.max(r.y - p.y, 0, p.y - (r.y + r.height));
    return Math.hypot(dx, dy);
}

/// The side of a window a point is nearest, by its diagonals: the window is cut into four
/// triangles, the way docking targets work, so the middle of the left edge means "left"
/// whatever the window's shape.
function sideOf(r, p) {
    const nx = (p.x - (r.x + r.width / 2)) / Math.max(1, r.width / 2);
    const ny = (p.y - (r.y + r.height / 2)) / Math.max(1, r.height / 2);
    if (Math.abs(nx) >= Math.abs(ny))
        return nx < 0 ? "l" : "r";
    return ny < 0 ? "u" : "d";
}

/// Splits a window's rect in two along `side`. The gap between the halves is what
/// Hyprland leaves between two tiled windows: gaps_in on each.
function splitRect(r, side, gap, ratio) {
    const horizontal = side === "l" || side === "r";
    const span = (horizontal ? r.width : r.height) - gap;
    const share = Math.max(0.1, Math.min(1.9, ratio || 1)) / 2;
    const first = Math.round(span * share);
    const second = span - first;
    let before;
    let after;
    if (horizontal) {
        before = rect(r.x, r.y, first, r.height);
        after = rect(r.x + first + gap, r.y, second, r.height);
    } else {
        before = rect(r.x, r.y, r.width, first);
        after = rect(r.x, r.y + first + gap, r.width, second);
    }
    return (side === "l" || side === "u")
        ? { incoming: before, existing: after }
        : { incoming: after, existing: before };
}

function centered(area, widthShare, heightShare) {
    const width = Math.round(area.width * widthShare);
    const height = Math.round(area.height * heightShare);
    return rect(Math.round(area.x + (area.width - width) / 2), Math.round(area.y + (area.height - height) / 2), width, height);
}

function stackColumn(column, count, gap) {
    const rects = [];
    const each = (column.height - gap * (count - 1)) / Math.max(1, count);
    for (let i = 0; i < count; i++)
        rects.push(rect(column.x, Math.round(column.y + i * (each + gap)), column.width, Math.round(each)));
    return rects;
}

/**
 * input:
 *   point       { x, y }                       where the finger is
 *   area        rect                            the monitor's usable area (bar and dock out)
 *   gapsIn, gapsOut                             Hyprland's gaps
 *   layout      "dwindle" | "master" | "monocle" | anything else (planned as dwindle)
 *   windows     [{ address, cls, x, y, width, height }]   tiled windows on the workspace
 *   splitRatio  dwindle:default_split_ratio
 *   mfact, newStatus                            master layout options
 *   floating    true when the family floats new windows; floatRect is where
 *
 * returns { mode, direction, targetAddress, incoming, windows: [{ address, cls, from, to }] }
 */
function planDrop(input) {
    const area = input.area;
    const gap = 2 * Math.max(0, input.gapsIn || 0);
    const inner = inset(area, Math.max(0, input.gapsOut || 0));
    const source = input.windows || [];
    const plan = {
        mode: "",
        direction: "",
        targetAddress: "",
        incoming: inner,
        windows: source.map(w => ({
            address: w.address,
            cls: w.cls,
            from: rect(w.x, w.y, w.width, w.height),
            to: rect(w.x, w.y, w.width, w.height)
        }))
    };

    if (input.floating) {
        plan.mode = "floating";
        plan.incoming = input.floatRect || centered(inner, 0.62, 0.68);
        return plan;
    }
    if (plan.windows.length === 0) {
        plan.mode = "empty";
        return plan;
    }
    if (input.layout === "monocle") {
        plan.mode = "monocle";
        return plan;
    }
    if (input.layout === "master")
        return planMaster(plan, input, inner, gap);

    // dwindle, and the fallback for layouts this does not model.
    const p = input.point;
    let target = plan.windows.find(w => contains(w.from, p));
    if (!target) {
        target = plan.windows.reduce((best, w) =>
            (!best || distanceTo(w.from, p) < distanceTo(best.from, p)) ? w : best, null);
    }
    const side = sideOf(target.from, p);
    const split = splitRect(target.from, side, gap, input.splitRatio);
    target.to = split.existing;
    plan.mode = "dwindle";
    plan.direction = side;
    plan.targetAddress = target.address;
    plan.incoming = split.incoming;
    return plan;
}

/// Master on the left, the rest stacked on the right in reading order.
function planMaster(plan, input, inner, gap) {
    const mfact = Math.max(0.05, Math.min(0.95, input.mfact || 0.55));
    const byColumn = plan.windows.slice().sort((a, b) => (a.from.x - b.from.x) || (b.from.height - a.from.height));
    const incomingIsMaster = input.newStatus === "master";

    const masterWidth = Math.round((inner.width - gap) * mfact);
    const masterRect = rect(inner.x, inner.y, masterWidth, inner.height);
    const column = rect(inner.x + masterWidth + gap, inner.y, inner.width - masterWidth - gap, inner.height);

    let stack;
    if (incomingIsMaster) {
        plan.incoming = masterRect;
        stack = plan.windows.slice().sort((a, b) => (a.from.y - b.from.y) || (a.from.x - b.from.x));
    } else {
        const master = byColumn[0];
        master.to = masterRect;
        stack = plan.windows.filter(w => w !== master).sort((a, b) => (a.from.y - b.from.y) || (a.from.x - b.from.x));
        stack.push(null); // the incoming window joins the bottom of the stack
    }

    const rects = stackColumn(column, stack.length, gap);
    stack.forEach((w, i) => {
        if (w === null)
            plan.incoming = rects[i];
        else
            w.to = rects[i];
    });
    plan.mode = "master";
    return plan;
}
