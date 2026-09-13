pragma Singleton
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import "../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Presentation helpers shared by every Modes surface: the overlay, the bar
 * pill, the lock pill, the flash banner and the sidebar dialog.
 *
 * A mode's `color` is a palette key, not a literal colour: the hue is fixed
 * per key and the lightness follows the theme, so "blue" stays blue across
 * wallpapers while the pill it paints still reads as part of the shell.
 * The empty key is the theme's own primary.
 */
Singleton {
    id: root

    readonly property var paletteKeys: ["", "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"]
    readonly property var paletteHues: ({
        red: 4,
        orange: 28,
        yellow: 52,
        green: 135,
        teal: 178,
        blue: 218,
        purple: 272,
        pink: 330
    })

    function hasHue(key) {
        return root.paletteHues[key] !== undefined;
    }

    function paletteLabel(key) {
        switch (key) {
        case "":
            return Translation.tr("Theme");
        case "red":
            return Translation.tr("Red");
        case "orange":
            return Translation.tr("Orange");
        case "yellow":
            return Translation.tr("Yellow");
        case "green":
            return Translation.tr("Green");
        case "teal":
            return Translation.tr("Teal");
        case "blue":
            return Translation.tr("Blue");
        case "purple":
            return Translation.tr("Purple");
        case "pink":
            return Translation.tr("Pink");
        }
        return key;
    }

    // Soft fill for pills and list icons.
    function container(key) {
        if (!root.hasHue(key))
            return Appearance.colors.colPrimaryContainer;
        return ColorUtils.categoryContainer(root.paletteHues[key], Appearance.colors.colPrimaryContainer, 0.42);
    }

    function onContainer(key) {
        if (!root.hasHue(key))
            return Appearance.colors.colOnPrimaryContainer;
        return ColorUtils.categoryOnColor(root.container(key), root.paletteHues[key]);
    }

    // Strong fill for the active row and the Start button.
    function accent(key) {
        if (!root.hasHue(key))
            return Appearance.colors.colPrimary;
        return ColorUtils.categoryContainer(root.paletteHues[key], Appearance.colors.colPrimary, 0.55);
    }

    function onAccent(key) {
        if (!root.hasHue(key))
            return Appearance.colors.colOnPrimary;
        return ColorUtils.categoryOnColor(root.accent(key), root.paletteHues[key]);
    }

    // A swatch for the colour picker: saturated enough to tell apart.
    function swatch(key) {
        if (!root.hasHue(key))
            return Appearance.colors.colPrimary;
        return ColorUtils.categoryContainer(root.paletteHues[key], Appearance.colors.colPrimary, 0.7);
    }

    // ---------------------------------------------------------------- text

    function clock(epochMs) {
        if (!epochMs || epochMs <= 0)
            return "";
        return new Date(epochMs).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    readonly property var dayShort: [
        Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"),
        Translation.tr("Fri"), Translation.tr("Sat"), Translation.tr("Sun")
    ]

    function daysText(days) {
        const list = ModeSchema.toArray(days).map(Number).sort((a, b) => a - b);
        const key = list.join(",");
        if (list.length === 7 || list.length === 0)
            return "";
        if (key === "1,2,3,4,5")
            return Translation.tr("Weekdays");
        if (key === "6,7")
            return Translation.tr("Weekends");
        return list.map(d => root.dayShort[d - 1] ?? d).join(" ");
    }

    function triggerTypeLabel(type) {
        const label = ModeSchema.TRIGGER_TYPES[type]?.label;
        return label ? Translation.tr(label) : type;
    }

    function triggerTypeIcon(type) {
        return ModeSchema.TRIGGER_TYPES[type]?.icon ?? "bolt";
    }

    function listText(items, max = 2) {
        const list = ModeSchema.stringList(items);
        if (!list.length)
            return "";
        if (list.length <= max)
            return list.join(", ");
        return Translation.tr("%1 +%2").arg(list.slice(0, max).join(", ")).arg(list.length - max);
    }

    // One line that says what a trigger waits for.
    function triggerText(t) {
        if (!t)
            return "";
        const plain = root.plainTriggerText(t);
        const text = t.not ? Translation.tr("Not: %1").arg(plain) : plain;
        const dwell = ModeSchema.durationSec(t.forSec);
        return dwell > 0 ? Translation.tr("%1 · for %2").arg(text).arg(root.durationText(dwell)) : text;
    }

    // "30 s", "5 min", "1 h 30 min".
    function durationText(sec) {
        const s = Math.max(0, Math.round(Number(sec) || 0));
        if (s === 0)
            return Translation.tr("0 s");
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const r = s % 60;
        const parts = [];
        if (h > 0)
            parts.push(Translation.tr("%1 h").arg(h));
        if (m > 0)
            parts.push(Translation.tr("%1 min").arg(m));
        if (r > 0 || parts.length === 0)
            parts.push(Translation.tr("%1 s").arg(r));
        return parts.join(" ");
    }

    // "After 5 min" for a delayed action, "" otherwise (wait steps say it
    // through their value instead).
    function actionDelayText(a) {
        if (!a || a.type === "wait")
            return "";
        const d = ModeSchema.durationSec(a.delaySec);
        return d > 0 ? Translation.tr("After %1").arg(root.durationText(d)) : "";
    }

    function plainTriggerText(t) {
        switch (t.type) {
        case "schedule": {
            const days = root.daysText(t.days);
            return `${t.from} – ${t.to}` + (days.length ? ` · ${days}` : "");
        }
        case "app": {
            const apps = root.listText(t.classes);
            const title = String(t.title ?? "").trim();
            const what = apps.length
                ? (title.length ? `${apps} "${title}"` : apps)
                : (title.length ? Translation.tr("Window titled \"%1\"").arg(title) : "");
            if (!what.length)
                return t.when === "focused" ? Translation.tr("Any app focused") : Translation.tr("Any app running");
            return t.when === "focused"
                ? Translation.tr("%1 focused").arg(what)
                : Translation.tr("%1 running").arg(what);
        }
        case "game":
            return t.when === "focused" ? Translation.tr("A game is focused") : Translation.tr("A game is running");
        case "battery": {
            const parts = [];
            if (t.below !== null && t.below !== undefined)
                parts.push(Translation.tr("Battery below %1 %").arg(t.below));
            if (t.above !== null && t.above !== undefined)
                parts.push(Translation.tr("Battery above %1 %").arg(t.above));
            if (t.pluggedIn === true)
                parts.push(Translation.tr("Plugged in"));
            else if (t.pluggedIn === false)
                parts.push(Translation.tr("On battery"));
            return parts.length ? parts.join(" · ") : Translation.tr("Battery (any)");
        }
        case "wifi": {
            const ssids = root.listText(t.ssids);
            let text = t.connected === false ? Translation.tr("Wi-Fi disconnected") : (ssids.length
                ? Translation.tr("On Wi-Fi %1").arg(ssids) : Translation.tr("Wi-Fi connected"));
            if (t.ethernet === true)
                text += " · " + Translation.tr("Ethernet");
            else if (t.ethernet === false)
                text += " · " + Translation.tr("No ethernet");
            return text;
        }
        case "bluetooth": {
            const devs = root.listText(t.devices.map(a => root.bluetoothName(a)));
            if (t.connected === false)
                return devs.length ? Translation.tr("%1 disconnected").arg(devs) : Translation.tr("No Bluetooth device");
            return devs.length ? Translation.tr("%1 connected").arg(devs) : Translation.tr("A Bluetooth device connected");
        }
        case "monitors": {
            const names = root.listText(t.names);
            if (names.length)
                return Translation.tr("Monitor %1 connected").arg(names);
            return Translation.tr("%1+ monitors").arg(t.count);
        }
        case "fullscreen":
            return Translation.tr("Fullscreen window");
        case "locked":
            return t.is === false ? Translation.tr("Screen unlocked") : Translation.tr("Screen locked");
        case "modeActive":
            return t.id ? Translation.tr("Mode %1 is on").arg(Modes.modeById(t.id)?.name ?? t.id)
                        : Translation.tr("Any mode is on");
        case "audioDevice":
            return (t.kind === "source" ? Translation.tr("Input %1") : Translation.tr("Output %1"))
                .arg(t.match || Translation.tr("(any)"));
        case "idle":
            return Translation.tr("No input for %1").arg(root.durationText(t.sec));
        case "workspace": {
            if (t.special === true)
                return Translation.tr("A special workspace is open");
            const names = root.listText(t.names);
            return names.length ? Translation.tr("On workspace %1").arg(names) : Translation.tr("Workspace (none chosen)");
        }
        case "media": {
            const who = String(t.player ?? "").trim();
            if (t.playing === false)
                return who.length ? Translation.tr("%1 is not playing").arg(who) : Translation.tr("Nothing is playing");
            return who.length ? Translation.tr("%1 is playing").arg(who) : Translation.tr("Media is playing");
        }
        case "deviceInUse":
            return t.what === "camera" ? Translation.tr("Camera in use")
                : (t.what === "screen" ? Translation.tr("Screen being captured") : Translation.tr("Microphone in use"));
        case "discordVoice":
            return Translation.tr("In a Discord voice call");
        case "phone": {
            if (t.reachable === false)
                return Translation.tr("Phone out of reach");
            return t.batteryBelow !== null && t.batteryBelow !== undefined
                ? Translation.tr("Phone nearby, battery below %1 %").arg(t.batteryBelow)
                : Translation.tr("Phone nearby");
        }
        case "pomodoro":
            return t.phase === "focus" ? Translation.tr("Pomodoro focus lap")
                : (t.phase === "break" ? Translation.tr("Pomodoro break") : Translation.tr("Pomodoro running"));
        case "calendar": {
            const m = String(t.match ?? "").trim();
            return m.length ? Translation.tr("During an event \"%1\"").arg(m) : Translation.tr("During a calendar event");
        }
        case "resource": {
            const metric = root.resourceMetricLabel(t.metric);
            const unit = String(t.metric).endsWith("Temp") ? "°C" : "%";
            if (t.above !== null && t.above !== undefined)
                return Translation.tr("%1 above %2 %3").arg(metric).arg(t.above).arg(unit);
            if (t.below !== null && t.below !== undefined)
                return Translation.tr("%1 below %2 %3").arg(metric).arg(t.below).arg(unit);
            return metric;
        }
        case "vpn": {
            const what = t.kind === "tailscale" ? Translation.tr("Tailscale") : Translation.tr("VPN");
            return t.connected === false ? Translation.tr("%1 down").arg(what) : Translation.tr("%1 up").arg(what);
        }
        case "lid":
            return t.closed === false ? Translation.tr("Lid open") : Translation.tr("Lid closed");
        case "weather": {
            const parts = [];
            if (t.kind && t.kind !== "any")
                parts.push(root.weatherKindLabel(t.kind));
            if (t.tempBelow !== null && t.tempBelow !== undefined)
                parts.push(Translation.tr("colder than %1°").arg(t.tempBelow));
            if (t.tempAbove !== null && t.tempAbove !== undefined)
                parts.push(Translation.tr("warmer than %1°").arg(t.tempAbove));
            return parts.length ? parts.join(" · ") : Translation.tr("Any weather");
        }
        case "keyboardLayout":
            return t.code ? Translation.tr("Keyboard layout %1").arg(String(t.code).toUpperCase())
                : Translation.tr("Keyboard layout (none chosen)");
        case "updates":
            return Translation.tr("%1+ updates pending").arg(t.atLeast);
        case "notification": {
            const app = String(t.app ?? "").trim();
            const text = String(t.text ?? "").trim();
            let out = app.length ? Translation.tr("Notification from %1").arg(app) : Translation.tr("Any notification");
            if (text.length)
                out += " · " + Translation.tr("containing \"%1\"").arg(text);
            return out;
        }
        case "alarm":
            return Translation.tr("An alarm rings");
        case "pomodoroLap":
            return t.lap === "focusEnd" ? Translation.tr("A Pomodoro focus lap ends")
                : (t.lap === "breakEnd" ? Translation.tr("A Pomodoro break ends") : Translation.tr("A Pomodoro lap ends"));
        case "shortcut": {
            const name = String(t.name ?? "").trim();
            return name.length ? Translation.tr("Shortcut quickshell:modes-%1").arg(name)
                : Translation.tr("The routine's shortcut is pressed");
        }
        }
        return root.triggerTypeLabel(t.type);
    }

    function resourceMetricLabel(metric) {
        switch (metric) {
        case "cpuUsage":
            return Translation.tr("CPU load");
        case "cpuTemp":
            return Translation.tr("CPU temperature");
        case "gpuUsage":
            return Translation.tr("GPU load");
        case "gpuTemp":
            return Translation.tr("GPU temperature");
        case "memory":
            return Translation.tr("Memory used");
        case "swap":
            return Translation.tr("Swap used");
        case "disk":
            return Translation.tr("Disk used");
        }
        return String(metric ?? "");
    }

    function weatherKindLabel(kind) {
        switch (kind) {
        case "clear":
            return Translation.tr("Clear");
        case "cloudy":
            return Translation.tr("Cloudy");
        case "fog":
            return Translation.tr("Fog");
        case "rain":
            return Translation.tr("Rain");
        case "snow":
            return Translation.tr("Snow");
        case "storm":
            return Translation.tr("Storm");
        }
        return Translation.tr("Any weather");
    }

    function triggerGroupLabel(type) {
        const key = ModeSchema.TRIGGER_TYPES[type]?.group ?? "";
        const label = ModeSchema.TRIGGER_GROUPS[key] ?? "";
        return label.length ? Translation.tr(label) : "";
    }

    function bluetoothName(address) {
        const dev = Array.from(BluetoothStatus.connectedDevices ?? [])
            .concat(Array.from(BluetoothStatus.pairedButNotConnectedDevices ?? []))
            .find(d => String(d.address).toUpperCase() === String(address).toUpperCase());
        return dev?.name ?? address;
    }

    // The list row's second line: what starts the mode, or that it is running.
    function modeStatus(m) {
        if (!m)
            return "";
        if (Modes.activeModeId === m.id) {
            if (Modes.activeEndsAt > 0)
                return Translation.tr("On · ends %1").arg(root.clock(Modes.activeEndsAt));
            return Translation.tr("On · since %1").arg(root.clock(Modes.activeSince));
        }
        if (!m.triggers.length)
            return Translation.tr("Manual");
        const first = root.triggerText(m.triggers[0]);
        if (m.triggers.length === 1)
            return first;
        return Translation.tr("%1 +%2").arg(first).arg(m.triggers.length - 1);
    }

    // The editor header's second line.
    function modeHeaderStatus(m) {
        if (!m)
            return "";
        if (Modes.activeModeId === m.id) {
            const since = root.clock(Modes.activeSince);
            const by = Modes.sourceText(Modes.activeSource);
            const base = Translation.tr("Started %1 · %2").arg(by).arg(since);
            if (Modes.activeEndsAt > 0)
                return base + " · " + Translation.tr("ends %1").arg(root.clock(Modes.activeEndsAt));
            return base;
        }
        if (Modes.isSuppressed(m.id))
            return Translation.tr("Off · waiting for its conditions to reset");
        if (m.auto && m.triggers.length)
            return Translation.tr("Off · starts automatically");
        return Translation.tr("Off");
    }

    function routineKindText(kind) {
        return kind === "once" ? Translation.tr("When conditions become true") : Translation.tr("While conditions hold");
    }

    // The newest history line about a routine, or null.
    function lastRoutineEvent(id) {
        return Modes.history.find(h => h.kind === "routine" && h.id === id) ?? null;
    }

    // The routine list row's second line.
    function routineStatus(r) {
        if (!r)
            return "";
        const run = Modes.routineRun(r.id);
        if (run)
            return Translation.tr("Running · since %1").arg(root.clock(run.since));
        const last = root.lastRoutineEvent(r.id);
        if (last)
            return Translation.tr("Last %1 · %2").arg(root.historyEventText(last).toLowerCase()).arg(root.whenText(last.t));
        if (!r.triggers.length)
            return Translation.tr("Manual");
        const first = root.triggerText(r.triggers[0]);
        return r.triggers.length === 1 ? first : Translation.tr("%1 +%2").arg(first).arg(r.triggers.length - 1);
    }

    function routineHeaderStatus(r) {
        if (!r)
            return "";
        const run = Modes.routineRun(r.id);
        if (run)
            return Translation.tr("Running · started %1 · %2").arg(Modes.sourceText(run.source)).arg(root.clock(run.since));
        if (!r.enabled)
            return r.triggers.length ? Translation.tr("Off · runs by hand only") : Translation.tr("Manual");
        if (Modes.isRoutineSuppressed(r.id))
            return Translation.tr("Stopped · waits for its conditions to reset");
        if (!r.triggers.length)
            return Translation.tr("Manual · no conditions");
        return r.kind === "once" ? Translation.tr("Armed · fires when its conditions become true")
            : Translation.tr("Armed · runs while its conditions hold");
    }

    function templateDescription(key) {
        switch (key) {
        case "battery-saver":
            return Translation.tr("Power-saver profile and dimmer screen under 20 % on battery; put back when charging");
        case "focus-headphones":
            return Translation.tr("Starts the Focus mode when the output switches to headphones");
        case "pause-on-lock":
            return Translation.tr("Pauses whatever is playing the moment the screen locks");
        case "mute-after-call":
            return Translation.tr("Mutes the microphone once the last Zoom window is gone");
        case "performance-gaming":
            return Translation.tr("Performance power profile for as long as a game is running");
        }
        return "";
    }

    // ---------------------------------------------------------------- history

    function historyEventText(h) {
        switch (h?.event) {
        case "start":
            return Translation.tr("Started");
        case "end":
            return Translation.tr("Ended");
        case "run":
            return Translation.tr("Ran");
        }
        return root.capitalize(h?.event ?? "");
    }

    // Why it happened: the start source or the end reason, in words.
    function historyWhyText(h) {
        if (!h)
            return "";
        if (h.event === "end")
            return Modes.reasonText(h.why);
        return root.capitalize(Modes.sourceText(h.why));
    }

    function historyName(h) {
        if (!h)
            return "";
        const def = h.kind === "routine" ? Modes.routineById(h.id) : Modes.modeById(h.id);
        return def?.name ?? h.id;
    }

    function historyDef(h) {
        if (!h)
            return null;
        return h.kind === "routine" ? Modes.routineById(h.id) : Modes.modeById(h.id);
    }

    function startOfDay(epochMs) {
        const d = new Date(epochMs);
        d.setHours(0, 0, 0, 0);
        return d.getTime();
    }

    // "Today", "Yesterday", else a short date.
    function dayLabel(epochMs) {
        const day = root.startOfDay(epochMs);
        const today = root.startOfDay(Date.now());
        if (day === today)
            return Translation.tr("Today");
        if (day === today - 86400000)
            return Translation.tr("Yesterday");
        return new Date(epochMs).toLocaleDateString(Qt.locale(), Locale.LongFormat);
    }

    // A time for today, a day and time for anything older.
    function whenText(epochMs) {
        if (!epochMs)
            return "";
        if (root.startOfDay(epochMs) === root.startOfDay(Date.now()))
            return root.clock(epochMs);
        return Translation.tr("%1 %2").arg(root.dayLabel(epochMs)).arg(root.clock(epochMs));
    }

    // What a freshly added action row starts with: the sensible "do the
    // thing" value, never an empty one that would fail on apply.
    function defaultActionValue(type) {
        const entry = Modes.actions.get(type);
        switch (entry?.editor) {
        case "switch":
            return true;
        case "segmented":
            return (entry.choices?.() ?? [])[0] ?? "";
        case "dropdown":
            return (entry.choices?.() ?? [""])[0] ?? "";
        case "brightness":
            return { level: 50, scope: "all" };
        case "volume":
            return { level: 40, muted: null };
        case "stepper":
            return 1;
        case "hyprland":
            return { presets: ["animations"], options: {} };
        case "barDock":
            return { bar: "keep", dock: "keep" };
        case "launch":
            return { app: "", command: "", onEnd: "keep", class: "" };
        case "shell":
            return { start: "", end: "" };
        case "notify":
            return { title: Translation.tr("Routine ran"), body: "", icon: "" };
        case "mode":
            return { action: "start", id: Modes.modes[0]?.id ?? "" };
        case "routine":
            return { action: "run", id: "" };
        case "wait":
            return 60;
        case "audioDevice":
            return { name: "", label: "" };
        case "appVolume":
            return { app: "", level: 40, muted: null };
        case "level":
            return 50;
        case "temperature":
            return Config.options.light.night.colorTemperature || 4000;
        case "workspace":
            return { action: "go", target: "1", back: false };
        case "phone":
            return { kind: "ping", message: "" };
        case "none":
            return null;
        }
        return type === "closeApps" ? [] : "";
    }

    // The label of one of an action's choices (segmented / dropdown editors).
    function choiceLabel(entry, value) {
        if (entry?.choiceLabel)
            return Translation.tr(entry.choiceLabel(value));
        return root.capitalize(value);
    }

    // What a row without parameters does, in the place of its value.
    function noValueText(type) {
        switch (type) {
        case "desktopWidgets":
            return Translation.tr("Hidden while it's on, back afterwards");
        case "lock":
            return Translation.tr("Locks the session");
        case "screensOff":
            return Translation.tr("Turns every screen off; any key wakes them");
        case "suspend":
            return Translation.tr("Suspends at once — put a Wait step above it");
        }
        return "";
    }

    function actionLabel(type) {
        return Modes.actions.get(type)?.label ?? type;
    }

    function actionIcon(type) {
        return Modes.actions.get(type)?.icon ?? "bolt";
    }

    function onOff(v) {
        return v ? Translation.tr("On") : Translation.tr("Off");
    }

    function capitalize(s) {
        const t = String(s ?? "");
        return t.length ? t[0].toUpperCase() + t.slice(1) : t;
    }

    // "workspace 3", "the next workspace", "the special workspace"…
    function workspaceLabel(target) {
        const t = String(target ?? "").trim();
        if (!t.length)
            return Translation.tr("no workspace");
        if (/^\d+$/.test(t))
            return Translation.tr("workspace %1").arg(t);
        if (t === "+1" || t === "r+1" || t === "e+1" || t === "m+1")
            return Translation.tr("the next workspace");
        if (t === "-1" || t === "r-1" || t === "e-1" || t === "m-1")
            return Translation.tr("the previous workspace");
        if (t === "empty")
            return Translation.tr("an empty workspace");
        if (t === "special")
            return Translation.tr("the special workspace");
        if (t.startsWith("special:"))
            return Translation.tr("special workspace %1").arg(t.slice(8));
        if (t.startsWith("name:"))
            return Translation.tr("workspace %1").arg(t.slice(5));
        return t;
    }

    // ---------------------------------------------------------------- forms

    // Where a condition's parameter form lives ("" when it has none). Forms
    // are plain files under forms/, picked by the editor key in TRIGGER_TYPES.
    function triggerFormUrl(type) {
        const editor = ModeSchema.TRIGGER_TYPES[type]?.editor ?? "none";
        return editor === "none" ? "" : Qt.resolvedUrl(`forms/Trigger${root.capitalize(editor)}.qml`);
    }

    // Same for an action's editor key; inline editors have no form.
    function actionFormUrl(editor) {
        if (!editor || editor === "none" || root.inlineActionEditors.indexOf(editor) !== -1)
            return "";
        return Qt.resolvedUrl(`forms/Action${root.capitalize(editor)}.qml`);
    }

    // Editors drawn right on the action row instead of in a form.
    readonly property var inlineActionEditors: ["switch", "segmented", "dropdown", "stepper", "text", "wait"]

    // Open windows as chip suggestions: class as the value, title as the label.
    function windowSuggestions() {
        const seen = {};
        const out = [];
        for (const w of ModeSchema.toArray(HyprlandData.windowList)) {
            const cls = String(w.initialClass || w["class"] || "");
            if (!cls.length || seen[cls])
                continue;
            seen[cls] = true;
            out.push({ label: String(w.title || cls).slice(0, 40), value: cls });
        }
        return out;
    }

    function hyprlandPresetLabel(key) {
        switch (key) {
        case "animations":
            return Translation.tr("Animations");
        case "blur":
            return Translation.tr("Blur");
        case "shadows":
            return Translation.tr("Shadows");
        case "gaps":
            return Translation.tr("Gaps");
        case "rounding":
            return Translation.tr("Rounding");
        case "tearing":
            return Translation.tr("Tearing");
        }
        return key;
    }

    // The value column of an action row.
    function actionValueText(a) {
        if (!a)
            return "";
        const v = a.value;
        const entry = Modes.actions.get(a.type);
        const obj = (v && typeof v === "object" && !Array.isArray(v)) ? v : null;
        switch (entry?.editor) {
        case "none":
            return root.noValueText(a.type);
        case "switch":
            return root.onOff(!!v);
        case "segmented":
            return root.choiceLabel(entry, v ?? "");
        case "dropdown":
            return v === "" || v === null || v === undefined ? Translation.tr("None") : root.choiceLabel(entry, v);
        case "brightness": {
            const level = obj ? obj.level : v;
            const scope = obj?.scope === "all" ? Translation.tr("all monitors") : Translation.tr("focused");
            return level === null || level === undefined ? "" : `${level} % · ${scope}`;
        }
        case "volume": {
            const parts = [];
            if (obj?.level !== null && obj?.level !== undefined)
                parts.push(`${obj.level} %`);
            else if (typeof v === "number")
                parts.push(`${v} %`);
            if (obj?.muted === true)
                parts.push(Translation.tr("muted"));
            else if (obj?.muted === false)
                parts.push(Translation.tr("unmuted"));
            return parts.join(" · ");
        }
        case "stepper":
            return String(v ?? 0);
        case "file":
            return String(v ?? "").split("/").pop();
        case "text":
            return String(v ?? "");
        case "classes":
            return root.listText(Array.isArray(v) || ModeSchema.isArrayLike(v) ? v : obj?.classes);
        case "hyprland": {
            const presets = ModeSchema.stringList(obj?.presets);
            const keys = Object.keys(obj?.options ?? {});
            const parts = presets.map(p => root.capitalize(p));
            if (keys.length)
                parts.push(Translation.tr("%1 option(s)").arg(keys.length));
            return parts.join(", ");
        }
        case "barDock": {
            const parts = [];
            const bar = obj?.bar ?? "keep";
            const dock = obj?.dock ?? "keep";
            if (bar === "autoHide")
                parts.push(Translation.tr("Bar auto-hides"));
            else if (bar === "fixed")
                parts.push(Translation.tr("Bar fixed"));
            if (dock === "hide")
                parts.push(Translation.tr("Dock hidden"));
            else if (dock === "show")
                parts.push(Translation.tr("Dock shown"));
            return parts.length ? parts.join(" · ") : Translation.tr("No change");
        }
        case "launch": {
            const target = obj?.app ? (DesktopEntries.byId(obj.app)?.name ?? obj.app) : (obj?.command ?? "");
            return target + (obj?.onEnd === "close" ? " · " + Translation.tr("close on end") : "");
        }
        case "shell":
            return String(obj?.start ?? v ?? "");
        case "notify": {
            const title = String(obj?.title ?? v ?? "");
            return obj?.body ? `${title} · ${obj.body}` : title;
        }
        case "mode": {
            const name = Modes.modeById(obj?.id)?.name ?? obj?.id ?? "";
            return (obj?.action === "stop" ? Translation.tr("Stop %1") : Translation.tr("Start %1")).arg(name);
        }
        case "routine": {
            const name = Modes.routineById(obj?.id)?.name ?? obj?.id ?? "";
            return (obj?.action === "stop" ? Translation.tr("Stop %1") : Translation.tr("Run %1")).arg(name);
        }
        case "wait":
            return Translation.tr("Wait %1, then go on").arg(root.durationText(ModeSchema.durationSec(v)));
        case "audioDevice":
            return String(obj?.label ?? obj?.name ?? v ?? "");
        case "appVolume": {
            const parts = [String(obj?.app ?? "")];
            if (obj?.level !== null && obj?.level !== undefined)
                parts.push(`${obj.level} %`);
            if (obj?.muted === true)
                parts.push(Translation.tr("muted"));
            else if (obj?.muted === false)
                parts.push(Translation.tr("unmuted"));
            return parts.filter(p => p.length).join(" · ");
        }
        case "level":
            return v === null || v === undefined ? "" : `${v} %`;
        case "temperature":
            return v === null || v === undefined ? "" : `${v} K`;
        case "workspace": {
            const target = String(obj?.target ?? "");
            const label = root.workspaceLabel(target);
            if (obj?.action === "move")
                return Translation.tr("Move the window to %1").arg(label);
            return obj?.back ? Translation.tr("Go to %1, back at the end").arg(label) : Translation.tr("Go to %1").arg(label);
        }
        case "phone":
            return obj?.kind === "ring" ? Translation.tr("Ring it")
                : (obj?.message ? Translation.tr("Ping: %1").arg(obj.message) : Translation.tr("Ping"));
        case "sound":
            return String(v ?? "").split("/").pop();
        }
        return v === null || v === undefined ? "" : String(v);
    }
}
