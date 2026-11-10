pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import "../../modes/ModeSchema.js" as ModeSchema

/**
 * UI-independent adapter between the assistant and the Modes & Routines
 * engine.
 *
 * The model does not get the engine: it gets this bounded contract — a
 * vocabulary read (catalogue), compact reads (list/get/history), and one
 * validated write per call. Validation is strict on purpose:
 * `ModeSchema.normalize*` degrades unknown trigger and action types quietly
 * (an unknown watcher just never fires), which is fine for a hand-edited
 * config and terrible for an answer from a model. So every unknown here
 * comes back as an error the model can fix and retry, never as a silently
 * broken mode.
 *
 * `created` is the seam the Modes surfaces listen to: it says a definition
 * just came from a run, so the overlay can reveal it while the assistant
 * finishes its sentence.
 */
QtObject {
    id: root

    /// A definition was just written by an assistant call.
    signal created(string kind, string id, string name, string sessionId)

    // Palette keys mirror `ModeUi.paletteKeys`; the contract test pins the
    // two lists together. Kept literal here because a service must not
    // reach into a UI singleton.
    readonly property var paletteKeys: ["", "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink"]
    // A small shelf of symbols that read well at list size; any Material
    // Symbols name is accepted, these are the recommendations. Mirror of
    // IconPicker.shelf, pinned by the same contract test.
    readonly property var iconShelf: [
        "tune", "bedtime", "work", "center_focus_strong", "sports_esports", "theaters", "co_present", "spa",
        "school", "menu_book", "headphones", "music_note", "movie", "videocam", "mic", "podcasts",
        "fitness_center", "directions_run", "self_improvement", "coffee", "restaurant", "nightlight",
        "wb_sunny", "flight", "home", "apartment", "commute", "directions_car", "pets", "child_care",
        "code", "terminal", "science", "biotech", "psychology", "edit_note", "draw", "brush", "palette",
        "camera", "photo_camera", "savings", "shopping_cart", "celebration", "favorite", "star", "bolt",
        "do_not_disturb_on", "notifications_off", "battery_saver", "power", "speed", "eco", "lock",
        "visibility_off", "auto_awesome", "rocket_launch", "public", "schedule", "alarm", "timer"
    ]

    /**
     * Parameter lines per trigger type. The live `TRIGGER_TYPES` table
     * decides which types exist and are wired (CONDITION_SOURCES); this
     * only says what each one carries. A type with no line here still
     * appears in the catalogue, without parameters — never invented ones.
     */
    readonly property var triggerDocs: ({
        schedule: "from,to: 'HH:MM' or 'sunrise'/'sunset'; days: ISO weekdays 1=Mon..7=Sun (default all)",
        calendar: "match: substring of the event title ('' any event)",
        app: "classes: window classes (plain name or regex); title: title substring; when: 'focused' | 'running'",
        game: "when: 'focused' | 'running'",
        fullscreen: "no parameters",
        workspace: "names: workspace names or numbers; special: true = a special workspace",
        idle: "sec: seconds without input (min 5); ignoreInhibitors: bool",
        locked: "is: true = locked, false = unlocked",
        lid: "closed: true = lid shut, false = open",
        media: "playing: bool; player: player-name substring ('' any player)",
        deviceInUse: "what: 'mic' | 'camera' | 'screen'",
        discordVoice: "no parameters",
        pomodoro: "phase: 'focus' | 'break' | 'any'",
        battery: "below,above: 0-100; pluggedIn: bool (null = don't care)",
        resource: "metric: cpuUsage|cpuTemp|gpuUsage|gpuTemp|memory|swap|disk; above,below: number",
        keyboardLayout: "code: xkb layout code, e.g. 'us'",
        updates: "atLeast: how many pending updates count as true",
        wifi: "ssids: network names; connected: bool; ethernet: bool (null = don't care)",
        vpn: "kind: 'vpn' | 'tailscale'; connected: bool",
        bluetooth: "devices: MAC addresses; connected: bool",
        phone: "reachable: bool; batteryBelow: 1-100",
        monitors: "count: minimum connected; names: monitor names",
        audioDevice: "match: device name/description substring; kind: 'sink' (output) | 'source' (input)",
        weather: "kind: any|clear|cloudy|fog|rain|snow|storm; tempBelow,tempAbove: degrees",
        modeActive: "id: a mode id ('' = any mode is on); routines only",
        notification: "app: app name; text: body substring; routines with kind 'once' only",
        alarm: "routines with kind 'once' only",
        pomodoroLap: "lap: 'focusEnd' | 'breakEnd' | 'any'; routines with kind 'once' only",
        shortcut: "name: the shortcut name to bind; routines with kind 'once' only"
    })

    /** Value shapes per action type; same honesty rule as `triggerDocs`. */
    readonly property var actionDocs: ({
        dnd: "bool",
        autoDndFullscreen: "bool",
        nightLight: "bool",
        darkMode: "'dark' | 'light'",
        brightness: "0-100, or { level: 0-100, scope: 'focused' | 'all' }",
        screenShader: "shader name ('' = none); live names in this catalogue's screenShader line",
        keyboardBacklight: "integer brightness level",
        wallpaper: "absolute file path — only reuse paths from existing modes, never invent one",
        nightLightTemp: "kelvin, 1000-10000",
        oledSaver: "'all' | 'focused' (which monitors to blackout)",
        desktopWidgets: "no value; hides desktop widgets, restores them at the end",
        volume: "{ level: 0-100|null, muted: bool|null } — null leaves that part alone",
        micMute: "bool",
        systemSounds: "bool",
        media: "'pause' | 'play'",
        audioOutput: "{ name: pipewire node name, label: description } — only reuse pairs from existing modes",
        audioInput: "{ name, label } — same rule as audioOutput",
        appVolume: "{ app: app name, level: 0-100|null, muted: bool|null }",
        playerVolume: "0-100 on the active media player",
        mediaSkip: "'next' | 'previous'",
        monoAudio: "bool",
        easyEffects: "bool",
        earbudsAnc: "'normal' | 'transparency' | 'adaptive' | 'anc' (only while earbuds are connected)",
        playSound: "absolute audio file path",
        keepAwake: "bool",
        powerProfile: "'power-saver' | 'balanced' | 'performance'",
        lock: "no value",
        screensOff: "no value",
        suspend: "no value",
        pomodoro: "'start' | 'stop'",
        hyprland: "{ presets: ['animations','blur','shadows','gaps','rounding','tearing'], options: { 'section:option': value } }",
        gameMode: "bool",
        barDock: "{ bar: 'keep'|'autoHide'|'fixed', dock: 'keep'|'hide'|'show' }",
        workspace: "{ action: 'go'|'move', target: number|'+1'|'empty'|'special', back: bool }",
        keyboardLayout: "layout code, e.g. 'us'",
        touchGestures: "bool",
        launch: "{ app: 'desktop-file-id' } or { command: 'argv line' }, optional onEnd: 'keep'|'close'",
        closeApps: "['class', …] — graceful close, never a kill",
        workspaceProfile: "profile slug from the live choices in this catalogue's workspaceProfile line",
        openUrl: "https URL",
        wifi: "bool",
        bluetooth: "bool",
        vpn: "bool",
        tailscale: "bool",
        dnsOverTls: "bool",
        pingPhone: "{ kind: 'ping'|'ring', message: text }",
        wait: "seconds to pause the sequence (integer)",
        shell: "{ start: 'command run on apply', end: 'optional command on revert' }",
        notify: "{ title, body, icon } — routines only",
        mode: "{ action: 'start'|'stop', id: mode id } — routines only",
        routine: "{ action: 'run'|'stop', id: routine id } — routines only"
    })

    // ── Vocabulary ────────────────────────────────────────────────────────

    /** The whole grammar in one model-facing text; English, it is data. */
    function capabilities(): string {
        const lines = [];
        lines.push("A mode is an exclusive setting set: starting one reverts the previous, and ending a mode undoes what the user has not touched since. A routine is not exclusive; 'while' applies on true / reverts on false, 'once' fires on the false-to-true edge and never reverts.");
        lines.push("");
        lines.push("MODE: { name, icon, color, auto: bool, match: 'any'|'all', notify: bool, triggers: [...], actions: [...], end: { revert: bool, strict: bool, autoOffMin: int, notify: bool } }");
        lines.push("ROUTINE: { name, icon, color, kind: 'while'|'once', enabled: bool, match: 'any'|'all', cooldownSec: int, notify: bool, triggers: [...], actions: [...], end: { revert, strict, notify } }");
        lines.push("TRIGGER: { type, not: bool (invert), forSec: int (hold that long first), plus per-type fields below }");
        lines.push("ACTION: { type, value, revert: false to keep the effect after the end, delaySec: int to wait before it }");
        lines.push("color: one of " + JSON.stringify(root.paletteKeys) + " ('' = theme). icon: a Material Symbols name; recommended: " + JSON.stringify(root.iconShelf));
        lines.push("Actions run top to bottom; use 'wait' or delaySec to order them in time.");
        lines.push("");
        lines.push("TRIGGER TYPES (type — fields):");
        for (const type in ModeSchema.TRIGGER_TYPES) {
            if (!ModeSchema.CONDITION_SOURCES[type])
                continue;
            const meta = ModeSchema.TRIGGER_TYPES[type];
            const tags = [];
            if (meta.routineOnly === true)
                tags.push("routines only");
            if (meta.event === true)
                tags.push("moment, not a state: kind 'once' only");
            const tagText = tags.length ? " [" + tags.join(", ") + "]" : "";
            lines.push(`- ${type}${tagText}: ${root.triggerDocs[type] ?? "(no extra fields)"}`);
        }
        lines.push("");
        lines.push("ACTION TYPES (type — value), with live availability on this machine:");
        const registry = Modes.actions.registry;
        for (const type of Modes.actions.types()) {
            const entry = Modes.actions.get(type);
            if (!entry)
                continue;
            const state = Modes.actions.isAvailable(type) ? "" : " [not available on this machine — do not use]";
            const only = entry.routineOnly === true ? " [routines only]" : "";
            let choices = "";
            try {
                if (entry.choices)
                    choices = " | live choices: " + JSON.stringify(entry.choices().slice(0, 24));
            } catch (e) {
                // Choices that need a service mid-flight simply stay unlisted.
            }
            lines.push(`- ${type}${only}${state} (${entry.category}): ${root.actionDocs[type] ?? "see an existing mode"}${choices}`);
        }
        return lines.join("\n");
    }

    /** The per-turn instructions the Modes surface submits alongside the request. */
    function agentPrompt(): string {
        return [
            "You are the Modes & Routines assistant of this shell. The user asked from inside the Modes & Routines manager.",
            "Goal: turn the request into exactly one mode or one routine that matches what they asked, using the modes tools only.",
            "First call modes_catalogue and read it — the vocabulary is live and this machine's availability is part of it. Never invent a trigger or action type; unknown types are refused.",
            "Call modes_list when the request could overlap or reference an existing definition; reuse exact ids.",
            "A mode fits a state the user moves in and out of (work, sleep, gaming). A 'once' routine fits an event that should fire a moment later (a notification, a lap, a shortcut).",
            "Give it a short name, a fitting icon from the recommended shelf, and a color key that suits the mood. Use real values only: never invent file paths, SSIDs, MAC addresses, device names or desktop ids — pick an action that does not need one instead.",
            "When several requests arrive at once, still create one definition that covers them.",
            "Create it with modes_create (or modes_update when the user asked to change a named existing one). Do not start it — the user reviews it in the editor you opened.",
            "If the request is impossible with this vocabulary, do not force a broken definition: say plainly what cannot be done and what comes closest.",
            "When done, answer in two short sentences: what you created and one hint on where to tweak it. Say nothing you did not actually do."
        ].join("\n");
    }

    // ── Reads ─────────────────────────────────────────────────────────────

    function listBrief(): var {
        const out = [];
        for (const m of Modes.modes) {
            out.push({
                kind: "mode",
                id: m.id,
                name: m.name,
                icon: m.icon,
                color: m.color,
                auto: m.auto === true,
                active: Modes.activeModeId === m.id,
                triggers: (m.triggers ?? []).map(t => t.type),
                actions: (m.actions ?? []).map(a => a.type)
            });
        }
        for (const r of Modes.routines) {
            out.push({
                kind: "routine",
                id: r.id,
                name: r.name,
                icon: r.icon,
                color: r.color,
                routineKind: r.kind,
                enabled: r.enabled !== false,
                running: Modes.isRoutineRunning(r.id),
                triggers: (r.triggers ?? []).map(t => t.type),
                actions: (r.actions ?? []).map(a => a.type)
            });
        }
        return { count: out.length, definitions: out };
    }

    function definitionOf(kind, id) {
        const def = kind === "routine" ? Modes.routineById(id) : Modes.modeById(id);
        return def ? ModeSchema.clone(def) : null;
    }

    function historyBrief(limit) {
        const list = ModeSchema.toArray(Modes.history).slice(0, Math.max(1, Math.min(20, limit)));
        return list.map(entry => ({
            at: entry.t ?? 0,
            kind: entry.kind ?? "",
            id: entry.id ?? "",
            event: entry.event ?? "",
            why: entry.why ?? "",
            failed: ModeSchema.toArray(entry.failed)
        }));
    }

    // ── Validation ────────────────────────────────────────────────────────

    function isPlainObject(value): bool {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    /** Shared field checks for create and update. Returns an errors list. */
    function checkDefinition(kind, def): var {
        const errors = [];
        if (!root.isPlainObject(def))
            return ["definition must be an object"];
        const name = String(def.name ?? "").trim();
        if (name.length === 0 || name.length > 80)
            errors.push("name is required, up to 80 characters");

        const triggers = ModeSchema.toArray(def.triggers);
        const actions = ModeSchema.toArray(def.actions);
        if (triggers.length > 12)
            errors.push("at most 12 triggers");
        if (actions.length > 24)
            errors.push("at most 24 actions");

        const isRoutine = kind === "routine";
        const routineKind = isRoutine ? (def.kind === "once" ? "once" : "while") : "";
        for (const t of triggers) {
            const type = String(root.isPlainObject(t) ? t.type ?? "" : "");
            if (!type.length || !ModeSchema.TRIGGER_TYPES[type]) {
                errors.push(`unknown trigger type "${type || "(none)"}" — call modes_catalogue for the live list`);
                continue;
            }
            if (!ModeSchema.CONDITION_SOURCES[type])
                errors.push(`trigger type "${type}" has no watcher on this shell`);
            const meta = ModeSchema.TRIGGER_TYPES[type];
            if (meta.routineOnly === true && !isRoutine)
                errors.push(`trigger type "${type}" is only for routines`);
            if (meta.event === true && isRoutine && routineKind !== "once")
                errors.push(`trigger type "${type}" is a moment — a routine using it must have kind "once"`);
        }
        for (const a of actions) {
            const type = String(root.isPlainObject(a) ? a.type ?? "" : "");
            if (!type.length || !Modes.actions.get(type)) {
                errors.push(`unknown action type "${type || "(none)"}" — call modes_catalogue for the live list`);
                continue;
            }
            const entry = Modes.actions.get(type);
            if (entry.routineOnly === true && !isRoutine)
                errors.push(`action type "${type}" is only for routines`);
            // Availability is a property of this machine right now; a mode
            // built around an absent device reads as a bug to the user.
            if (!Modes.actions.isAvailable(type))
                errors.push(`action type "${type}" is not available on this machine`);
        }
        if (isRoutine && def.cooldownSec !== undefined && def.cooldownSec !== null) {
            const cool = Number(def.cooldownSec);
            if (!isFinite(cool) || cool < 0 || cool > 86400)
                errors.push("cooldownSec must be 0-86400 seconds");
        }
        if (!isRoutine && def.end !== undefined && root.isPlainObject(def.end)) {
            const offMin = Number(def.end.autoOffMin ?? 0);
            if (!isFinite(offMin) || offMin < 0 || offMin > 1440)
                errors.push("end.autoOffMin must be 0-1440 minutes");
        }
        // The engine's own guard: a routine that starts itself (directly or
        // through modes it triggers) is a fire drill, not an automation. The
        // candidate will live under its slugified name, so test against that.
        if (isRoutine) {
            const loop = Modes.routineLoop(ModeSchema.slugify(name), actions);
            if (loop && loop.length)
                errors.push(`actions would run this routine again (loop through: ${loop.join(", ")})`);
        }
        return errors;
    }

    // ── Writes ────────────────────────────────────────────────────────────

    function create(args, sessionId = ""): var {
        const kind = String(args?.kind ?? "") === "routine" ? "routine" : "mode";
        const def = args?.definition;
        const errors = root.checkDefinition(kind, def);
        if (errors.length)
            return { ok: false, errors: errors };
        const clean = ModeSchema.clone(def);
        // Ids are the engine's business; a model that guesses one must not
        // collide with a hand-made definition. name carries meaning, id follows.
        delete clean.id;
        delete clean.preset;
        clean.id = ModeSchema.slugify(String(clean.name ?? ""));
        if (kind === "routine")
            clean.template = "";
        const id = kind === "routine" ? Modes.addRoutine(clean) : Modes.addMode(clean);
        const stored = kind === "routine" ? Modes.routineById(id) : Modes.modeById(id);
        root.created(kind, id, String(stored?.name ?? clean.name ?? id), String(sessionId ?? ""));
        return { ok: true, kind: kind, id: id, name: String(stored?.name ?? id) };
    }

    function update(args, sessionId = ""): var {
        const kind = String(args?.kind ?? "") === "routine" ? "routine" : "mode";
        const id = String(args?.id ?? "").trim();
        const existing = kind === "routine" ? Modes.routineById(id) : Modes.modeById(id);
        if (!existing)
            return { ok: false, errors: [`no ${kind} with id "${id}" — call modes_list for the live ids`] };
        const def = args?.definition;
        const errors = root.checkDefinition(kind, def);
        if (errors.length)
            return { ok: false, errors: errors };
        const clean = ModeSchema.clone(def);
        clean.id = existing.id;
        // A rewritten definition is user content from here on, not a preset.
        clean.preset = false;
        if (kind === "routine") {
            clean.template = "";
            Modes.upsertRoutine(clean);
        } else {
            Modes.upsertMode(clean);
        }
        const stored = kind === "routine" ? Modes.routineById(id) : Modes.modeById(id);
        root.created(kind, id, String(stored?.name ?? id), String(sessionId ?? ""));
        return { ok: true, kind: kind, id: id, name: String(stored?.name ?? id), updated: true };
    }

    function start(args): var {
        const kind = String(args?.kind ?? "") === "routine" ? "routine" : "mode";
        const id = String(args?.id ?? "").trim();
        if (kind === "routine") {
            if (!Modes.routineById(id))
                return { ok: false, errors: [`no routine with id "${id}"`] };
            return Modes.runRoutine(id, "manual")
                ? { ok: true, kind: kind, id: id, started: true }
                : { ok: false, errors: ["the routine did not start (cooldown or guard)"] };
        }
        if (!Modes.modeById(id))
            return { ok: false, errors: [`no mode with id "${id}"`] };
        return Modes.activate(id, "manual")
            ? { ok: true, kind: kind, id: id, started: true }
            : { ok: false, errors: ["the mode did not start"] };
    }

    function stop(args): var {
        const kind = String(args?.kind ?? "") === "routine" ? "routine" : "mode";
        const id = String(args?.id ?? "").trim();
        if (kind === "routine") {
            if (!Modes.isRoutineRunning(id))
                return { ok: false, errors: [`routine "${id}" is not running`] };
            Modes.stopRoutine(id, "manual");
            return { ok: true, kind: kind, id: id, stopped: true };
        }
        if (id.length > 0 && Modes.activeModeId !== id)
            return { ok: false, errors: [`mode "${id}" is not the active mode`] };
        if (!Modes.active)
            return { ok: false, errors: ["no mode is active"] };
        Modes.deactivate("manual");
        return { ok: true, kind: kind, id: Modes.activeModeId || id, stopped: true };
    }

    function remove(args): var {
        const kind = String(args?.kind ?? "") === "routine" ? "routine" : "mode";
        const id = String(args?.id ?? "").trim();
        const existing = kind === "routine" ? Modes.routineById(id) : Modes.modeById(id);
        if (!existing)
            return { ok: false, errors: [`no ${kind} with id "${id}"`] };
        const name = String(existing.name ?? id);
        if (kind === "routine")
            Modes.removeRoutine(id);
        else
            Modes.removeMode(id);
        return { ok: true, kind: kind, id: id, name: name, removed: true };
    }
}
