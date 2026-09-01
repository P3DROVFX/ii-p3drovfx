.pragma library

// Shared shape of mode / routine definitions stored in
// Config.options.modes.modes and Config.options.modes.routines.
//
// Everything that reads a definition goes through normalizeMode() so the rest
// of the engine can assume every field exists and has the right type.
// JsonAdapter hands back QML sequences rather than JS arrays, so arrays are
// always rebuilt with Array.from before being touched.

var SCHEMA_VERSION = 1;
var HISTORY_MAX = 200;

// Trigger types whose watcher exists. Anything else evaluates as unsatisfied
// (and is reported once).
var CONDITION_SOURCES = {
    schedule: "conditions/ScheduleCondition.qml",
    app: "conditions/AppCondition.qml",
    game: "conditions/GameCondition.qml",
    battery: "conditions/BatteryCondition.qml",
    wifi: "conditions/WifiCondition.qml",
    bluetooth: "conditions/BluetoothCondition.qml",
    monitors: "conditions/MonitorsCondition.qml",
    fullscreen: "conditions/FullscreenCondition.qml",
    locked: "conditions/LockedCondition.qml",
    modeActive: "conditions/ModeActiveCondition.qml",
    audioDevice: "conditions/AudioDeviceCondition.qml",
    idle: "conditions/IdleCondition.qml",
    workspace: "conditions/WorkspaceCondition.qml",
    media: "conditions/MediaCondition.qml",
    deviceInUse: "conditions/DeviceInUseCondition.qml",
    discordVoice: "conditions/DiscordVoiceCondition.qml",
    phone: "conditions/PhoneCondition.qml",
    pomodoro: "conditions/PomodoroCondition.qml",
    calendar: "conditions/CalendarCondition.qml",
    resource: "conditions/ResourceCondition.qml",
    vpn: "conditions/VpnCondition.qml",
    lid: "conditions/LidCondition.qml",
    weather: "conditions/WeatherCondition.qml",
    keyboardLayout: "conditions/KeyboardLayoutCondition.qml",
    updates: "conditions/UpdatesCondition.qml",
    notification: "conditions/NotificationCondition.qml",
    alarm: "conditions/AlarmCondition.qml",
    pomodoroLap: "conditions/PomodoroLapCondition.qml",
    shortcut: "conditions/ShortcutCondition.qml"
};

// Editor metadata per trigger type: label, icon, group in the "add
// condition" menu and which parameter form the editor row shows. Every
// trigger also accepts `not: true`, which flips its verdict ("Zoom is not
// running" is how "when X closes" is said), and `forSec`.
var TRIGGER_GROUPS = {
    time: "Time",
    windows: "Apps & windows",
    you: "What you're doing",
    system: "Power & system",
    connectivity: "Connectivity & devices",
    outside: "Outside",
    automation: "Automation",
    events: "Moments"
};

