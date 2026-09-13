// Portable visual keyboard maps. This module never writes to a keyboard.
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function clean(value, limit) { return String(value ?? "").slice(0, limit); }

function problem(board) {
    if (!board || !Array.isArray(board.keys) || !Array.isArray(board.layers)) return "Missing keyboard geometry or layers";
    if (!board.keys.length || board.keys.length > 256 || !board.layers.length || board.layers.length > 32) return "Invalid keyboard size";
    if (!Number.isFinite(board.width) || !Number.isFinite(board.height) || board.width <= 0 || board.height <= 0 || board.width > 100 || board.height > 100) return "Invalid keyboard bounds";
    const ids = new Set();
    for (const key of board.keys) {
        if (!key || typeof key !== "object") return "Invalid key geometry";
        if (!Number.isInteger(key.row) || !Number.isInteger(key.col) || key.row < 0 || key.col < 0) return "Invalid key position";
        const id = key.row + ":" + key.col;
        if (ids.has(id)) return "Duplicate key position";
        ids.add(id);
        for (const field of ["x", "y", "w", "h", "r", "rx", "ry"])
            if (!Number.isFinite(key[field]) || Math.abs(key[field]) > 360) return "Invalid key geometry";
        if (key.w <= 0 || key.h <= 0 || key.w > 16 || key.h > 16) return "Invalid key dimensions";
    }
    for (const layer of board.layers) {
        if (!Array.isArray(layer) || layer.length !== board.keys.length) return "Layer does not match the keyboard";
        for (const key of layer) if (!key || typeof key !== "object" || typeof key.label !== "string") return "Invalid key label";
    }
    return "";
}

function normalized(board) {
    if (problem(board)) return null;
    return {
        source: ["vial", "system"].includes(board.source) ? board.source : "manual",
        deviceUid: clean(board.deviceUid, 80),
        deviceName: clean(board.deviceName, 120),
        layout: clean(board.layout, 80), variant: clean(board.variant, 80),
        model: clean(board.model, 80), options: clean(board.options, 200),
        name: clean(board.name, 100),
        preset: clean(board.preset, 40),
        width: board.width, height: board.height,
        keys: board.keys.map(k => ({ row: k.row, col: k.col, x: k.x, y: k.y, w: k.w, h: k.h, r: k.r, rx: k.rx, ry: k.ry })),
        layers: board.layers.map(layer => layer.map(k => ({
            label: clean(k.label, 120), char: clean(k.char, 32),
            code: Number.isInteger(k.code) ? k.code : -1,
            resolvedCode: Number.isInteger(k.resolvedCode) ? k.resolvedCode : -1,
            inherited: Boolean(k.inherited),
            custom: Boolean(k.custom),
            icon: clean(k.icon, 80), description: clean(k.description, 500)
        }))),
        layerNames: board.layers.map((_, i) => clean(board.layerNames?.[i], 60)),
        readAt: clean(board.readAt, 80)
    };
}

function fromVial(data) {
    if (!data?.available) return null;
    return normalized(Object.assign({}, data, { source: "vial", readAt: new Date().toISOString() }));
}

function refreshed(previous, data) {
    const next = data?.source === "system" ? normalized(data) : fromVial(data);
    if (!next) return null;
    if (!previous || previous.source !== next.source || !next.deviceUid || previous.deviceUid !== next.deviceUid) return next;
    const positions = new Map(previous.keys.map((k, i) => [k.row + ":" + k.col, i]));
    next.layers.forEach((layer, l) => layer.forEach((entry, i) => {
        const key = next.keys[i];
        const old = previous.layers[l]?.[positions.get(key.row + ":" + key.col)];
        // A changed firmware assignment must not keep an obsolete visual label.
        if (old?.custom && old.code === entry.code && old.resolvedCode === entry.resolvedCode)
            layer[i] = Object.assign({}, entry, { label: old.label, icon: old.icon, description: old.description, custom: true });
    }));
    next.layerNames = next.layers.map((_, i) => previous.layerNames?.[i] || next.layerNames[i] || "");
    return next;
}

function editKey(board, layer, index, label, icon, description) {
    if (!board?.layers?.[layer]?.[index]) return null;
    const next = copy(board);
    Object.assign(next.layers[layer][index], { label: clean(label, 120), icon: clean(icon, 80), description: clean(description, 500), custom: true, inherited: false });
    return normalized(next);
}

function manual(rows, preset) {
    const keys = [], entries = [];
    function row(labels, widths, y) {
        let x = 0;
        labels.forEach((label, col) => {
            const w = widths[col] || 1;
            keys.push({ row: y, col: col, x: x, y: y, w: w, h: 1, r: 0, rx: 0, ry: 0 });
            entries.push({ label: label, char: label.length === 1 ? label : "" });
            x += w;
        });
    }
    row(["Esc", ...Array.from({length: 12}, (_, i) => "F" + (i + 1)), "Del"], [], 0);
    row(["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "Bksp"], [], 1);
    row(["Tab", ...rows[0], "\\"], [], 2);
    const home = ["Ctrl", ...rows[1], "Enter"];
    row(home, home.map((_, i) => i === home.length - 1 ? 14 - home.length + 1 : 1), 3);
    const bottom = ["Shift", ...rows[2], "↑", "Shift"];
    row(bottom, bottom.map((_, i) => i === 0 ? 14 - bottom.length + 1 : 1), 4);
    row(["Ctrl", "Super", "Alt", "Space", "Alt", "←", "↓", "→"], [1,1,1,7,1,1,1,1], 5);
    return normalized({ name: preset.toUpperCase(), preset: preset, source: "manual", keys: keys, layers: [entries], width: 14, height: 6 });
}

function automaticIcon(label) {
    return ({ "Super": "keyboard_command_key", "Space": "space_bar", "Enter": "keyboard_return", "Bksp": "backspace", "Shift": "shift", "R\nShift": "shift", "←": "arrow_back", "→": "arrow_forward", "↑": "arrow_upward", "↓": "arrow_downward", "Vol+": "volume_up", "Vol-": "volume_down", "Mute": "volume_off", "Play": "play_pause", "Prev": "skip_previous", "Next": "skip_next", "Bri+": "brightness_high", "Bri-": "brightness_low" })[label] || "";
}
