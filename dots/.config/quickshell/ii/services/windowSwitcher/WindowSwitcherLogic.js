.pragma library

/*
 * Alt+Tab's pure logic: which windows, in what order, what a query matches, where a key moves
 * the selection, how a peeked window is drawn. No QML, no compositor - WindowSwitcher.qml and
 * the views call these, and scripts/tests/test_window_switcher_logic.cjs checks them directly.
 */

function normalisedAddress(raw) {
    const text = String(raw ?? "").trim();
    if (text.length === 0)
        return "";
    return text.startsWith("0x") ? text : `0x${text}`;
}

/// A `hyprctl clients` object as the switcher keeps it. `appName` turns a class into a name.
function entryFor(client, toplevels, appName) {
    const address = normalisedAddress(client.address);
    const workspace = client.workspace ?? {};
    const appClass = String(client.class || client.initialClass || "");
    return {
        "address": address,
        "toplevel": toplevels?.[address] ?? null,
        "appClass": appClass,
        "appName": String((appName ? appName(appClass) : "") || appClass),
        "title": String(client.title || client.initialTitle || ""),
        "workspaceId": Number(workspace.id ?? 0),
        "workspaceName": String(workspace.name ?? ""),
        "special": Number(workspace.id ?? 0) < 0,
        "monitor": Number(client.monitor ?? -1),
        "x": Number(client.at?.[0] ?? 0),
        "y": Number(client.at?.[1] ?? 0),
        "width": Math.max(1, Number(client.size?.[0] ?? 16)),
        "height": Math.max(1, Number(client.size?.[1] ?? 9)),
        "floating": client.floating === true,
        "fullscreen": Number(client.fullscreen ?? 0) > 0,
        "focusOrder": Number(client.focusHistoryID ?? 9999)
    };
}

/**
 * Whether a window belongs in the switcher.
 * `filter`: { includeOtherWorkspaces, visibleWorkspaceIds, monitor (-1: every monitor),
 * appClass ("" : every app) }.
 */
function wanted(client, filter) {
    if (!client || client.mapped === false || client.hidden === true)
        return false;
    const workspaceId = Number(client.workspace?.id ?? NaN);
    // -1 is "no workspace": a window being torn down, or not placed yet.
    if (!isFinite(workspaceId) || workspaceId === -1)
        return false;
    if (filter.monitor !== undefined && filter.monitor >= 0 && Number(client.monitor ?? -1) !== filter.monitor)
        return false;
    if (filter.appClass && String(client.class || client.initialClass || "").toLowerCase() !== filter.appClass.toLowerCase())
        return false;
    if (filter.includeOtherWorkspaces)
        return true;
    return (filter.visibleWorkspaceIds ?? []).some(id => id === workspaceId);
}

/**
 * The order, most recently used first: Hyprland's focus stack, with the focused window
 * (off the event socket, fresher than the stack) moved to the front.
 */
function snapshot(clients, toplevels, filter, currentAddress, appName) {
    const list = (clients ?? []).filter(client => wanted(client, filter))
        .map(client => entryFor(client, toplevels, appName));
    list.sort((a, b) => a.focusOrder - b.focusOrder);
    const at = list.findIndex(entry => entry.address === currentAddress);
    if (at > 0)
        list.unshift(list.splice(at, 1)[0]);
    return list;
}

/// A changed window list under an open switcher: order kept, the gone leave, the new join last.
function reconcile(previous, clients, toplevels, filter, appName) {
    const byAddress = {};
    for (const client of (clients ?? [])) {
        if (wanted(client, filter))
            byAddress[normalisedAddress(client.address)] = client;
    }
    const kept = [];
    for (const entry of previous) {
        const client = byAddress[entry.address];
        if (!client)
            continue;
        kept.push(entryFor(client, toplevels, appName));
        delete byAddress[entry.address];
    }
    for (const address in byAddress)
        kept.push(entryFor(byAddress[address], toplevels, appName));
    return kept;
}

// ------------------------------------------------------------------ search

const wordBreak = /[\s\-_.:/|·—]+/;

function searchText(entry) {
    const title = entry.toplevel?.title || entry.title;
    return `${entry.appName || ""} ${entry.appClass} ${title}`.toLowerCase();
}

function inOrder(needle, haystack) {
    let at = 0;
    for (const ch of needle) {
        at = haystack.indexOf(ch, at);
        if (at < 0)
            return false;
        at++;
    }
    return needle.length > 0;
}

/// 0: a word starts with the query; 1: the query appears; 2: its letters appear in order; -1: no match.
function matchTier(entry, query) {
    const q = String(query ?? "").trim().toLowerCase();
    if (q.length === 0)
        return 0;
    const text = searchText(entry);
    if (text.split(wordBreak).some(word => word.startsWith(q)))
        return 0;
    if (text.includes(q))
        return 1;
    if (inOrder(q.replace(/\s+/g, ""), text))
        return 2;
    return -1;
}

