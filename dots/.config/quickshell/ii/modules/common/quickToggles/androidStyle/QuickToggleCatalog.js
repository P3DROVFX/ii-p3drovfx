.pragma library

// The catalog is deliberately independent from QML, Config, and services. It
// is the only place where quick-toggle kinds, defaults, and size constraints
// are defined. The UI may add presentation metadata, but it must not invent a
// second size policy.
//
// `families` names the hosts that offer a tile. The android grid's hosts are
// `"ii"` (the desktop sidebar), `"island"` (the Dynamic Island's dashboard) and
// `"tablet"` (the shade); omitting the field offers the tile everywhere. The
// island's widget designs are offered to the sidebar as well - same grid, same
// tile, same persistence - so only what a host has to provide itself stays
// restricted: the island's toolbar, the tablet's own 1x2 cards, and a tile that
// needs a host which can lay a surface over the grid.
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

function expressiveMediaFootprints() {
    var sizes = [];
    for (var width = 4; width <= MEDIA_MAX_COLUMNS; width++) {
        for (var height = 2; height <= 4; height++)
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
    discordVoice: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    phoneCamera: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    phoneMic: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    phoneMirror: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },
    speedTest: { kind: "toggle", defaultSize: [1, 1], maxHeight: 8 },

    volumeSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    micSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    brightnessSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },
    gammaSlider: { kind: "slider", defaultSize: [4, 1], maxHeight: 8 },

    // Media: several designs of one tile. They share a variant group, so the tray
    // offers them as a single entry the user cycles through before adding one; once on
    // the grid each is its own type and keeps its design.
    mediaWidget: {
        kind: "widget",
        variantGroup: "media",
        defaultSize: [2, 2],
        allowedSizes: mediaFootprints(),
        families: ["island", "tablet", "ii"]
    },
    mediaCircleWidget: {
        kind: "widget",
        variantGroup: "media",
        defaultSize: [2, 2],
        maxHeight: 8,
        families: ["island", "tablet", "ii"]
    },
    expressiveMediaWidget: {
        kind: "widget",
        variantGroup: "media",
        defaultSize: [4, 2],
        allowedSizes: expressiveMediaFootprints(),
        families: ["island", "tablet", "ii"]
    },
    cdMediaWidget: {
        kind: "widget",
        variantGroup: "media",
        defaultSize: [2, 2],
        allowedSizes: [[2, 2]],
        families: ["island", "tablet", "ii"]
    },
    compactMediaWidget: {
        kind: "widget",
        variantGroup: "media",
        defaultSize: [4, 2],
        allowedSizes: [[4, 2], [2, 2]],
        families: ["island", "tablet", "ii"]
    },
    nothingRingMediaWidget: {
        kind: "widget",
        variantGroup: "media",
        defaultSize: [2, 2],
        maxHeight: 8,
        families: ["island", "tablet", "ii"]
    },

    // Battery: several designs of one tile. They share a variant group, so the tray
    // offers them as a single entry the user cycles through before adding one; once on
    // the grid each is its own type and keeps its design.
    bluetoothBatteryWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    mobileBatteryWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    bluetoothHeadphoneCookieWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    pcBatteryBarsWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    pcBatteryCableWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    devicesBatteryListWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    bluetoothEarbudsStemWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    laptopBatteryWidget: { kind: "widget", variantGroup: "battery", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },

    // System resources: the combined tile shows up to four monitors and the four others
    // give a monitor a tile of its own. All free-form: the tiles pick their arrangement
    // from the surface they are given, so only the minimum footprint matters here.
    systemResourcesWidget: { kind: "widget", variantGroup: "resources", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    cpuResourceWidget: { kind: "widget", variantGroup: "resources", defaultSize: [2, 1], maxHeight: 8, families: ["island", "tablet", "ii"] },
    ramResourceWidget: { kind: "widget", variantGroup: "resources", defaultSize: [2, 1], maxHeight: 8, families: ["island", "tablet", "ii"] },
    diskResourceWidget: { kind: "widget", variantGroup: "resources", defaultSize: [2, 1], maxHeight: 8, families: ["island", "tablet", "ii"] },
    gpuResourceWidget: { kind: "widget", variantGroup: "resources", defaultSize: [2, 1], maxHeight: 8, families: ["island", "tablet", "ii"] },

    // Sports: the score line and the scoreboard card, free-form from a two-wide row.
    // They read SportsService and nothing of their host, so the sidebar offers them
    // exactly as the island does.
    sportsWidget: { kind: "widget", variantGroup: "sports", defaultSize: [2, 1], allowedSizes: [[2, 1], [3, 1], [4, 1], [2, 2], [3, 2], [4, 2]], families: ["island", "ii"] },
    sportsCard: { kind: "widget", variantGroup: "sports", defaultSize: [2, 2], allowedSizes: [[2, 2], [3, 2], [4, 2]], families: ["island", "ii"] },

    // The photo widget: no chrome, the chosen image fills whatever footprint it is
    // given. Each tile keeps its own image, in the pages of the layout it lives in.
    photoWidget: { kind: "widget", defaultSize: [2, 2], maxHeight: 8, families: ["island", "ii"] },

    // The tablet shade's tray pill as a grid tile: a 1-row tile whatever the
    // width, since the pill is one line of text and every metric derives from the
    // row height. A click asks the host for the tray surface - a page on the
    // island, a dialog on the sidebar - so the tablet, which owns a tray row of
    // its own, does not offer it.
    trayWidget: { kind: "widget", defaultSize: [4, 1], allowedSizes: [[2, 1], [3, 1], [4, 1], [5, 1], [6, 1]], families: ["island", "ii"] },

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
    fullCalendarWidget: { kind: "fullDashboardWidget", variantGroup: "calendar", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet", "ii"] },
    // The same date, as the background desktop widgets draw it. Free-form: the tile
    // re-lays the design out from the surface it is given, so 1x1, the 2x wide row and
    // the taller footprints that repeat a 2x2 proportion all work without a size list.
    calendarMinimalWidget: { kind: "widget", variantGroup: "calendar", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    // The month's grid, at the ~2:1 proportion the desktop widget draws it at. Closed
    // size list, and horizontal only: the grid needs the height of six rows plus its
    // header, so there is no portrait form of it, and 1x1/2x2 are not it either. The
    // wider and taller entries are the same design with more room.
    calendarMonthGridWidget: { kind: "widget", variantGroup: "calendar", defaultSize: [4, 3], allowedSizes: [[3, 2], [4, 2], [5, 2], [6, 2], [4, 3], [5, 3], [6, 3], [5, 4], [6, 4]], families: ["island", "tablet", "ii"] },
    // The next three days with their events. Free-form like the minimal date: the list
    // drops rows from the bottom as the tile shrinks and shows one line at one row.
    calendarUpcomingWidget: { kind: "widget", variantGroup: "calendar", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    // The month as a card: a whole month in seven columns, with the grid handing two
    // fifths of the tile to the coming events once the tile is tall enough to have any.
    // Two cells each way is the floor, not one: a 96 x 56 tile leaves the days 12 px of
    // width and 7 px of height, which is not a month anyone reads.
    calendarMonthAgendaWidget: {
        kind: "widget",
        variantGroup: "calendar",
        defaultSize: [2, 2],
        minWidth: 2,
        minHeight: 2,
        maxHeight: 8,
        families: ["island", "tablet", "ii"]
    },
    fullTasksWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet", "ii"] },
    fullTimerWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet", "ii"] },
    fullCountdownWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet", "ii"] },
    fullPomodoroWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet", "ii"] },
    fullNotesWidget: { kind: "fullDashboardWidget", defaultSize: [2, 2], allowedSizes: [[2, 2], [2, 4], [4, 2]], families: ["island", "tablet", "ii"] },

    // Clock: several designs of one tile. They share a variant group, so the tray
    // offers them as a single entry the user cycles through before adding one; once on
    // the grid each is its own type and keeps its design.
    // Number clock widget (Google Sans Flex die-cut stencil design, freeform sizing, minimum 1x1)
    clockWidget: {
        kind: "widget",
        variantGroup: "clock",
        defaultSize: [2, 1],
        families: ["island", "tablet", "ii"]
    },

    // iOS Clock widget (Apple SF Pro Display design, adaptive vertical/horizontal, date above clock, minimum 1x1)
    iosClockWidget: {
        kind: "widget",
        variantGroup: "clock",
        defaultSize: [2, 2],
        families: ["island", "tablet", "ii"]
    },

    // Digital clock widget: the background widget's DigitalClock as-is, configured by
    // the clock_digital settings. Free-form sizing (minimum 1x1); the tile scales the
    // whole design into its footprint and stacks the lines when it is taller than wide.
    digitalClockWidget: {
        kind: "widget",
        variantGroup: "clock",
        defaultSize: [2, 2],
        families: ["island", "tablet", "ii"]
    },

    // Notifications as a list (minimum 4xY, freeform height): the sidebar's columns
    // give it the four it needs, and the tablet's shade keeps its own card.
    notificationListWidget: {
        kind: "widget",
        defaultSize: [4, 4],
        minWidth: 4,
        maxHeight: 8,
        families: ["island", "ii"]
    },

    // Weather: several designs of one tile. They share a variant group, so the tray
    // offers them as a single entry the user cycles through before adding one; once on
    // the grid each is its own type and keeps its design.
    weatherIconShape: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    weatherCard: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    weatherWidget: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    weatherCircle: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    weatherTypography: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },
    weatherForecast: { kind: "widget", variantGroup: "weather", defaultSize: [2, 2], maxHeight: 8, families: ["island", "tablet", "ii"] },

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
    phoneCamera: "connectivity", phoneMic: "connectivity", phoneMirror: "connectivity", speedTest: "connectivity",

    // Everything else that toggles - display, audio, tools and system - is one section:
    // split further, most sections held a single row.
};

function canonicalType(type) {
    if (type === "toolbar" || type === "dashboardToolbar")
        return "dashboardToolbar";
    if (type === "flexClock" || type === "horiClock")
        return "clockWidget";
    if (type === "iosClock" || type === "iosClockWidget" || type === "clockIos" || type === "clock_ios")
        return "iosClockWidget";
    if (type === "notificationListWidget" || type === "notificationWidget" || type === "notificationsWidget" || type === "notificationList" || type === "notificationsList")
        return "notificationListWidget";
    if (type === "media" || type === "media_widget")
        return "mediaWidget";
    if (type === "mediaCircle" || type === "media_circle" || type === "mediaCircleWidget" || type === "media_circle_widget" || type === "mediaShape" || type === "media_shape")
        return "mediaCircleWidget";
    if (type === "expressiveMedia" || type === "expressive_media" || type === "expressiveMediaWidget" || type === "expressive_media_widget")
        return "expressiveMediaWidget";
    if (type === "cdMedia" || type === "cd_media" || type === "cdMediaWidget" || type === "cd_media_widget")
        return "cdMediaWidget";
    if (type === "compactMedia" || type === "compact_media" || type === "compactMediaWidget" || type === "compact_media_widget")
        return "compactMediaWidget";
    if (type === "nothingRingMedia" || type === "nothing_ring_media" || type === "nothingMedia" || type === "nothingRingMediaWidget" || type === "nothing_ring_media_widget")
        return "nothingRingMediaWidget";
    if (type === "bluetoothBattery" || type === "bluetooth_battery" || type === "bluetoothBatteryWidget" || type === "bluetooth_battery_widget" || type === "batteryWidget" || type === "battery_widget")
        return "bluetoothBatteryWidget";
    if (type === "mobileBattery" || type === "mobile_battery" || type === "mobileBatteryWidget" || type === "mobile_battery_widget")
        return "mobileBatteryWidget";
    if (type === "bluetoothHeadphoneCookie" || type === "bluetooth_headphone_cookie" || type === "bluetoothHeadphoneCookieWidget" || type === "bluetooth_headphone_cookie_widget" || type === "headphoneCookieWidget")
        return "bluetoothHeadphoneCookieWidget";
    if (type === "pcBatteryBars" || type === "pc_battery_bars" || type === "pcBatteryBarsWidget" || type === "pc_battery_bars_widget" || type === "batteryBarsWidget")
        return "pcBatteryBarsWidget";
    if (type === "pcBatteryCable" || type === "pc_battery_cable" || type === "pcBatteryCableWidget" || type === "pc_battery_cable_widget" || type === "batteryCableWidget")
        return "pcBatteryCableWidget";
    if (type === "devicesBatteryList" || type === "devices_battery_list" || type === "devicesBatteryListWidget" || type === "devices_battery_list_widget" || type === "devicesBatteryList1x1Widget" || type === "devicesBatteryList1x1" || type === "devices_battery_list_1x1")
        return "devicesBatteryListWidget";
    if (type === "bluetoothEarbudsStem" || type === "bluetooth_earbuds_stem" || type === "bluetoothEarbudsStemWidget" || type === "bluetooth_earbuds_stem_widget" || type === "earbudsStemWidget")
        return "bluetoothEarbudsStemWidget";
    if (type === "laptopBattery" || type === "laptop_battery" || type === "laptopBatteryWidget" || type === "laptop_battery_widget" || type === "batteryGlowWidget" || type === "pcBatteryGlowWidget")
        return "laptopBatteryWidget";
    if (type === "systemResources" || type === "system_resources" || type === "systemResourcesWidget" || type === "system_resources_widget" || type === "resources" || type === "resourcesWidget")
        return "systemResourcesWidget";
    if (type === "cpu" || type === "cpuResource" || type === "cpu_resource" || type === "cpuWidget" || type === "cpu_widget")
        return "cpuResourceWidget";
    if (type === "ram" || type === "memory" || type === "ramResource" || type === "ram_resource" || type === "ramWidget" || type === "ram_widget")
        return "ramResourceWidget";
    if (type === "disk" || type === "storage" || type === "diskResource" || type === "disk_resource" || type === "diskWidget" || type === "disk_widget")
        return "diskResourceWidget";
    if (type === "gpu" || type === "gpuResource" || type === "gpu_resource" || type === "gpuWidget" || type === "gpu_widget")
        return "gpuResourceWidget";
    if (type === "battery")
        return "bluetoothBatteryWidget";
    if (type === "weather_card")
        return "weatherCard";
    if (type === "weatherIcon" || type === "weather_icon")
        return "weatherIconShape";
    if (type === "weatherWidget" || type === "weather_widget" || type === "weatherPill" || type === "weather_pill")
        return "weatherWidget";
    if (type === "weatherCircle" || type === "weather_circle" || type === "weatherCircleCookie" || type === "weather_circle_cookie")
        return "weatherCircle";
    if (type === "weatherTypography" || type === "weather_typography" || type === "weatherTyphograpy" || type === "weather_typhograpy")
        return "weatherTypography";
    if (type === "weatherForecast" || type === "weather_forecast" || type === "weatherForecast2x1" || type === "weather_forecast_2x1")
        return "weatherForecast";
    if (type === "weather")
        return "weatherCard";
    if (type === "calendar")
        return "fullCalendarWidget";
    if (type === "calendarMinimal" || type === "calendar_minimal" || type === "calendar_minimal_widget" || type === "desktopCalendarWidget")
        return "calendarMinimalWidget";
    if (type === "calendarMonthGrid" || type === "calendar_month_grid" || type === "calendarGrid" || type === "calendar_grid" || type === "calendarGridWidget")
        return "calendarMonthGridWidget";
    if (type === "calendarUpcoming" || type === "calendarUpcoming3Days" || type === "calendarUpcoming3DaysWidget"
            || type === "calendar_upcoming" || type === "calendar_upcoming_3days" || type === "calendar_upcoming_3_days")
        return "calendarUpcomingWidget";
    if (type === "calendarMonthAgenda" || type === "calendar_month_agenda" || type === "monthCard" || type === "month_card")
        return "calendarMonthAgendaWidget";
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

// ── Variant groups ──────────────────────────────────────────────────────────
// A variant group is several designs of the same tile (`variantGroup` on each type).
// The tray shows one entry per group with arrows to cycle its designs; the grid holds
// whichever the user added, as an ordinary type. Types without a group are a group of
// their own.

/** The group a type belongs to, or "" when it stands alone. */
function variantGroup(type) {
    var metadata = TOGGLE_TYPES[type];
    return (metadata && typeof metadata.variantGroup === "string") ? metadata.variantGroup : "";
}

/** Every type in a group, in catalog order; the first is the group's default design. */
function variantsOf(group) {
    if (!group)
        return [];
    return allTypes().filter(function(type) {
        return variantGroup(type) === group;
    });
}

/**
 * Whether the tray stands in for this type with a static preview instead of building
 * the real tile (see QuickToggleTrayPreview). Widget tiles are the expensive ones and
 * say nothing useful at tray size; toggles and sliders are cheap and are shown live.
 */
function usesTrayPreview(type) {
    var previewed = ["widget", "media", "dashboardWidget", "fullDashboardWidget"];
    return previewed.indexOf(kind(type)) !== -1;
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

/**
 * Whether a host offers this type in its tray. A type with no `families` is offered
 * everywhere; otherwise the list names every host that has it - so the island's widget
 * designs name the sidebar ("ii") beside the island and the tablet, while the island's
 * toolbar names only the island.
 */
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
    var minH = metadata && metadata.minHeight !== undefined ? metadata.minHeight : 1;
    var rawW = finiteInteger(width, fallback[0]);
    var normalizedWidth = Math.max(minW, rawW);
    var normalizedHeight = Math.max(minH, finiteInteger(height, fallback[1]));

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
    var minH = metadata && metadata.minHeight !== undefined ? metadata.minHeight : 1;
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
    return requestedWidth >= minW && requestedWidth <= positiveColumns(columns) && requestedHeight >= minH && requestedHeight <= (metadata.maxHeight || 8);
}

function item(type, id, width, height, columns, extraProps) {
    var resolvedType = canonicalType(type);
    var normalized = normalizeSize(resolvedType, width, height, columns);
    var stableId = typeof id === "string" && id.length > 0 ? id : resolvedType;
    var res = {
        id: stableId,
        type: resolvedType,
        sizeW: normalized[0],
        sizeH: normalized[1]
    };
    if (extraProps && typeof extraProps === "object") {
        for (var k in extraProps) {
            if (k !== "id" && k !== "type" && k !== "sizeW" && k !== "sizeH" && k !== "size" && k !== "layoutX" && k !== "layoutY" && k !== "pixelWidth") {
                res[k] = extraProps[k];
            }
        }
    }
    return res;
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
            var sourceSize = item(type, id, sourceWidth, source.sizeH, columns, source);
            page.push(sourceSize);
        }
        result.push(page);
    }

    return result.length > 0 ? result : [[]];
}
