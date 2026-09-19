.pragma library

// The catalog is deliberately independent from QML, Config, and services. It
// is the only place where quick-toggle kinds, defaults, and size constraints
// are defined. The UI may add presentation metadata, but it must not invent a
// second size policy.
/**
 * Media footprints. Two designs, split by column count:
 *
 * - Two columns are the vertical family: compact at one row, square at two, and
 *   the portrait transport from four rows up (2x3 belongs to no design and is
 *   left out).
 * - Three columns and wider are the cover-backed face the 4x2 uses, which takes
 *   any extra width and any height from two rows on. A wide one-row tile is left
 *   out: the audio chip and the transport would both sit on the right with no
 *   room between them.
 *
 * The widest entries exist only so a grid wider than any panel we ship still
 * normalizes a stored tile to a real footprint instead of falling back.
 */
var MEDIA_MAX_COLUMNS = 8;

function mediaFootprints() {
    var sizes = [[2, 1], [2, 2], [2, 4], [2, 5], [2, 6], [2, 7], [2, 8]];
    for (var width = 3; width <= MEDIA_MAX_COLUMNS; width++) {
        for (var height = 2; height <= 8; height++)
            sizes.push([width, height]);
    }
    return sizes;
}

var TOGGLE_TYPES = {
    network: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    bluetooth: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    vpn: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    tailscale: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    kdeConnect: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
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
    laptopKeyboard: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    modes: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    notes: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },

    volumeSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    micSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    brightnessSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    gammaSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },

    // The one toggle with a design per footprint: see `mediaFootprints`.
    mediaWidget: {
        kind: "media",
        defaultSize: [2, 2],
        allowedSizes: mediaFootprints()
    },

    // The dashboard widgets use one column by two rows: across both the ii sidebar and
    // tablet shade this is the grid's near-square footprint. A single allowed size makes
    // the footprint immutable while keeping the same packer and persistence format.
    calendarWidget: { kind: "dashboardWidget", defaultSize: [1, 2], allowedSizes: [[1, 2]], families: ["tablet"] },
    tasksWidget: { kind: "dashboardWidget", defaultSize: [1, 2], allowedSizes: [[1, 2]], families: ["tablet"] },
    timerWidget: { kind: "dashboardWidget", defaultSize: [1, 2], allowedSizes: [[1, 2]], families: ["tablet"] },
    countdownWidget: { kind: "dashboardWidget", defaultSize: [1, 2], allowedSizes: [[1, 2]], families: ["tablet"] },
    pomodoroWidget: { kind: "dashboardWidget", defaultSize: [1, 2], allowedSizes: [[1, 2]], families: ["tablet"] },

    // Complete ports coexist with the summary cards above. They deliberately
    // use distinct stable types so existing pages never change appearance.
    // Formats supported: 2x2, 2x4, and 4x2 (defaulting to 2x2).
    fullCalendarWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet"] },
    fullTasksWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet"] },
    fullTimerWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet"] },
    fullCountdownWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet"] },
    fullPomodoroWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet"] },
    fullNotesWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet"] },

    // Number clock widget (Google Sans Flex die-cut stencil design, freeform sizing, minimum 1x1)
    clockWidget: {
        kind: "widget",
        defaultSize: [2, 1],
        families: ["island", "tablet"]
    },

    // Notification list widget for Dynamic Island (minimum 4xY, freeform height)
    notificationListWidget: {
        kind: "widget",
        defaultSize: [4, 4],
        minWidth: 4,
        maxHeight: 8,
        families: ["island"]
    },

    // The Dynamic Island dashboard's own toolbar (edit, reload, settings, session). It is
    // the only way into that grid's edit mode, so it is permanent: it can be moved and
    // resized but never removed, and it exists only in the island's grid.
    dashboardToolbar: {
        kind: "toolbar",
        defaultSize: [2, 1],
        allowedSizes: [
            [2, 1], [3, 1], [4, 1],
            [1, 2], [1, 3], [1, 4],
            [2, 2], [3, 2], [4, 2],
            [2, 3], [3, 3], [4, 3],
            [2, 4], [3, 4], [4, 4]
        ],
        families: ["island"],
        permanent: true
    }
};

function allTypes() {
    return Object.keys(TOGGLE_TYPES);
}
// The tray groups what it offers into a few broad sections. Deliberately coarse: the
// grids are narrow, and a section per handful of toggles would be mostly headers. The
// labels and icons live in QML (they are translated); this is only the assignment.
var CATEGORY_ORDER = ["connectivity", "system", "sliders", "widgets"];

var TYPE_CATEGORIES = {
    network: "connectivity", bluetooth: "connectivity", vpn: "connectivity",
    tailscale: "connectivity", kdeConnect: "connectivity", dnsOverTls: "connectivity",
    cloudflareWarp: "connectivity", localSend: "connectivity",

    // Everything else that toggles - display, audio, tools and system - is one section:
    // split further, most sections held a single row.
};