var TRIGGER_TYPES = {
    schedule: { label: "Schedule", icon: "schedule", editor: "schedule", group: "time" },
    calendar: { label: "Calendar event", icon: "event", editor: "calendar", group: "time" },
    app: { label: "App", icon: "apps", editor: "app", group: "windows" },
    game: { label: "Game", icon: "sports_esports", editor: "game", group: "windows" },
    fullscreen: { label: "Fullscreen window", icon: "fullscreen", editor: "none", group: "windows" },
    workspace: { label: "Workspace", icon: "grid_view", editor: "workspace", group: "windows" },
    idle: { label: "Away from the keyboard", icon: "hourglass_empty", editor: "idle", group: "you" },
    locked: { label: "Screen locked", icon: "lock", editor: "locked", group: "you" },
    lid: { label: "Laptop lid", icon: "laptop", editor: "lid", group: "you" },
    media: { label: "Media playing", icon: "music_note", editor: "media", group: "you" },
    deviceInUse: { label: "Mic, camera or screen in use", icon: "videocam", editor: "deviceInUse", group: "you" },
    discordVoice: { label: "Discord voice call", icon: "headset_mic", editor: "none", group: "you" },
    pomodoro: { label: "Pomodoro timer", icon: "timer", editor: "pomodoro", group: "you" },
    battery: { label: "Battery", icon: "battery_5_bar", editor: "battery", group: "system" },
    resource: { label: "CPU, GPU, memory or disk", icon: "memory", editor: "resource", group: "system" },
    keyboardLayout: { label: "Keyboard layout", icon: "keyboard", editor: "keyboardLayout", group: "system" },
    updates: { label: "Updates pending", icon: "system_update", editor: "updates", group: "system" },
    wifi: { label: "Wi-Fi", icon: "wifi", editor: "wifi", group: "connectivity" },
    vpn: { label: "VPN or Tailscale", icon: "vpn_lock", editor: "vpn", group: "connectivity" },
    bluetooth: { label: "Bluetooth", icon: "bluetooth", editor: "bluetooth", group: "connectivity" },
    phone: { label: "Phone", icon: "smartphone", editor: "phone", group: "connectivity" },
    monitors: { label: "Monitors", icon: "monitor", editor: "monitors", group: "connectivity" },
    audioDevice: { label: "Audio device", icon: "headphones", editor: "audioDevice", group: "connectivity" },
    weather: { label: "Weather", icon: "partly_cloudy_day", editor: "weather", group: "outside" },
    modeActive: { label: "Mode active", icon: "tune", editor: "modeActive", group: "automation", routineOnly: true },
    // Events: a moment rather than a state. They pulse, so only a "when"
    // routine (kind once) can use them.
    notification: { label: "A notification arrives", icon: "notifications_active", editor: "notification",
        group: "events", routineOnly: true, event: true },
    alarm: { label: "An alarm rings", icon: "alarm", editor: "none", group: "events", routineOnly: true, event: true },
    pomodoroLap: { label: "A Pomodoro lap ends", icon: "timer_off", editor: "pomodoroLap", group: "events",
        routineOnly: true, event: true },
    shortcut: { label: "A shortcut is pressed", icon: "keyboard_command_key", editor: "shortcut", group: "events",
        routineOnly: true, event: true }
};

function isEventTrigger(type) {
    return TRIGGER_TYPES[type]?.event === true;
}

// Global shortcut name for a shortcut trigger: the chosen name, else the
// owning routine's id; only what Hyprland accepts in a dispatcher arg.
function shortcutName(trigger, ownerId) {
    var raw = String((trigger && trigger.name) || ownerId || "routine");
    return slugify(raw);
}

// WWO weather codes (what the weather service stores in wCode) folded into
// the few kinds a condition can ask for.
function weatherKind(code) {
    var c = Number(code);
    if (c === 113)
        return "clear";
    if (c === 116 || c === 119 || c === 122)
        return "cloudy";
    if (c === 143 || c === 248 || c === 260)
        return "fog";
    if (c === 200 || c === 386 || c === 389 || c === 392 || c === 395)
        return "storm";
    var snow = [179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377];
    if (snow.indexOf(c) !== -1)
        return "snow";
    if (c >= 176)
        return "rain";
    return "";
}

// Default launcher class patterns for game detection (GameDetector signal 1).
var GAME_LAUNCHER_PATTERNS = [
    "^steam_app_\\d+$",
    "^gamescope",
    "^(heroic|lutris|bottles|net\\.lutris\\.)",
    "^(minecraft|prism)"
];

// The exact option set the Game Mode quick toggle writes
// (modules/common/models/quickToggles/GameModeToggle.qml). Kept identical so
// the Gaming preset and the toggle cannot drift apart.
var GAME_MODE_OPTIONS = {
    "animations:enabled": 0,
    "decoration:shadow:enabled": 0,
    "decoration:blur:enabled": 0,
    "general:gaps_in": 0,
    "general:gaps_out": 0,
    "general:border_size": 1,
    "decoration:rounding": 0,
    "decoration:rounding_power": 0,
    "general:allow_tearing": 1
};
var GAME_MODE_RULE_MARKER = "shell:game-mode-opaque";
var GAME_MODE_RULE = 'hl.window_rule({name="' + GAME_MODE_RULE_MARKER + '",match={class=".*"},'
    + 'opacity="1.0 override 1.0 override 1.0 override",opaque=true})';

