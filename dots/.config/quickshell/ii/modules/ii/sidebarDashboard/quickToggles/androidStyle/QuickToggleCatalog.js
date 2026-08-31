.pragma library

// The catalog is deliberately independent from QML, Config, and services. It
// is the only place where quick-toggle kinds, defaults, and size constraints
// are defined. The UI may add presentation metadata, but it must not invent a
// second size policy.
var TOGGLE_TYPES = {
    network: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    bluetooth: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    vpn: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    tailscale: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    dnsOverTls: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    idleInhibitor: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    easyEffects: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    nightLight: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    darkMode: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    cloudflareWarp: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    gameMode: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    screenSnip: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    screenRecord: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    colorPicker: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    videoEditor: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    onScreenKeyboard: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    keypressDisplay: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    mic: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    audio: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    notifications: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    autoDnd: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    powerProfile: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    musicRecognition: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    antiFlashbang: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    screenShader: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    soundcoreAnc: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    systemSounds: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    localSend: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    keyboardBacklight: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    modes: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },

    volumeSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    micSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    brightnessSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    gammaSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },

    mediaWidget: {
        kind: "media",
        defaultSize: [2, 2],
        allowedSizes: [[2, 1], [2, 2], [4, 2]]
    }
};

function allTypes() {
    return Object.keys(TOGGLE_TYPES);
}
function hasType(type) {
    return typeof type === "string" && TOGGLE_TYPES[type] !== undefined;
}

function kind(type) {
    var metadata = TOGGLE_TYPES[type];
    return metadata ? metadata.kind : "unknown";
}

function defaultSize(type) {
    var metadata = TOGGLE_TYPES[type];
    if (!metadata)
        return [1, 1];
    return [metadata.defaultSize[0], metadata.defaultSize[1]];
}

function finiteInteger(value, fallback) {
    var number = Number(value);
    if (!isFinite(number))
        return fallback;
    return Math.floor(number);
}

function positiveColumns(columns) {
    return Math.max(1, finiteInteger(columns, 1));
}

function distance(width, height, candidate) {
    return Math.abs(width - candidate[0]) + Math.abs(height - candidate[1]);
}

function normalizeSize(type, width, height, columns) {
    var metadata = TOGGLE_TYPES[type];
    var cols = positiveColumns(columns);
    var fallback = defaultSize(type);
    var normalizedWidth = Math.max(1, finiteInteger(width, fallback[0]));
    var normalizedHeight = Math.max(1, finiteInteger(height, fallback[1]));

    if (!metadata) {
        return [Math.min(normalizedWidth, cols), normalizedHeight];
    }

    if (metadata.fixedHeight !== undefined)
        normalizedHeight = metadata.fixedHeight;

    if (metadata.allowedSizes) {
        var fittingSizes = [];
        for (var i = 0; i < metadata.allowedSizes.length; i++) {
            var candidate = metadata.allowedSizes[i];
            if (candidate[0] <= cols)
                fittingSizes.push(candidate);
        }

        // A one-column grid cannot render the media widget's normal minimum
        // width. It still must remain packable and never escape the grid.
        if (fittingSizes.length === 0)
            return [cols, 1];

        var best = fittingSizes[0];
        var bestDistance = distance(normalizedWidth, normalizedHeight, best);
        for (var j = 1; j < fittingSizes.length; j++) {
            var candidateDistance = distance(normalizedWidth, normalizedHeight, fittingSizes[j]);
            if (candidateDistance < bestDistance) {
                best = fittingSizes[j];
                bestDistance = candidateDistance;
            }
        }
        return [best[0], best[1]];
    }

    return [Math.min(normalizedWidth, cols), normalizedHeight];
}

function isSizeAllowed(type, width, height, columns) {
    var normalized = normalizeSize(type, width, height, columns);
    var requestedWidth = finiteInteger(width, -1);
    var requestedHeight = finiteInteger(height, -1);
    if (requestedWidth !== normalized[0] || requestedHeight !== normalized[1])
        return false;

    var metadata = TOGGLE_TYPES[type];
    if (!metadata)
        return requestedWidth >= 1 && requestedWidth <= positiveColumns(columns) && requestedHeight >= 1;
    if (metadata.allowedSizes) {
        for (var i = 0; i < metadata.allowedSizes.length; i++) {
            if (metadata.allowedSizes[i][0] === requestedWidth && metadata.allowedSizes[i][1] === requestedHeight)
                return requestedWidth <= positiveColumns(columns);
        }
        return false;
    }
    if (metadata.fixedHeight !== undefined && requestedHeight !== metadata.fixedHeight)
        return false;
    return requestedWidth >= 1 && requestedWidth <= positiveColumns(columns) && requestedHeight >= 1 && requestedHeight <= (metadata.maxHeight || 8);
}

function item(type, id, width, height, columns) {
    var normalized = normalizeSize(type, width, height, columns);
    var stableId = typeof id === "string" && id.length > 0 ? id : type;
    return {
        id: stableId,
        type: type,
        sizeW: normalized[0],
        sizeH: normalized[1]
    };
}

function asArray(value) {
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

function warn(options, message) {
    if (options && typeof options.warn === "function") {
        options.warn(message);
        return;
    }
    if (!options || options.logWarnings !== false)
        console.warn(message);
}

function normalizePages(rawPages, columns, options) {
    var raw = asArray(rawPages);
    if (raw.length === 0)
        return [[]];

    // Config v2 stored one flat toggle list in `pages` before pages existed.
    if (raw[0] && typeof raw[0] === "object" && !Array.isArray(raw[0]) && raw[0].type !== undefined)
        raw = [raw];

    var result = [];
    var seen = Object.create(null);
    for (var pageIndex = 0; pageIndex < raw.length; pageIndex++) {
        var sourcePage = asArray(raw[pageIndex]);
        var page = [];
        for (var itemIndex = 0; itemIndex < sourcePage.length; itemIndex++) {
            var source = sourcePage[itemIndex];
            if (!source || typeof source !== "object")
                continue;
            var type = typeof source.type === "string" ? source.type : "";
            if (type.length === 0)
                continue;

            var id = typeof source.id === "string" && source.id.length > 0 ? source.id : type;
            if (seen[id]) {
                warn(options, "[QuickToggleConfig] duplicate id detected: " + id + " (keeping page=" + seen[id].page + ",index=" + seen[id].index + ")");
                continue;
            }
            seen[id] = { page: pageIndex, index: itemIndex };
            if (!hasType(type))
                warn(options, "[QuickToggleConfig] unknown toggle type preserved: " + type);

            var sourceWidth = source.sizeW !== undefined ? source.sizeW : source.size;
            var sourceSize = item(type, id, sourceWidth, source.sizeH, columns);
            page.push(sourceSize);
        }
        result.push(page);
    }

    return result.length > 0 ? result : [[]];
}