function canonicalType(type) {
    if (type === "toolbar" || type === "dashboardToolbar")
        return "dashboardToolbar";
    if (type === "flexClock" || type === "horiClock")
        return "clockWidget";
    if (type === "notificationListWidget" || type === "notificationWidget" || type === "notificationsWidget" || type === "notificationList" || type === "notificationsList")
        return "notificationListWidget";
    if (type === "calendar")
        return "fullCalendarWidget";
    if (type === "todo" || type === "fullTodoWidget" || type === "fullTodo" || type === "todoWidget")
        return "fullTasksWidget";
    if (type === "timer" || type === "stopwatch" || type === "fullStopwatchWidget" || type === "fullStopwatch")
        return "fullTimerWidget";
    if (type === "countdown")
        return "fullCountdownWidget";
    if (type === "pomodoro")
        return "fullPomodoroWidget";
    if (type === "notesWidget" || type === "notesDashboard" || type === "fullNotes")
        return "fullNotesWidget";
    return type;
}

/** The tray section a type belongs to. Sliders and widgets follow their kind. */
function category(type) {
    var resolved = canonicalType(type);
    var metadata = TOGGLE_TYPES[resolved];
    if (!metadata)
        return "system";
    if (metadata.kind === "slider")
        return "sliders";
    if (metadata.kind !== "toggle")
        return "widgets";
    return TYPE_CATEGORIES[resolved] || "system";
}

function categoryOrder() {
    return CATEGORY_ORDER.slice();
}

/** A permanent tile can be rearranged but never removed from its grid. */
function isPermanent(type) {
    var metadata = TOGGLE_TYPES[canonicalType(type)];
    return !!(metadata && metadata.permanent);
}

function hasType(type) {
    return typeof type === "string" && TOGGLE_TYPES[canonicalType(type)] !== undefined;
}

function kind(type) {
    var metadata = TOGGLE_TYPES[canonicalType(type)];
    return metadata ? metadata.kind : "unknown";
}

function availableForFamily(type, family) {
    var metadata = TOGGLE_TYPES[canonicalType(type)];
    if (!metadata || !metadata.families)
        return true;
    return metadata.families.indexOf(String(family || "")) !== -1;
}

function isResizable(type, columns) {
    var metadata = TOGGLE_TYPES[canonicalType(type)];
    if (!metadata || !metadata.allowedSizes)
        return true;
    var fitting = metadata.allowedSizes.filter(function(candidate) {
        return candidate[0] <= positiveColumns(columns);
    });
    return fitting.length > 1;
}

function defaultSize(type) {
    var metadata = TOGGLE_TYPES[canonicalType(type)];
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
    var resolvedType = canonicalType(type);
    var metadata = TOGGLE_TYPES[resolvedType];
    var cols = positiveColumns(columns);
    var fallback = defaultSize(resolvedType);
    var minW = metadata && metadata.minWidth !== undefined ? metadata.minWidth : ((metadata && metadata.kind === "toggle") ? 0 : 1);
    var rawW = finiteInteger(width, fallback[0]);
    var normalizedWidth = Math.max(minW, rawW);
    var normalizedHeight = Math.max(1, finiteInteger(height, fallback[1]));

    if (!metadata) {
        return [Math.min(normalizedWidth, cols), normalizedHeight];
    }

    if (metadata.fixedHeight !== undefined)
        normalizedHeight = metadata.fixedHeight;

    if (metadata.maxHeight !== undefined)
        normalizedHeight = Math.min(normalizedHeight, metadata.maxHeight);

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

    // Square toggle ([0, 1]) is strictly 1-row high. If height > 1, width cannot be 0.
    if (normalizedWidth === 0 && normalizedHeight > 1)
        normalizedWidth = 1;

    return [Math.min(normalizedWidth, cols), normalizedHeight];
}

function isSizeAllowed(type, width, height, columns) {
    var resolvedType = canonicalType(type);
    var normalized = normalizeSize(resolvedType, width, height, columns);
    var requestedWidth = finiteInteger(width, -1);
    var requestedHeight = finiteInteger(height, -1);
    if (requestedWidth !== normalized[0] || requestedHeight !== normalized[1])
        return false;

    var metadata = TOGGLE_TYPES[resolvedType];
    var minW = metadata && metadata.minWidth !== undefined ? Math.min(metadata.minWidth, positiveColumns(columns)) : ((metadata && metadata.kind === "toggle") ? 0 : 1);
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
    return requestedWidth >= minW && requestedWidth <= positiveColumns(columns) && requestedHeight >= 1 && requestedHeight <= (metadata.maxHeight || 8);
}

function item(type, id, width, height, columns) {
    var resolvedType = canonicalType(type);
    var normalized = normalizeSize(resolvedType, width, height, columns);
    var stableId = typeof id === "string" && id.length > 0 ? id : resolvedType;
    return {
        id: stableId,
        type: resolvedType,
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