/// The windows matching the query, best tier first; inside a tier the most recently used first.
function filtered(list, query) {
    if (String(query ?? "").trim().length === 0)
        return list.slice();
    const tiers = [[], [], []];
    for (const entry of list) {
        const tier = matchTier(entry, query);
        if (tier >= 0)
            tiers[tier].push(entry);
    }
    return tiers[0].concat(tiers[1], tiers[2]);
}

/**
 * Which characters of `text` the query matched, for highlighting: one run where the query
 * appears whole (a word start preferred), else each letter in order. [] when it does not match.
 */
function matchedIndices(text, query) {
    const t = String(text ?? "").toLowerCase();
    const q = String(query ?? "").trim().toLowerCase();
    if (q.length === 0 || t.length === 0)
        return [];
    let at = -1;
    const re = new RegExp(`(^|${wordBreak.source})`, "g");
    let m;
    while ((m = re.exec(t)) !== null) {
        const start = m.index + m[0].length;
        if (t.startsWith(q, start)) {
            at = start;
            break;
        }
        if (re.lastIndex === m.index)
            re.lastIndex++;
    }
    if (at < 0)
        at = t.indexOf(q);
    if (at >= 0)
        return Array.from({ length: q.length }, (_, i) => at + i);
    const needle = q.replace(/\s+/g, "");
    const out = [];
    let from = 0;
    for (const ch of needle) {
        const found = t.indexOf(ch, from);
        if (found < 0)
            return [];
        out.push(found);
        from = found + 1;
    }
    return out;
}

function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/// `text` as rich text with the matched characters in `color`, bold. Plain-escaped with no match.
function highlighted(text, query, color) {
    const s = String(text ?? "");
    const hits = new Set(matchedIndices(s, query));
    if (hits.size === 0)
        return escapeHtml(s);
    let out = "";
    let open = false;
    for (let i = 0; i < s.length; i++) {
        const hit = hits.has(i);
        if (hit && !open) {
            out += `<b><font color="${color}">`;
            open = true;
        } else if (!hit && open) {
            out += "</font></b>";
            open = false;
        }
        out += escapeHtml(s[i]);
    }
    if (open)
        out += "</font></b>";
    return out;
}

// ------------------------------------------------------------------ moving the selection

function stepIndex(index, delta, n) {
    if (n <= 0)
        return 0;
    return ((index + delta) % n + n) % n;
}

/// Up/Down on a grid of `columns`; off an edge wraps to the same column on the other one.
function stepRow(index, delta, n, columns) {
    if (columns <= 0 || n <= columns)
        return stepIndex(index, delta, n);
    const next = index + delta * columns;
    if (next >= n)
        return index % columns;
    if (next < 0) {
        const column = index % columns;
        const lastRowStart = Math.floor((n - 1) / columns) * columns;
        return Math.min(n - 1, lastRowStart + column);
    }
    return next;
}

/// Alt+1…9: window N, counted from the first; -1 when there are fewer.
function jumpIndex(digit, n) {
    const i = Number(digit) - 1;
    return i >= 0 && i < 9 && i < n ? i : -1;
}

/// The windows' position for the counter: "4 / 17", 1-based. "" with nothing to count.
function positionText(index, n) {
    return n > 0 ? `${index + 1} / ${n}` : "";
}

/**
 * The workspace label a cover or card carries: nothing for the workspace you are on, its
 * name for a special one (marked), its name or number for any other.
 */
function workspaceLabel(entry, currentWorkspaceId) {
    if (!entry || entry.workspaceId === currentWorkspaceId)
        return { "text": "", "special": false };
    if (entry.special) {
        const name = String(entry.workspaceName ?? "").replace(/^special:?/, "");
        return { "text": name.length > 0 ? name : "special", "special": true };
    }
    const name = String(entry.workspaceName ?? "");
    return { "text": name.length > 0 ? name : String(entry.workspaceId), "special": false };
}

// ------------------------------------------------------------------ the peek

/**
 * One `hyprctl --batch` asking how Hyprland draws a window: its opacities (focused,
 * fullscreen, unfocused), border, corners and dim. Read back by `parseWindowLook`, in order.
 */
function windowLookBatch(address) {
    const w = `address:${address}`;
    return [
        `getprop ${w} opacity`, `getprop ${w} opacity_override`,
        `getprop ${w} opacity_fullscreen`, `getprop ${w} opacity_fullscreen_override`,
        `getprop ${w} opacity_inactive`, `getprop ${w} opacity_inactive_override`,
        "j/getoption decoration:active_opacity", "j/getoption decoration:fullscreen_opacity",
        "j/getoption decoration:inactive_opacity",
        `getprop ${w} border_size`, `getprop ${w} active_border_color`, `getprop ${w} inactive_border_color`,
        `getprop ${w} rounding`, `getprop ${w} rounding_power`,
        `getprop ${w} no_dim`, "j/getoption decoration:dim_inactive", "j/getoption decoration:dim_special"
    ].join("; ");
}