// Named option sets for the `hyprland` action's preset chips.
var HYPRLAND_PRESETS = {
    animations: { "animations:enabled": 0 },
    blur: { "decoration:blur:enabled": 0 },
    shadows: { "decoration:shadow:enabled": 0 },
    gaps: { "general:gaps_in": 0, "general:gaps_out": 0 },
    rounding: { "decoration:rounding": 0, "decoration:rounding_power": 0 },
    tearing: { "general:allow_tearing": 1 }
};

function isArrayLike(value) {
    return typeof value === "object" && value !== null && typeof value.length === "number";
}

function toArray(value) {
    if (value === undefined || value === null)
        return [];
    if (Array.isArray(value))
        return value.slice();
    if (isArrayLike(value))
        return Array.from(value);
    return [];
}

// Deep copy through JSON so nothing keeps a reference into the adapter.
function clone(value) {
    if (value === undefined)
        return undefined;
    return JSON.parse(JSON.stringify(value));
}

function slugify(text) {
    return String(text || "")
        .toLowerCase()
        .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "") || "mode";
}

function uniqueId(base, taken) {
    var id = base;
    var n = 2;
    while (taken.indexOf(id) !== -1) {
        id = base + "-" + n;
        n += 1;
    }
    return id;
}

function stringList(value) {
    return toArray(value)
        .map(function (x) { return String(x); })
        .filter(function (x) { return x.length > 0; });
}

function optionalBool(value) {
    return typeof value === "boolean" ? value : null;
}

function optionalInt(value, min, max) {
    if (value === null || value === undefined || value === "")
        return null;
    var n = Number(value);
    if (!isFinite(n))
        return null;
    return Math.max(min, Math.min(max, Math.round(n)));
}

var MAX_DURATION_SEC = 86400;

function durationSec(value) {
    var n = Number(value);
    if (!isFinite(n) || n <= 0)
        return 0;
    return Math.min(MAX_DURATION_SEC, Math.round(n));
}

// Every trigger also accepts `forSec`: the verdict must hold that long
// before it counts ("idle for 10 min", "in a game for 5 min").
function normalizeTrigger(raw) {
    var t = (raw && typeof raw === "object") ? clone(raw) : {};
    t.type = typeof t.type === "string" ? t.type : "";
    t.not = t.not === true;
    t.forSec = durationSec(t.forSec);
    switch (t.type) {
    case "schedule":
        t.from = validTime(t.from) ? t.from : "22:00";
        t.to = validTime(t.to) ? t.to : "07:00";
        var days = toArray(t.days).map(Number).filter(function (d) { return d >= 1 && d <= 7; });
        t.days = days.length ? days : [1, 2, 3, 4, 5, 6, 7];
        break;
    case "app":
        t.classes = stringList(t.classes);
        t.title = typeof t.title === "string" ? t.title.trim() : "";
        t.when = t.when === "focused" ? "focused" : "running";
        break;
    case "game":
        t.when = t.when === "focused" ? "focused" : "running";
        break;
    case "battery":
        t.below = optionalInt(t.below, 0, 100);
        t.above = optionalInt(t.above, 0, 100);
        t.pluggedIn = optionalBool(t.pluggedIn);
        break;
    case "wifi":
        t.ssids = stringList(t.ssids);
        t.connected = t.connected !== false;
        t.ethernet = optionalBool(t.ethernet);
        break;
    case "bluetooth":
        t.devices = stringList(t.devices).map(function (a) { return a.toUpperCase(); });
        t.connected = t.connected !== false;
        break;
    case "monitors":
        t.count = optionalInt(t.count, 1, 16) || 2;
        t.names = stringList(t.names);
        break;
    case "locked":
        t.is = t.is !== false;
        break;
    case "modeActive":
        t.id = typeof t.id === "string" ? t.id : "";
        break;
    case "audioDevice":
        t.match = typeof t.match === "string" ? t.match : "";
        t.kind = t.kind === "source" ? "source" : "sink";
        break;
    case "idle":
        t.sec = Math.max(5, durationSec(t.sec) || 300);
        t.ignoreInhibitors = t.ignoreInhibitors === true;
        break;
    case "workspace":
        t.names = stringList(t.names);
        t.special = t.special === true;
        break;
    case "media":
        t.playing = t.playing !== false;
        t.player = typeof t.player === "string" ? t.player.trim() : "";
        break;
    case "deviceInUse":
        t.what = ["mic", "camera", "screen"].indexOf(t.what) !== -1 ? t.what : "mic";
        break;
    case "phone":
        t.reachable = t.reachable !== false;
        t.batteryBelow = optionalInt(t.batteryBelow, 1, 100);
        break;
    case "pomodoro":
        t.phase = ["focus", "break", "any"].indexOf(t.phase) !== -1 ? t.phase : "any";
        break;
    case "calendar":
        t.match = typeof t.match === "string" ? t.match.trim() : "";
        break;
    case "resource":
        t.metric = RESOURCE_METRICS.indexOf(t.metric) !== -1 ? t.metric : "cpuUsage";
        t.above = optionalInt(t.above, 0, 1000);
        t.below = optionalInt(t.below, 0, 1000);
        if (t.above === null && t.below === null)
            t.above = 80;
        break;
    case "vpn":
        t.kind = t.kind === "tailscale" ? "tailscale" : "vpn";
        t.connected = t.connected !== false;
        break;
    case "lid":
        t.closed = t.closed !== false;
        break;
    case "weather":
        t.kind = WEATHER_KINDS.indexOf(t.kind) !== -1 ? t.kind : "any";
        t.tempBelow = optionalInt(t.tempBelow, -100, 150);
        t.tempAbove = optionalInt(t.tempAbove, -100, 150);
        break;
    case "keyboardLayout":
        t.code = typeof t.code === "string" ? t.code.trim().toLowerCase() : "";
        break;
    case "updates":
        t.atLeast = Math.max(1, optionalInt(t.atLeast, 1, 10000) || 1);
        break;
    case "notification":
        t.app = typeof t.app === "string" ? t.app.trim() : "";
        t.text = typeof t.text === "string" ? t.text.trim() : "";
        break;
    case "pomodoroLap":
        t.lap = ["focusEnd", "breakEnd", "any"].indexOf(t.lap) !== -1 ? t.lap : "any";
        break;
    case "shortcut":
        t.name = typeof t.name === "string" && t.name.trim().length ? slugify(t.name) : "";
        break;
    }
    // A pulse is a moment; holding it for a while makes no sense.
    if (isEventTrigger(t.type))
        t.forSec = 0;
    return t;
}

