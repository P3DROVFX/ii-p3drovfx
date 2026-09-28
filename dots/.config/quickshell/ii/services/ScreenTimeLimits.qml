pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

/**
 * Daily limits on focused screen time, the engine behind the usage overlay's Limits tab.
 *
 * Three kinds of rule, all read from `Config.options.screenTime`:
 *   - an app limit: one or more window classes sharing a daily budget;
 *   - the total limit: every focused minute of the day, except always-allowed apps;
 *   - a focus schedule: apps (or every app) blocked between two times of day.
 *
 * Time comes from AppStats. The day file holds focused seconds up to its last flush;
 * between flushes this counts the focused window itself, so a limit lands on the
 * minute rather than up to a flush interval late. A fresh day file replaces the live
 * count, which the file then already contains.
 *
 * When a rule is spent and one of its apps has a window, `activeBlock` names it and the
 * block screen (modules/ii/screenTimeOverlay) opens over it. Its choices come back here:
 * close the app, lock the screen, or take more time. What happened today — ignores,
 * extra time, warnings sent — lives in Persistent as one document reset at midnight.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.screenTime ?? null
    readonly property bool enabled: Config.ready && Persistent.ready && (root.opts?.enable ?? true)
    readonly property var limits: root.opts?.limits ?? []
    readonly property var schedules: root.opts?.schedules ?? []
    readonly property var alwaysAllowed: root.opts?.alwaysAllowed ?? []
    readonly property bool hasPin: (root.opts?.pinHash ?? "").length > 0
    readonly property int warnMinutes: root.opts?.warnMinutes ?? 5
    readonly property int autoCloseSeconds: root.opts?.autoCloseSeconds ?? 0
    readonly property bool hasRules: root.limits.some(l => l.enabled !== false) || root.schedules.some(s => s.enabled !== false)
    /// Counting and enforcing. The page asks for counting too while it is open, so the
    /// hero figure moves even before the first rule exists.
    readonly property bool active: root.enabled && (root.hasRules || root.watchers > 0)
    /// Open pages that want live figures (see `watch`).
    property int watchers: 0

    readonly property string today: AppStats.todayDate
    property real now: Date.now()
    /// Bumped whenever a figure may have changed; bindings read it to recompute.
    property int revision: 0

    // ── Focused time ────────────────────────────────────────────────────
    property var baseFocus: ({})
    property var liveFocus: ({})
    property var lastDoc: undefined
    property real lastTick: 0
    property string lastFocusedKey: ""
    readonly property string focusedKey: ToplevelManager.activeToplevel?.appId ?? ""
    /// The block screen covering the focused app stops its clock: time spent looking
    /// at the choices is not time spent in the app.
    readonly property bool counting: !GlobalStates.screenLocked && !AppStats.userIdle
        && !(root.activeBlock !== null && root.activeBlock.key === root.focusedKey)

    function watch(on: bool): void {
        root.watchers = Math.max(0, root.watchers + (on ? 1 : -1));
    }

    function rebase(): void {
        const doc = AppStats.history[root.today];
        if (doc === root.lastDoc)
            return;
        root.lastDoc = doc;
        const base = ({});
        const apps = doc?.apps ?? ({});
        const fi = AppStats.field.focus;
        for (const key in apps) {
            if (key === AppStats.systemKey)
                continue;
            let sum = 0;
            const hours = apps[key].h ?? ({});
            for (const hour in hours)
                sum += hours[hour][fi] ?? 0;
            if (sum > 0)
                base[key] = sum;
        }
        root.baseFocus = base;
        root.liveFocus = ({});
        root.revision++;
    }

    function focusedFor(key: string): real {
        return (root.baseFocus[key] ?? 0) + (root.liveFocus[key] ?? 0);
    }

    /// Focused seconds today for every app, live, biggest first: [{ key, seconds }].
    function todayApps() {
        void root.revision;
        const keys = Object.keys(root.baseFocus);
        for (const key in root.liveFocus)
            if (!keys.includes(key))
                keys.push(key);
        return keys.map(key => ({ key: key, seconds: root.focusedFor(key) }))
            .filter(e => e.seconds >= 1)
            .sort((a, b) => b.seconds - a.seconds);
    }

    function totalUsed(): real {
        void root.revision;
        let sum = 0;
        const seen = ({});
        for (const key in root.baseFocus) {
            seen[key] = true;
            if (!root.alwaysAllowed.includes(key))
                sum += root.focusedFor(key);
        }
        for (const key in root.liveFocus)
            if (!seen[key] && !root.alwaysAllowed.includes(key))
                sum += root.liveFocus[key];
        return sum;
    }

    /// Focused seconds counted toward the total limit on `date` (today is live).
    function focusForDate(date: string): real {
        if (date === root.today)
            return root.totalUsed();
        const apps = AppStats.history[date]?.apps;
        if (!apps)
            return 0;
        const fi = AppStats.field.focus;
        let sum = 0;
        for (const key in apps) {
            if (key === AppStats.systemKey || root.alwaysAllowed.includes(key))
                continue;
            const hours = apps[key].h ?? ({});
            for (const hour in hours)
                sum += hours[hour][fi] ?? 0;
        }
        return sum;
    }

    function usedFor(rule): real {
        void root.revision;
        if (!rule)
            return 0;
        if (rule.kind === "total")
            return root.totalUsed();
        let sum = 0;
        for (const key of rule.keys ?? [])
            sum += root.focusedFor(key);
        return sum;
    }

    function budgetFor(rule): real {
        void root.revision;
        if (!rule)
            return 0;
        return Math.max(0, (rule.minutes ?? 0) * 60 + (root.dayState.extra?.[rule.id] ?? 0));
    }

    function remainingFor(rule): real {
        return Math.max(0, root.budgetFor(rule) - root.usedFor(rule));
    }

    function appliesOn(rule, day: int): bool {
        const days = rule?.days ?? [];
        return rule?.enabled !== false && (days.length !== 7 || days[day] === true);
    }

    function appliesToday(rule): bool {
        return root.appliesOn(rule, new Date(root.now).getDay());
    }

    /// "off" (disabled or not today), "ok", "warn" (inside the warning window),
    /// "ignored" (spent, more time refused) or "reached".
    function stateFor(rule): string {
        void root.revision;
        if (!root.appliesToday(rule))
            return "off";
        const remaining = root.budgetFor(rule) - root.usedFor(rule);
        if (remaining > 0)
            return remaining <= root.warnMinutes * 60 ? "warn" : "ok";
        return root.isIgnored(rule.id) ? "ignored" : "reached";
    }

    /// The total limit that applies today, if any.
    function totalLimit() {
        void root.revision;
        return root.limits.find(l => l.kind === "total" && root.appliesToday(l)) ?? root.limits.find(l => l.kind === "total") ?? null;
    }

    // ── Schedules ───────────────────────────────────────────────────────
    function minutesOf(hhmm: string): int {
        const parts = String(hhmm ?? "0:0").split(":");
        return (parseInt(parts[0]) || 0) * 60 + (parseInt(parts[1]) || 0);
    }

    function scheduleActiveAt(s, at: real): bool {
        if (!s || s.enabled === false)
            return false;
        const d = new Date(at);
        const day = d.getDay();
        const mins = d.getHours() * 60 + d.getMinutes();
        const start = root.minutesOf(s.start);
        const end = root.minutesOf(s.end);
        const days = s.days ?? [];
        const on = dayIndex => days.length !== 7 || days[dayIndex] === true;
        if (start === end)
            return false;
        if (start < end)
            return on(day) && mins >= start && mins < end;
        return (on(day) && mins >= start) || (on((day + 6) % 7) && mins < end);
    }

    function scheduleActive(s): bool {
        void root.revision;
        return root.scheduleActiveAt(s, root.now);
    }

    /// Minutes until the schedule starts (not active) or ends (active), or -1.
    /// Only its own start and end times can flip it, so those are all that is tried.
    function scheduleMinutesAway(s): int {
        void root.revision;
        if (!s || s.enabled === false)
            return -1;
        const nowMin = Math.floor(root.now / 60000) * 60000;
        const activeNow = root.scheduleActiveAt(s, nowMin);
        const base = new Date(nowMin);
        const candidates = [];
        for (let d = 0; d <= 8; d++) {
            for (const m of [root.minutesOf(s.start), root.minutesOf(s.end)]) {
                const t = new Date(base.getFullYear(), base.getMonth(), base.getDate() + d, 0, m).getTime();
                if (t > nowMin)
                    candidates.push(t);
            }
        }
        candidates.sort((a, b) => a - b);
        for (const t of candidates) {
            if (root.scheduleActiveAt(s, t) !== activeNow)
                return Math.round((t - nowMin) / 60000);
        }
        return -1;
    }

    // ── Today's state ───────────────────────────────────────────────────
    property var dayState: root.blankDay()

    function blankDay() {
        return {
            ignored: ({}),
            extra: ({}),
            warned: ({}),
            reminded: ({}),
            paused: false,
            ignores: 0,
            blocks: 0,
            closes: 0
        };
    }

    function loadDay(): void {
        if (!Persistent.ready)
            return;
        const stored = Persistent.states.screenTime;
        if (stored.date !== root.today) {
            root.dayState = root.blankDay();
            root.saveDay();
            return;
        }
        try {
            root.dayState = Object.assign(root.blankDay(), JSON.parse(stored.dayJson || "{}"));
        } catch (e) {
            root.dayState = root.blankDay();
        }
        root.revision++;
    }

    function saveDay(): void {
        if (!Persistent.ready)
            return;
        Persistent.states.screenTime.date = root.today;
        Persistent.states.screenTime.dayJson = JSON.stringify(root.dayState);
    }

    /// Replace the document so bindings on `dayState` see the change, then persist it.
    function commitDay(mutate): void {
        const next = JSON.parse(JSON.stringify(root.dayState));
        mutate(next);
        root.dayState = next;
        root.revision++;
        root.saveDay();
    }

    function isIgnored(ruleId: string): bool {
        const until = root.dayState.ignored?.[ruleId];
        if (until === undefined)
            return false;
        return until < 0 || until > root.now;
    }

    readonly property bool paused: root.dayState.paused === true

    // ── PIN ─────────────────────────────────────────────────────────────
    property real editsUnlockedUntil: 0
    readonly property bool editsLocked: root.hasPin && (root.opts?.pinForEdits ?? false) && root.now >= root.editsUnlockedUntil

    function hashPin(pin: string): string {
        return Qt.md5("ii-screen-time:" + pin);
    }

    function checkPin(pin: string): bool {
        return !root.hasPin || root.hashPin(pin) === root.opts.pinHash;
    }

    function setPin(pin: string): void {
        Config.options.screenTime.pinHash = pin.length > 0 ? root.hashPin(pin) : "";
    }

    function unlockEdits(pin: string): bool {
        if (!root.checkPin(pin))
            return false;
        root.editsUnlockedUntil = Date.now() + 10 * 60 * 1000;
        root.now = Date.now();
        return true;
    }

    // ── Rules ───────────────────────────────────────────────────────────
    function newId(): string {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function copyList(list) {
        return Array.from(list ?? []).map(item => JSON.parse(JSON.stringify(item)));
    }

    /// An edited rule warns afresh only if it has time left again: renaming a spent
    /// limit must not announce it (and count it) a second time. Ignores stand.
    function forgetDayFor(rule, ruleId: string): void {
        if (rule && rule.kind !== undefined && root.usedFor(rule) >= root.budgetFor(Object.assign({}, rule, { id: ruleId })))
            return;
        root.commitDay(day => {
            delete day.warned[ruleId];
            delete day.reminded[ruleId];
        });
    }

    function saveLimit(limit): void {
        const list = root.copyList(root.limits);
        const next = Object.assign({ id: root.newId(), kind: "app", name: "", keys: [], minutes: 60,
            days: [true, true, true, true, true, true, true], enabled: true, strict: false }, limit);
        const index = list.findIndex(l => l.id === next.id);
        if (index >= 0)
            list[index] = next;
        else
            list.push(next);
        // Forget today's warnings first: writing the list re-evaluates at once, and
        // would otherwise announce the limit before the old flags were cleared.
        root.forgetDayFor(next, next.id);
        Config.options.screenTime.limits = list;
        root.evaluate();
    }

    function removeLimit(id: string): void {
        Config.options.screenTime.limits = root.copyList(root.limits).filter(l => l.id !== id);
        root.forgetDayFor(null, id);
        root.evaluate();
    }

    function setLimitEnabled(id: string, on: bool): void {
        const list = root.copyList(root.limits);
        const item = list.find(l => l.id === id);
        if (!item)
            return;
        item.enabled = on;
        Config.options.screenTime.limits = list;
        root.evaluate();
    }

    function saveSchedule(schedule): void {
        const list = root.copyList(root.schedules);
        const next = Object.assign({ id: root.newId(), name: "", start: "22:00", end: "07:00",
            days: [true, true, true, true, true, true, true], keys: [], allApps: false, enabled: true, strict: false }, schedule);
        const index = list.findIndex(s => s.id === next.id);
        if (index >= 0)
            list[index] = next;
        else
            list.push(next);
        root.forgetDayFor(null, "s:" + next.id);
        Config.options.screenTime.schedules = list;
        root.evaluate();
    }

    function removeSchedule(id: string): void {
        Config.options.screenTime.schedules = root.copyList(root.schedules).filter(s => s.id !== id);
        root.forgetDayFor(null, "s:" + id);
        root.evaluate();
    }

    function setScheduleEnabled(id: string, on: bool): void {
        const list = root.copyList(root.schedules);
        const item = list.find(s => s.id === id);
        if (!item)
            return;
        item.enabled = on;
        Config.options.screenTime.schedules = list;
        root.evaluate();
    }

    function setAlwaysAllowed(keys): void {
        Config.options.screenTime.alwaysAllowed = Array.from(keys ?? []);
        root.revision++;
        root.evaluate();
    }

    function setPaused(on: bool): void {
        root.commitDay(day => {
            day.paused = on;
        });
        root.evaluate();
    }

    // ── Names ───────────────────────────────────────────────────────────
    function ruleName(rule): string {
        if (!rule)
            return "";
        if (String(rule.name ?? "").length > 0)
            return rule.name;
        if (rule.kind === "total")
            return Translation.tr("Screen time");
        const keys = rule.keys ?? [];
        if (keys.length === 0)
            return Translation.tr("No apps");
        const first = AppStats.displayName(keys[0]);
        return keys.length === 1 ? first : Translation.tr("%1 +%2").arg(first).arg(String(keys.length - 1));
    }

    function formatMinutes(minutes: real): string {
        const m = Math.max(0, Math.round(minutes));
        const h = Math.floor(m / 60);
        const rest = m % 60;
        if (h === 0)
            return Translation.tr("%1 min").arg(String(rest));
        return rest === 0 ? Translation.tr("%1 h").arg(String(h)) : Translation.tr("%1 h %2 min").arg(String(h)).arg(String(rest));
    }

    /// Dense form for tiles: "1h 7m", "45m", "30s".
    function formatCompact(seconds: real): string {
        const s = Math.max(0, Math.round(seconds));
        if (s < 60)
            return s + "s";
        const m = Math.floor(s / 60);
        const h = Math.floor(m / 60);
        return h === 0 ? m + "m" : (m % 60 === 0 ? h + "h" : h + "h " + (m % 60) + "m");
    }

    function formatSeconds(seconds: real): string {
        const s = Math.max(0, Math.round(seconds));
        return s < 60 && s > 0 ? Translation.tr("%1 s").arg(String(s)) : root.formatMinutes(Math.floor(s / 60));
    }

    // ── Enforcement ─────────────────────────────────────────────────────
    /// What the block screen shows, or null: { ruleId, kind, key, rule }.
    property var activeBlock: null
    /// Classes just sent a close; they are left alone while they exit.
    property var closingKeys: ({})

    function openKeys() {
        const keys = [];
        for (const w of HyprlandData.windowList) {
            const cls = w?.class ?? "";
            if (cls.length > 0 && !keys.includes(cls))
                keys.push(cls);
        }
        return keys;
    }

    function notify(title: string, body: string, key: string): void {
        const icon = key.length > 0 ? (AppStats.iconFor(key) || "hourglass") : "hourglass";
        Quickshell.execDetached(["notify-send", title, body, "-a", Translation.tr("Screen time"), "-i", icon, "--urgency=normal"]);
    }

    function tick(): void {
        const t = Date.now();
        const dt = root.lastTick > 0 ? (t - root.lastTick) / 1000 : 0;
        root.lastTick = t;
        root.now = t;
        if (Persistent.ready && Persistent.states.screenTime.date !== root.today)
            root.loadDay();
        // Credit the window that had focus over the span that just ended, not the one
        // that has it now. A gap much longer than the timer is a suspend: nobody used it.
        const key = root.lastFocusedKey;
        if (dt > 0 && dt < 30 && root.counting && key.length > 0) {
            root.liveFocus[key] = (root.liveFocus[key] ?? 0) + dt;
        }
        root.lastFocusedKey = root.focusedKey;
        root.revision++;
        root.evaluate();
    }

    function evaluate(): void {
        if (!root.enabled || !root.hasRules || root.paused) {
            root.activeBlock = null;
            return;
        }
        const t = root.now;
        const day = new Date(t).getDay();
        const open = root.openKeys().filter(k => !((root.closingKeys[k] ?? 0) > t));
        const focused = root.focusedKey;
        const allowed = root.alwaysAllowed;
        const warnAt = root.warnMinutes * 60;
        const candidates = [];
        let changes = [];

        for (const limit of root.limits) {
            if (!root.appliesOn(limit, day))
                continue;
            const id = limit.id;
            const used = root.usedFor(limit);
            const remaining = root.budgetFor(limit) - used;
            const warned = root.dayState.warned?.[id] ?? ({});
            const name = root.ruleName(limit);
            const icon = limit.kind === "total" ? "" : (limit.keys?.[0] ?? "");

            if (remaining > 0) {
                if (warnAt > 0 && remaining <= warnAt && !warned.warn) {
                    root.notify(Translation.tr("%1 left on %2").arg(root.formatSeconds(remaining)).arg(name),
                        Translation.tr("Your daily limit is almost up."), icon);
                    changes.push(d => root.markWarned(d, id, "warn"));
                } else if ((root.opts?.warnLastMinute ?? true) && remaining <= 60 && !warned.last) {
                    root.notify(Translation.tr("1 minute left on %1").arg(name), Translation.tr("Save what you are doing."), icon);
                    changes.push(d => root.markWarned(d, id, "last"));
                }
                continue;
            }

            if (!warned.limit) {
                if (root.opts?.notifyOnLimit ?? true)
                    root.notify(Translation.tr("Time's up for %1").arg(name),
                        Translation.tr("You reached your daily limit of %1.").arg(root.formatMinutes(limit.minutes ?? 0)), icon);
                changes.push(d => {
                    root.markWarned(d, id, "limit");
                    d.blocks = (d.blocks ?? 0) + 1;
                });
            }

            if (root.isIgnored(id)) {
                root.remindOverdue(limit, used - root.budgetFor(limit), focused, changes);
                continue;
            }

            const keys = limit.kind === "total"
                ? open.filter(k => !allowed.includes(k))
                : open.filter(k => (limit.keys ?? []).includes(k));
            for (const k of keys)
                candidates.push({ ruleId: id, kind: limit.kind === "total" ? "total" : "limit", key: k, rule: limit });
        }

        for (const s of root.schedules) {
            if (!root.scheduleActiveAt(s, t))
                continue;
            const id = "s:" + s.id;
            if (root.isIgnored(id))
                continue;
            const keys = s.allApps
                ? open.filter(k => !allowed.includes(k))
                : open.filter(k => (s.keys ?? []).includes(k));
            for (const k of keys)
                candidates.push({ ruleId: id, kind: "schedule", key: k, rule: s });
        }

        if (changes.length > 0)
            root.commitDay(d => changes.forEach(apply => apply(d)));

        const pick = candidates.find(c => c.key === focused) ?? candidates[0] ?? null;
        const current = root.activeBlock;
        if (!pick) {
            root.activeBlock = null;
        } else if (!current || current.ruleId !== pick.ruleId || current.key !== pick.key) {
            // Hold on to what is on screen while it is still blocked, rather than
            // jumping to whichever app took focus behind the overlay.
            const stillBlocked = current && candidates.some(c => c.ruleId === current.ruleId && c.key === current.key);
            root.activeBlock = stillBlocked ? current : pick;
        } else {
            root.activeBlock = Object.assign({}, current, { rule: pick.rule });
        }
    }

    function markWarned(day, id: string, level: string): void {
        const entry = day.warned[id] ?? ({});
        entry[level] = true;
        day.warned[id] = entry;
    }

    function remindOverdue(limit, over: real, focused: string, changes): void {
        const every = (root.opts?.overdueReminderMinutes ?? 15) * 60000;
        if (every <= 0)
            return;
        const inUse = limit.kind === "total" ? focused.length > 0 && !root.alwaysAllowed.includes(focused) : (limit.keys ?? []).includes(focused);
        if (!inUse || !root.counting)
            return;
        const last = root.dayState.reminded?.[limit.id] ?? 0;
        if (last === 0) {
            // The clock starts at the ignore itself, not with a reminder right away.
            changes.push(d => {
                d.reminded[limit.id] = root.now;
            });
            return;
        }
        if (root.now - last < every)
            return;
        root.notify(Translation.tr("%1 over your limit").arg(root.formatSeconds(over)),
            Translation.tr("%1 is past its daily limit.").arg(root.ruleName(limit)), limit.kind === "total" ? "" : (limit.keys?.[0] ?? ""));
        changes.push(d => {
            d.reminded[limit.id] = root.now;
        });
    }

    // ── Choices from the block screen ───────────────────────────────────
    /// More time for the blocked rule: `minutes` > 0 extends today's budget (a
    /// schedule is lifted for that long), `minutes` < 0 ignores it for the rest of
    /// the day. Checks the PIN when the rule is strict.
    function grant(ruleId: string, minutes: int, pin: string): bool {
        const rule = root.ruleById(ruleId);
        if (rule?.strict && !root.checkPin(pin ?? ""))
            return false;
        const isSchedule = ruleId.startsWith("s:");
        root.commitDay(day => {
            day.ignores = (day.ignores ?? 0) + 1;
            if (minutes < 0) {
                day.ignored[ruleId] = -1;
                day.reminded[ruleId] = 0;
            } else if (isSchedule) {
                day.ignored[ruleId] = Date.now() + minutes * 60000;
            } else {
                // Extra time runs out like the budget did: the warnings go out again.
                const used = root.usedFor(rule);
                const budget = root.budgetFor(rule);
                day.extra[ruleId] = Math.ceil((day.extra[ruleId] ?? 0) + Math.max(0, used - budget) + minutes * 60);
                const warned = day.warned[ruleId] ?? ({});
                warned.limit = false;
                warned.last = minutes <= 1;
                warned.warn = minutes * 60 <= root.warnMinutes * 60;
                day.warned[ruleId] = warned;
                delete day.ignored[ruleId];
            }
        });
        if (minutes < 0 && (root.opts?.notifyOnLimit ?? true))
            root.notify(Translation.tr("Limit ignored for today"),
                Translation.tr("%1 stays open. You'll be reminded while you use it.").arg(root.ruleName(rule)), "");
        root.activeBlock = null;
        root.evaluate();
        return true;
    }

    function closeApp(key: string): void {
        const pids = [];
        for (const w of HyprlandData.windowList) {
            if (w?.class === key && w.pid > 0 && !pids.includes(w.pid))
                pids.push(w.pid);
        }
        if (pids.length > 0)
            Quickshell.execDetached(["kill", "-TERM"].concat(pids.map(p => String(p))));
        const closing = Object.assign({}, root.closingKeys);
        closing[key] = Date.now() + 6000;
        root.closingKeys = closing;
        root.commitDay(day => {
            day.closes = (day.closes ?? 0) + 1;
        });
        root.activeBlock = null;
        root.evaluate();
        closingRecheck.restart();
    }

    function lockScreen(): void {
        root.activeBlock = null;
        Session.lock();
    }

    function ruleById(ruleId: string) {
        if (ruleId.startsWith("s:"))
            return root.schedules.find(s => "s:" + s.id === ruleId) ?? null;
        return root.limits.find(l => l.id === ruleId) ?? null;
    }

    // ── Wiring ──────────────────────────────────────────────────────────
    Timer {
        id: ticker
        interval: 3000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.tick()
        onRunningChanged: if (!running) root.lastTick = 0
    }

    // An app that ignored its close request comes back to the block screen.
    Timer {
        id: closingRecheck
        interval: 6500
        onTriggered: root.evaluate()
    }

    Connections {
        target: AppStats
        function onHistoryChanged() {
            root.rebase();
        }
        function onTodayDateChanged() {
            root.rebase();
            root.loadDay();
        }
    }

    Connections {
        target: HyprlandData
        enabled: root.active
        function onWindowListChanged() {
            root.evaluate();
        }
    }

    // Switching window is when a blocked app most often shows up; answering it at once
    // beats waiting out the timer.
    onFocusedKeyChanged: if (root.active) root.tick()
    onHasRulesChanged: root.evaluate()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.loadDay();
        }
    }

    Component.onCompleted: {
        root.loadDay();
        root.rebase();
    }

    IpcHandler {
        target: "screenTime"

        function status(): string {
            return JSON.stringify({
                paused: root.paused,
                total: Math.round(root.totalUsed()),
                limits: root.limits.map(l => ({ id: l.id, name: root.ruleName(l), state: root.stateFor(l), used: Math.round(root.usedFor(l)), budget: root.budgetFor(l) })),
                block: root.activeBlock ? { ruleId: root.activeBlock.ruleId, key: root.activeBlock.key } : null
            });
        }

        function pauseToday(): string {
            if (root.hasPin)
                return "PIN set: pause from the Limits tab";
            root.setPaused(true);
            return "paused";
        }

        function resume(): void {
            root.setPaused(false);
        }

        /// Drops today's extra time, ignores, warnings and counters. Only ever makes
        /// the limits stricter, so it needs no PIN.
        function resetToday(): void {
            root.dayState = root.blankDay();
            root.saveDay();
            root.revision++;
            root.evaluate();
        }
    }
}