/**
 * `hyprctl --batch` output (answers split by blank lines) -> { active, fullscreen, inactive,
 * border, borderColor, inactiveBorderColor, rounding, roundingPower, dimmed, dimSpecial }.
 * `dimmed`: dim_inactive is on and nothing exempts the window, so its capture is darkened.
 */
function parseWindowLook(text) {
    const parts = String(text ?? "").split(/\n\s*\n\s*\n/).map(part => part.trim());
    const option = part => {
        const m = /"(?:float|int)":\s*(-?[0-9.]+)/.exec(part ?? "");
        return m ? Number(m[1]) : 1;
    };
    const flag = part => /"bool":\s*true/.test(part ?? "") || /"int":\s*1\b/.test(part ?? "");
    const rule = value => {
        const n = Number(value);
        return isFinite(n) && n > 0 ? n : 1;
    };
    const clamp = v => Math.max(0, Math.min(1, v));
    // A gradient prints as AARRGGBB stops and an angle; the first stop stands for it.
    const colour = part => {
        const stop = (/^([0-9a-fA-F]{8})\b/.exec(part ?? "") ?? [])[1];
        return stop ? `#${stop}` : "transparent";
    };
    const power = Number(parts[13]);
    const dimSpecial = /"float":\s*([0-9.]+)/.exec(parts[16] ?? "");
    return {
        "active": clamp(rule(parts[0]) * (parts[1] === "true" ? 1 : option(parts[6]))),
        "fullscreen": clamp(rule(parts[2]) * (parts[3] === "true" ? 1 : option(parts[7]))),
        "inactive": clamp(rule(parts[4]) * (parts[5] === "true" ? 1 : option(parts[8]))),
        "border": Math.max(0, Number(parts[9]) || 0),
        "borderColor": colour(parts[10]),
        "inactiveBorderColor": colour(parts[11]),
        "rounding": Math.max(0, Number(parts[12]) || 0),
        "roundingPower": isFinite(power) && power > 0 ? power : 2,
        "dimmed": parts[14] === "false" && flag(parts[15]),
        "dimSpecial": dimSpecial ? clamp(Number(dimSpecial[1])) : 0.2
    };
}

/**
 * The outline of a w×h box whose corners are Hyprland's: radius r, rounding_power p (2 is a
 * circle, more is squarer - a superellipse |x|^p + |y|^p = 1 in each corner). An SVG path.
 */
function roundedPath(w, h, r, p, segments) {
    const radius = Math.max(0, Math.min(r, w / 2, h / 2));
    if (radius <= 0)
        return `M 0 0 L ${w} 0 L ${w} ${h} L 0 ${h} Z`;
    const n = Math.max(2, segments ?? 12);
    const e = 2 / Math.max(0.5, p);
    const pt = (cx, cy, angle) => {
        const c = Math.cos(angle), s = Math.sin(angle);
        const x = cx + radius * Math.sign(c) * Math.pow(Math.abs(c), e);
        const y = cy + radius * Math.sign(s) * Math.pow(Math.abs(s), e);
        return `${+x.toFixed(2)} ${+y.toFixed(2)}`;
    };
    // Corners clockwise from the top right, each a quarter turn of the superellipse.
    const corners = [
        [w - radius, radius, -Math.PI / 2],
        [w - radius, h - radius, 0],
        [radius, h - radius, Math.PI / 2],
        [radius, radius, Math.PI]
    ];
    let d = `M ${radius} 0`;
    for (const [cx, cy, start] of corners) {
        for (let i = 0; i <= n; i++)
            d += ` L ${pt(cx, cy, start + (Math.PI / 2) * i / n)}`;
    }
    return d + " Z";
}

/**
 * One step of a damped spring pulling `offset` to zero over `dt` seconds; returns [offset,
 * velocity], both 0 once inside `epsilon`. Small sub-steps keep it stable on a long frame.
 */
function springStep(offset, velocity, dt, stiffness, damping, epsilon) {
    let left = Math.min(dt, 0.05);
    while (left > 0) {
        const h = Math.min(left, 0.004);
        velocity += (-stiffness * offset - damping * velocity) * h;
        offset += velocity * h;
        left -= h;
    }
    if (Math.abs(offset) < epsilon && Math.abs(velocity) < epsilon * 10)
        return [0, 0];
    return [offset, velocity];
}

/**
 * The windows of a workspace bottom to top, for peeking at the whole workspace: tiled under
 * floating, each layer by focus (least recent lowest), the peeked window raised to the top of
 * its layer - and a fullscreen one over everything.
 */
function stacking(entries, peekedAddress) {
    const rank = e => (e.fullscreen && e.address === peekedAddress) ? 3 : e.floating ? 1 : 0;
    return entries.slice().sort((a, b) => {
        const layer = rank(a) - rank(b);
        if (layer !== 0)
            return layer;
        if (a.address === peekedAddress)
            return 1;
        if (b.address === peekedAddress)
            return -1;
        return b.focusOrder - a.focusOrder;
    });
}
