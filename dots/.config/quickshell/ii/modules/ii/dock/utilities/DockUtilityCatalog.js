.pragma library

// The utility widgets the dock can host, and the rules every surface shares
// about them (the dock model, Settings, Edit Mode, the widget menu). Pure JS so
// it can be tested without the dock.
//
// A widget is saved as { kind, wide } in dock.utilityWidgets; its place in the
// dock is the "util:<kind>" key in dock.order. `file` names the tile and the
// panel in this folder: <file>Tile.qml and, when `panel` is set, <file>Panel.qml.
// Titles and descriptions are translation keys (Translation.tr at the caller).

var KEY_PREFIX = "util:";
var WIDE_SLOTS = 3;

var kinds = [
    { kind: "stopwatch", file: "Stopwatch", group: "time", symbol: "timer",
      title: "Stopwatch", description: "Counts up, with laps.",
      panel: true, settings: true, drops: false },
    { kind: "timer", file: "Timer", group: "time", symbol: "hourglass_top",
      title: "Timer", description: "Counts down, with the progress ring drawn on the icon.",
      panel: true, settings: true, drops: false },
    { kind: "pomodoro", file: "Pomodoro", group: "time", symbol: "target",
      title: "Pomodoro", description: "Focus, short break, long break. Today's cycles marked on the tile.",
      panel: true, settings: true, drops: false },
    { kind: "clock", file: "Clock", group: "time", symbol: "schedule",
      title: "Clock", description: "The time, hh:mm, in tall expressive digits.",
      panel: false, settings: false, drops: false, wideSlots: 2 },
    { kind: "calendar", file: "Calendar", group: "system", symbol: "calendar_month",
      title: "Calendar", description: "The date on the icon, what's next on the card, the whole day in the panel.",
      panel: true, settings: false, drops: false },
    { kind: "battery", file: "Battery", group: "system", symbol: "battery_full",
      title: "Battery", description: "The charge and how long it still lasts.",
      panel: true, settings: false, drops: false },
    { kind: "aiUsage", file: "AiUsage", group: "system", symbol: "auto_awesome",
      title: "AI usage", description: "How much of your AI plan is gone, and when it resets. Claude, ChatGPT, Antigravity and more.",
      panel: true, settings: true, drops: false },
    { kind: "disk", file: "Disk", group: "system", symbol: "hard_drive",
      title: "Disk usage", description: "How full the chosen disk is, and what is still free.",
      panel: false, settings: true, drops: false },
    { kind: "files", file: "Files", group: "files", symbol: "download",
      title: "Files", description: "Your Downloads, or a folder you pick: what arrived last and how many are new.",
      panel: true, settings: true, drops: false },
    { kind: "shelf", file: "Shelf", group: "files", symbol: "shelves",
      title: "Shelf", description: "A place to leave files in the middle of a drag and pick them up later.",
      panel: true, settings: true, drops: true },
    { kind: "send", file: "Send", group: "files", symbol: "send_to_mobile",
      title: "Send", description: "Drop files on it to send them over KDE Connect or LocalSend.",
      panel: true, settings: false, drops: true },
    { kind: "screenshots", file: "Screenshots", group: "files", symbol: "screenshot_region",
      title: "Screenshots", description: "Your latest captures, to drag straight to where you need them.",
      panel: true, settings: true, drops: false },
    { kind: "search", file: "Search", group: "tools", symbol: "search",
      title: "Search", description: "A door into the shell's search: an icon, or a search bar.",
      panel: false, settings: true, drops: false },
    { kind: "favorites", file: "Favorites", group: "tools", symbol: "bookmarks",
      title: "Favorites", description: "The sites you open every day, one click each.",
      panel: true, settings: true, drops: false },
    { kind: "colorPicker", file: "ColorPicker", group: "tools", symbol: "colorize",
      title: "Color picker", description: "Pick any color on screen. The code goes to the clipboard and the last ones stay on the tile.",
      panel: true, settings: false, drops: false },
    { kind: "clipboard", file: "Clipboard", group: "tools", symbol: "content_paste",
      title: "Clipboard", description: "The history of what you copied, with pins. Text, images and files.",
      panel: true, settings: false, drops: false },
    { kind: "water", file: "Water", group: "tools", symbol: "water_drop",
      title: "Water", description: "One glass at a time, the daily goal, and the week on the card.",
      panel: true, settings: true, drops: false },
    { kind: "tools", file: "Tools", group: "tools", symbol: "handyman",
      title: "Tools", description: "The bar's quick tools: screenshot, screen record, color picker, dark mode and more.",
      panel: true, settings: true, drops: false },
    { kind: "converter", file: "Converter", group: "tools", symbol: "swap_horiz",
      title: "Converter", description: "Length, weight, temperature, data. Type on one side, read the other.",
      panel: true, settings: false, drops: false },
];

// Kinds that were renamed: saved entries and dock.order keys still using the
// old name keep their place.
var aliases = { claudeUsage: "aiUsage" };

function canonical(kind) {
    return aliases[kind] || kind;
}

var groups = [
    { id: "time", title: "Time" },
    { id: "system", title: "System" },
    { id: "files", title: "Files" },
    { id: "tools", title: "Tools" },
];

function find(kind) {
    kind = canonical(kind);
    for (var i = 0; i < kinds.length; i++) {
        if (kinds[i].kind === kind)
            return kinds[i];
    }
    return null;
}

function orderKey(kind) {
    return KEY_PREFIX + kind;
}

function isOrderKey(key) {
    return typeof key === "string" && key.indexOf(KEY_PREFIX) === 0;
}

function kindFromOrderKey(key) {
    return isOrderKey(key) ? canonical(key.slice(KEY_PREFIX.length)) : "";
}

// Saved entries, cleaned: known kinds only, one per kind, `wide` a bool.
// Older or hand-edited configs may hold plain strings; they read as square.
function normalize(entries) {
    var out = [];
    var seen = {};
    var list = entries || [];
    for (var i = 0; i < list.length; i++) {
        var raw = list[i];
        var kind = canonical(typeof raw === "string" ? raw : String((raw && raw.kind) || ""));
        if (!find(kind) || seen[kind])
            continue;
        seen[kind] = true;
        out.push({ kind: kind, wide: !!(raw && raw.wide) });
    }
    return out;
}

function entryFor(entries, kind) {
    var list = normalize(entries);
    for (var i = 0; i < list.length; i++) {
        if (list[i].kind === kind)
            return list[i];
    }
    return null;
}

// A vertical dock has one slot of width for everything, so a wide widget
// shows its square face there. A kind may ask for fewer (or more) slots than
// WIDE_SLOTS for its wide face (`wideSlots`): a clock does not need three.
function wideSlotsFor(kind) {
    const info = find(kind);
    return info && info.wideSlots ? info.wideSlots : WIDE_SLOTS;
}

function slotsFor(entry, vertical) {
    if (!entry || vertical)
        return 1;
    return entry.wide ? wideSlotsFor(entry.kind) : 1;
}

function withKind(entries, kind, wide) {
    kind = canonical(kind);
    var list = normalize(entries);
    for (var i = 0; i < list.length; i++) {
        if (list[i].kind === kind) {
            list[i] = { kind: kind, wide: !!wide };
            return list;
        }
    }
    if (find(kind))
        list.push({ kind: kind, wide: !!wide });
    return list;
}

function withoutKind(entries, kind) {
    kind = canonical(kind);
    return normalize(entries).filter(function (entry) { return entry.kind !== kind; });
}

function kindsInGroup(groupId) {
    return kinds.filter(function (entry) { return entry.group === groupId; });
}