var RESOURCE_METRICS = ["cpuUsage", "cpuTemp", "gpuUsage", "gpuTemp", "memory", "swap", "disk"];
var WEATHER_KINDS = ["any", "clear", "cloudy", "fog", "rain", "snow", "storm"];

// Class patterns: a plain name matches exactly (case-insensitive); anything
// containing regex metacharacters is taken as a regex.
function classRegex(text) {
    var s = String(text || "").trim();
    if (!s.length)
        return null;
    try {
        if (/[\\^$.*+?()\[\]{}|]/.test(s))
            return new RegExp(s, "i");
        return new RegExp("^" + s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$", "i");
    } catch (e) {
        return null;
    }
}

function classRegexes(list) {
    return toArray(list).map(classRegex).filter(function (r) { return r !== null; });
}

// Hyprland client JSON carries both `class` and `initialClass`; match
// either. With `titleRegex` the title has to match as well (or alone, when
// there are no class patterns).
function windowMatches(win, regexes, titleRegex) {
    if (!win)
        return false;
    if (titleRegex && !titleRegex.test(String(win.title || "")))
        return false;
    if (regexes.length === 0)
        return !!titleRegex;
    var a = String(win.initialClass || "");
    var b = String(win["class"] || "");
    for (var i = 0; i < regexes.length; ++i) {
        if ((a.length && regexes[i].test(a)) || (b.length && regexes[i].test(b)))
            return true;
    }
    return false;
}

// Title patterns: plain text matches anywhere (case-insensitive); anything
// with regex metacharacters is a regex.
function titleRegex(text) {
    var s = String(text || "").trim();
    if (!s.length)
        return null;
    try {
        if (/[\\^$.*+?()\[\]{}|]/.test(s))
            return new RegExp(s, "i");
        return new RegExp(s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i");
    } catch (e) {
        return null;
    }
}

// `revert: false` keeps an action's effect when its owner ends (routines
// offer it per action); absent means revert like everything else.
// `delaySec` holds the action — and everything below it — that long after
// the previous step; a `wait` action is the same pause as a row of its own.
function normalizeAction(raw) {
    var a = (raw && typeof raw === "object") ? clone(raw) : {};
    a.type = typeof a.type === "string" ? a.type : "";
    if (a.value === undefined)
        a.value = null;
    if (typeof a.revert !== "boolean")
        delete a.revert;
    var delay = durationSec(a.delaySec);
    if (delay > 0)
        a.delaySec = delay;
    else
        delete a.delaySec;
    if (a.type === "wait")
        a.value = Math.max(1, durationSec(a.value) || 60);
    return a;
}

// Seconds an action holds the sequence before it runs (its own delay, or
// the length of a wait step).
function actionPauseSec(action) {
    if (!action)
        return 0;
    if (action.type === "wait")
        return durationSec(action.value);
    return durationSec(action.delaySec);
}

// Total time from start to the last action, for the editor's summary.
function sequenceSpanSec(actions) {
    var total = 0;
    toArray(actions).forEach(function (a) { total += actionPauseSec(a); });
    return total;
}

function normalizeMode(raw) {
    var m = (raw && typeof raw === "object") ? clone(raw) : {};
    m.id = typeof m.id === "string" && m.id.length ? m.id : slugify(m.name);
    m.name = typeof m.name === "string" && m.name.length ? m.name : m.id;
    m.icon = typeof m.icon === "string" && m.icon.length ? m.icon : "tune";
    m.color = typeof m.color === "string" ? m.color : "";
    m.preset = m.preset === true;
    m.auto = m.auto === true;
    // Banner when it starts; the end half lives in m.end.notify.
    m.notify = m.notify !== false;
    m.match = m.match === "all" ? "all" : "any";
    m.triggers = toArray(m.triggers).map(normalizeTrigger).filter(function (t) { return t.type.length > 0; });
    m.actions = toArray(m.actions).map(normalizeAction).filter(function (a) { return a.type.length > 0; });
    var end = (m.end && typeof m.end === "object") ? m.end : {};
    m.end = {
        revert: end.revert !== false,
        strict: end.strict === true,
        autoOffMin: Math.max(0, Number(end.autoOffMin) || 0),
        notify: end.notify !== false
    };
    return m;
}

function normalizeModes(rawList) {
    var taken = [];
    return toArray(rawList).map(function (raw) {
        var m = normalizeMode(raw);
        m.id = uniqueId(m.id, taken);
        taken.push(m.id);
        return m;
    });
}

// Routines share the trigger/action vocabulary but are not exclusive.
//  - kind "while": applies on true, reverts on false (same grace as modes)
//  - kind "once":  fires on the false→true edge, never reverts, honours cooldownSec
function normalizeRoutine(raw) {
    var r = (raw && typeof raw === "object") ? clone(raw) : {};
    r.id = typeof r.id === "string" && r.id.length ? r.id : slugify(r.name);
    r.name = typeof r.name === "string" && r.name.length ? r.name : r.id;
    r.icon = typeof r.icon === "string" && r.icon.length ? r.icon : "bolt";
    r.color = typeof r.color === "string" ? r.color : "";
    r.preset = r.preset === true;
    r.template = typeof r.template === "string" ? r.template : "";
    r.enabled = r.enabled !== false;
    r.kind = r.kind === "once" ? "once" : "while";
    r.match = r.match === "all" ? "all" : "any";
    r.cooldownSec = Math.max(0, Number(r.cooldownSec) || 0);
    r.notify = r.notify !== false;
    r.triggers = toArray(r.triggers).map(normalizeTrigger).filter(function (t) { return t.type.length > 0; });
    r.actions = toArray(r.actions).map(normalizeAction).filter(function (a) { return a.type.length > 0; });
    var end = (r.end && typeof r.end === "object") ? r.end : {};
    r.end = {
        revert: r.kind === "while" && end.revert !== false,
        strict: end.strict === true,
        // Split out of the single banner switch: definitions written before
        // the split take their end half from what they already had.
        notify: end.notify === undefined ? r.notify : end.notify !== false
    };
    return r;
}

function normalizeRoutines(rawList) {
    var taken = [];
    return toArray(rawList).map(function (raw) {
        var r = normalizeRoutine(raw);
        r.id = uniqueId(r.id, taken);
        taken.push(r.id);
        return r;
    });
}

var SUN_TOKENS = ["sunrise", "sunset"];

function validTime(text) {
    return typeof text === "string"
        && (/^([01]\d|2[0-3]):[0-5]\d$/.test(text) || SUN_TOKENS.indexOf(text) !== -1);
}

// "HH:MM" (or "h:MM AM/PM", which the weather service may hand back) to
// minutes since midnight; -1 when unreadable.
function clockMinutes(text) {
    var m = /^\s*(\d{1,2}):(\d{2})\s*(AM|PM)?\s*$/i.exec(String(text || ""));
    if (!m)
        return -1;
    var h = Number(m[1]);
    if (m[3]) {
        h = h % 12;
        if (m[3].toUpperCase() === "PM")
            h += 12;
    }
    return h * 60 + Number(m[2]);
}

// `sun` is { sunrise, sunset } as clock text, for the tokens; without it a
// token does not resolve and the window is closed.
function timeToMinutes(text, sun) {
    if (SUN_TOKENS.indexOf(text) !== -1) {
        var t = sun ? clockMinutes(sun[text]) : -1;
        // The service's placeholder before any fetch.
        if (t === 0 && sun && clockMinutes(sun.sunrise) === 0 && clockMinutes(sun.sunset) === 0)
            return -1;
        return t;
    }
    return clockMinutes(text);
}

// ISO weekday, 1 = Monday … 7 = Sunday.
function isoDay(date) {
    return ((date.getDay() + 6) % 7) + 1;
}

// Whether `date` falls inside a schedule trigger. Overnight windows belong to
// the day they start on: 23:00–07:00 on Friday runs into Saturday morning.
function scheduleSatisfied(trigger, date, sun) {
    var from = timeToMinutes(trigger.from, sun);
    var to = timeToMinutes(trigger.to, sun);
    var now = date.getHours() * 60 + date.getMinutes();
    var days = toArray(trigger.days);
    if (from < 0 || to < 0 || from === to)
        return false;
    if (from < to)
        return now >= from && now < to && days.indexOf(isoDay(date)) !== -1;
    if (now >= from)
        return days.indexOf(isoDay(date)) !== -1;
    if (now < to) {
        var yesterday = new Date(date.getTime() - 86400000);
        return days.indexOf(isoDay(yesterday)) !== -1;
    }
    return false;
}

// Epoch ms of the moment the currently satisfied window ends, 0 if not inside one.
function scheduleEndsAt(trigger, date, sun) {
    if (!scheduleSatisfied(trigger, date, sun))
        return 0;
    var to = timeToMinutes(trigger.to, sun);
    var end = new Date(date.getTime());
    end.setSeconds(0, 0);
    end.setHours(Math.floor(to / 60), to % 60, 0, 0);
    if (end.getTime() <= date.getTime())
        end.setTime(end.getTime() + 86400000);
    return end.getTime();
}

// Objects with their keys in a fixed order: a snapshot that went through
// the state file comes back with its keys sorted, and must still compare
// equal to the value read live.
function canonical(value) {
    if (value === null || value === undefined)
        return value;
    if (Array.isArray(value) || isArrayLike(value))
        return toArray(value).map(canonical);
    if (typeof value !== "object")
        return value;
    var out = {};
    Object.keys(value).sort().forEach(function (key) { out[key] = canonical(value[key]); });
    return out;
}

function valuesEqual(a, b) {
    if (a === b)
        return true;
    if (a === null || b === null || a === undefined || b === undefined)
        return false;
    if (typeof a === "number" && typeof b === "number")
        return Math.abs(a - b) < 1e-6;
    if (typeof a === "object" || typeof b === "object") {
        try {
            return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
        } catch (e) {
            return false;
        }
    }
    return false;
}

// Seeded once into Config.options.modes.modes. All ship with auto off: a
// preset must never start on its own before the user has looked at it.
function presets() {
    var all = [1, 2, 3, 4, 5, 6, 7];
    return [
        {
            id: "sleep", name: "Sleep", icon: "bedtime",
            color: "", preset: true, auto: false, match: "any",
            triggers: [{ type: "schedule", from: "23:00", to: "07:00", days: all }],
            actions: [
                { type: "dnd", value: true },
                { type: "nightLight", value: true },
                { type: "screenShader", value: "grayscale" },
                { type: "brightness", value: 20 },
                { type: "keepAwake", value: false }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        },
        {
            id: "work", name: "Work", icon: "work",
            color: "", preset: true, auto: false, match: "any",
            triggers: [{ type: "schedule", from: "09:00", to: "18:00", days: [1, 2, 3, 4, 5] }],
            actions: [
                { type: "dnd", value: true },
                { type: "keepAwake", value: true },
                { type: "powerProfile", value: "balanced" }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        },
        {
            id: "focus", name: "Focus", icon: "center_focus_strong",
            color: "", preset: true, auto: false, match: "any",
            triggers: [],
            actions: [
                { type: "dnd", value: true },
                { type: "media", value: "pause" }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        },
        {
            id: "gaming", name: "Gaming", icon: "sports_esports",
            color: "", preset: true, auto: false, match: "any",
            triggers: [{ type: "game", when: "running" }],
            actions: [
                { type: "gameMode", value: true },
                { type: "dnd", value: true },
                { type: "powerProfile", value: "performance" },
                { type: "keepAwake", value: true },
                { type: "nightLight", value: false }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        },
        {
            id: "theater", name: "Theater", icon: "theaters",
            color: "", preset: true, auto: false, match: "any",
            triggers: [{ type: "fullscreen" }],
            actions: [
                { type: "dnd", value: true },
                { type: "keepAwake", value: true },
                { type: "nightLight", value: false }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        },
        {
            id: "presentation", name: "Presentation", icon: "co_present",
            color: "", preset: true, auto: false, match: "any",
            triggers: [{ type: "monitors", count: 2 }],
            actions: [
                { type: "dnd", value: true },
                { type: "keepAwake", value: true },
                { type: "nightLight", value: false },
                { type: "screenShader", value: "" }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        },
        {
            id: "relax", name: "Relax", icon: "spa",
            color: "", preset: true, auto: false, match: "any",
            triggers: [{ type: "schedule", from: "20:00", to: "23:00", days: all }],
            actions: [
                { type: "nightLight", value: true },
                { type: "brightness", value: 50 }
            ],
            end: { revert: true, strict: false, autoOffMin: 0, notify: true }
        }
    ];
}

// Ready-made routines offered in the editor's Templates group (Samsung's
// "Discover"). Adding one copies it into the list; the copy is then an
// ordinary routine, linked back here only by `template` so the list can say
// it has been added already.
function routineTemplates() {
    return [
        {
            template: "battery-saver", id: "battery-saver", name: "Battery saver below 20 %",
            icon: "battery_alert", color: "orange", enabled: true, kind: "while", match: "all",
            triggers: [{ type: "battery", below: 20, pluggedIn: false }],
            actions: [
                { type: "powerProfile", value: "power-saver" },
                { type: "brightness", value: { level: 40, scope: "all" } }
            ],
            cooldownSec: 0, notify: true, end: { revert: true, strict: false }
        },
        {
            template: "focus-headphones", id: "focus-headphones", name: "Focus when headphones connect",
            icon: "headphones", color: "purple", enabled: true, kind: "once", match: "any",
            triggers: [{ type: "audioDevice", kind: "sink", match: "headphone" }],
            actions: [{ type: "mode", value: { action: "start", id: "focus" } }],
            cooldownSec: 60, notify: true, end: { revert: false, strict: false }
        },
        {
            template: "pause-on-lock", id: "pause-on-lock", name: "Pause media on lock",
            icon: "pause_circle", color: "blue", enabled: true, kind: "once", match: "any",
            triggers: [{ type: "locked", is: true }],
            actions: [{ type: "media", value: "pause" }],
            cooldownSec: 5, notify: false, end: { revert: false, strict: false }
        },
        {
            template: "mute-after-call", id: "mute-after-call", name: "Mute mic when Zoom closes",
            icon: "mic_off", color: "red", enabled: true, kind: "once", match: "any",
            triggers: [{ type: "app", when: "running", classes: ["zoom", "Zoom", "us.zoom.Zoom"], not: true }],
            actions: [{ type: "micMute", value: true }],
            cooldownSec: 30, notify: true, end: { revert: false, strict: false }
        },
        {
            template: "performance-gaming", id: "performance-gaming", name: "Performance profile while a game runs",
            icon: "speed", color: "green", enabled: true, kind: "while", match: "any",
            triggers: [{ type: "game", when: "running" }],
            actions: [{ type: "powerProfile", value: "performance" }],
            cooldownSec: 0, notify: false, end: { revert: true, strict: false }
        },
        {
            template: "quiet-in-calls", id: "quiet-in-calls", name: "Quiet while the mic is in use",
            icon: "voice_chat", color: "teal", enabled: true, kind: "while", match: "any",
            triggers: [{ type: "deviceInUse", what: "mic" }],
            actions: [
                { type: "dnd", value: true },
                { type: "media", value: "pause" }
            ],
            cooldownSec: 0, notify: false, end: { revert: true, strict: false }
        },
        {
            template: "lock-phone-away", id: "lock-phone-away", name: "Lock when the phone is out of reach",
            icon: "phonelink_lock", color: "blue", enabled: true, kind: "once", match: "any",
            triggers: [{ type: "phone", reachable: false, forSec: 120 }],
            actions: [{ type: "lock", value: null }],
            cooldownSec: 300, notify: true, end: { revert: false, strict: false }
        },
        {
            template: "break-reminder", id: "break-reminder", name: "Break reminder after 50 min of Work",
            icon: "self_improvement", color: "green", enabled: true, kind: "once", match: "any",
            triggers: [{ type: "modeActive", id: "work", forSec: 3000 }],
            actions: [{ type: "notify", value: { title: "Time for a break", body: "Work has been on for 50 minutes.", icon: "" } }],
            cooldownSec: 0, notify: false, end: { revert: false, strict: false }
        },
        {
            template: "suspend-locked-battery", id: "suspend-locked-battery", name: "Suspend when locked for 30 min on battery",
            icon: "bedtime", color: "purple", enabled: true, kind: "once", match: "all",
            triggers: [
                { type: "locked", is: true, forSec: 1800 },
                { type: "battery", pluggedIn: false }
            ],
            actions: [{ type: "suspend", value: null }],
            cooldownSec: 600, notify: false, end: { revert: false, strict: false }
        }
    ];
}

function routineTemplate(key) {
    var all = routineTemplates();
    for (var i = 0; i < all.length; ++i) {
        if (all[i].template === key)
            return all[i];
    }
    return null;
}

// Routines that `actions` would set in motion, directly (run another
// routine) or through a mode (start a mode that another routine waits for).
function routinesTriggeredBy(actions, routines) {
    var out = [];
    toArray(actions).forEach(function (a) {
        var v = (a && a.value && typeof a.value === "object") ? a.value : {};
        if (a.type === "routine" && v.action !== "stop" && typeof v.id === "string" && v.id.length) {
            if (out.indexOf(v.id) === -1)
                out.push(v.id);
        } else if (a.type === "mode" && v.action !== "stop" && typeof v.id === "string" && v.id.length) {
            toArray(routines).forEach(function (r) {
                var waits = toArray(r.triggers).some(function (t) {
                    return t.type === "modeActive" && !t.not && (t.id === "" || t.id === v.id);
                });
                if (waits && out.indexOf(r.id) === -1)
                    out.push(r.id);
            });
        }
    });
    return out;
}

// If running `actions` as routine `ownerId` would eventually run `ownerId`
// again, returns the chain of routine ids that closes the loop (without the
// owner at either end); otherwise null.
function routineLoop(ownerId, actions, routines) {
    var byId = {};
    toArray(routines).forEach(function (r) { byId[r.id] = r; });
    var seen = {};
    function walk(id, path) {
        if (id === ownerId)
            return path;
        if (seen[id])
            return null;
        seen[id] = true;
        var r = byId[id];
        if (!r)
            return null;
        var next = routinesTriggeredBy(r.actions, routines);
        for (var i = 0; i < next.length; ++i) {
            var found = walk(next[i], path.concat([id]));
            if (found)
                return found;
        }
        return null;
    }
    var starts = routinesTriggeredBy(actions, routines);
    for (var i = 0; i < starts.length; ++i) {
        var found = walk(starts[i], []);
        if (found)
            return found;
    }
    return null;
}
