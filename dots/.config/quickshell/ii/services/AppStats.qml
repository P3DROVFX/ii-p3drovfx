pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Per-app usage and energy history: screen time, watt-hours, CPU and GPU time,
 * memory, launches and sessions.
 *
 * Runs the `app_stats` sampler and reads back what it writes. The daemon owns every
 * measurement — /proc, DRM fdinfo, RAPL and Hyprland's event socket — and knows only
 * window classes and pids. Names and icons are resolved here instead, where the
 * desktop-entry index already lives; that split is what keeps the daemon at ~3.5 MB.
 *
 * Two views of the same data, deliberately separate:
 *   - `lastSample` is live, one object per sample interval straight off stdout.
 *   - `history` is durable, one parsed file per local day, read back from disk.
 *
 * Screen state flows the other way: the daemon cannot see the lock screen or the
 * idle timer, so foreground time only stops accruing because this tells it to.
 */
Singleton {
    id: root

    /// The device rather than any one app. Holds the energy attributed to nothing —
    /// idle draw, kernel threads, backlight, radios — reported alongside the apps
    /// rather than spread over them, and screen time counted once however many
    /// windows were on screen for it.
    readonly property string systemKey: "__system"
    /// Layout of a stored hour tuple. Must match `store.rs`; a file written by a
    /// newer sampler is skipped rather than misread.
    readonly property int schema: 1
    readonly property var field: ({
            fg: 0,
            bg: 1,
            focus: 2,
            cpu: 3,
            gpu: 4,
            ramAvg: 5,
            ramPeak: 6,
            mjFg: 7,
            mjBg: 8,
            launches: 9,
            sessions: 10
        })

    readonly property var opts: Config.options?.appStats ?? null
    // IdleMonitor creates its native ext-idle-notify object from onPostReload.
    // Keep the whole service disabled until the async config load has completed,
    // otherwise it can ask Wayland for a notification while the seat is not ready.
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? true)
    readonly property bool trackHeadless: root.opts?.trackHeadless ?? true
    readonly property bool showHeadless: root.opts?.showHeadless ?? false
    readonly property int intervalMs: root.opts?.sampleIntervalMs ?? 10000
    readonly property int flushMs: root.opts?.flushIntervalMs ?? 60000
    readonly property int retentionDays: root.opts?.retentionDays ?? 31
    readonly property string retentionMode: root.opts?.retentionMode ?? "previousMonth"
    readonly property string energySource: root.opts?.energySource ?? "auto"
    readonly property int gpuFullEvery: root.opts?.gpuFullEvery ?? 30
    readonly property bool weekStartsMonday: root.opts?.weekStartsMonday ?? true
    /// Seconds of no input before foreground time is paused. 0 disables the monitor.
    readonly property int idleTimeout: root.opts?.idleTimeoutSec ?? 300

    readonly property string stateDir: Directories.appStats
    readonly property string binaryPath: `${Directories.scriptPath}/appStats/app_stats`
    /// The sampler is built rather than shipped, so a fresh config has the QML and no
    /// daemon. Assumed present until the probe says otherwise — the overlay would
    /// otherwise flash its install screen on every start.
    property bool binaryPresent: true
    /// Whether the install probe has answered yet. The sampler waits for it so a
    /// config without a daemon never execs a path that isn't there, while the overlay
    /// keeps reading `binaryPresent` and so still doesn't flash its install screen.
    property bool probed: false
    /// 1 readable, 0 present but root-only, 2 no intel-rapl on this machine.
    property int raplState: 1
    /// True once the sampler has announced itself, not merely once it was spawned.
    property bool running: false
    /// Energy source actually in use: "rapl", "battery" or "none".
    property string source: ""
    property var lastSample: null

    /// "YYYY-MM-DD" -> parsed day document, or null for a day with no data. The null
    /// matters: it is what stops a missing day from being requested forever.
    property var history: ({})
    /// Dates currently being read, one FileView each. Assigned as a whole batch —
    /// the Instantiator rebuilds every delegate when this changes, so it must not be
    /// trimmed as individual days arrive.
    property var loadBatch: []
    property bool restarting: false

    readonly property string todayDate: root.dateKey(clock.date)

    function pad(n) {
        return n < 10 ? `0${n}` : `${n}`;
    }

    function dateKey(d) {
        return `${d.getFullYear()}-${root.pad(d.getMonth() + 1)}-${root.pad(d.getDate())}`;
    }

    /// The last `days` local dates, oldest first, ending today.
    function recentDates(days) {
        const base = clock.date;
        const out = [];
        for (let i = days - 1; i >= 0; i--) {
            out.push(root.dateKey(new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)));
        }
        return out;
    }

    /**
     * Calendar periods, the unit the overlay navigates in.
     *
     * `granularity` is "day", "week" or "month" and `offset` counts backwards from
     * the current one: 0 is today / this week / this month, -1 the one before it.
     * Weeks and months are real calendar periods rather than a rolling window, so
     * that "the previous one" is the same seven days or the same month however long
     * ago it is asked about — which is what makes two periods comparable at all.
     */
    function periodStart(granularity, offset) {
        const base = clock.date;
        if (granularity === "week") {
            const dayOfWeek = base.getDay();
            const back = root.weekStartsMonday ? (dayOfWeek + 6) % 7 : dayOfWeek;
            return new Date(base.getFullYear(), base.getMonth(), base.getDate() - back + offset * 7);
        }
        if (granularity === "month") return new Date(base.getFullYear(), base.getMonth() + offset, 1);
        return new Date(base.getFullYear(), base.getMonth(), base.getDate() + offset);
    }

    function periodLength(granularity, start) {
        if (granularity === "week") return 7;
        if (granularity === "month") return new Date(start.getFullYear(), start.getMonth() + 1, 0).getDate();
        return 1;
    }

    /// The dates of a period, oldest first. Never runs past today: the month in
    /// progress ends where the data does rather than trailing empty columns for
    /// days that have not happened.
    function periodDates(granularity, offset) {
        const start = root.periodStart(granularity, offset);
        const length = root.periodLength(granularity, start);
        const out = [];
        for (let i = 0; i < length; i++) {
            const key = root.dateKey(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
            if (key > root.todayDate) break;
            out.push(key);
        }
        return out;
    }

    /// Oldest date still on disk, mirroring the daemon's own cutoff so navigation
    /// stops where the files do instead of walking into a run of empty periods.
    function oldestDate() {
        const base = clock.date;
        const days = Math.max(1, root.retentionDays);
        const byDays = root.dateKey(new Date(base.getFullYear(), base.getMonth(), base.getDate() - days));
        if (root.retentionMode !== "previousMonth") return byDays;
        const firstOfPrevious = root.dateKey(new Date(base.getFullYear(), base.getMonth() - 1, 1));
        return byDays < firstOfPrevious ? byDays : firstOfPrevious;
    }

    /// Whether stepping one period further back would land on anything retention
    /// still holds.
    function hasEarlierPeriod(granularity, offset) {
        const dates = root.periodDates(granularity, offset - 1);
        if (dates.length === 0) return false;
        return dates[dates.length - 1] >= root.oldestDate();
    }

    /// "Today", "Last week", "August 2026" — what the period is called. The two
    /// most recent of each get a name rather than a date, since that is how they
    /// are asked for; anything older is spelled out.
    function periodLabel(granularity, offset) {
        const start = root.periodStart(granularity, offset);
        if (granularity === "day") {
            if (offset === 0) return Translation.tr("Today");
            if (offset === -1) return Translation.tr("Yesterday");
            return start.toLocaleDateString(Qt.locale(), "ddd d MMM");
        }
        if (granularity === "week") {
            if (offset === 0) return Translation.tr("This week");
            if (offset === -1) return Translation.tr("Last week");
            return Translation.tr("Week of %1").arg(start.toLocaleDateString(Qt.locale(), "d MMM"));
        }
        return start.toLocaleDateString(Qt.locale(), "MMMM yyyy");
    }

    /// The dates a period actually covers, for the line under its name. A named
    /// period says nothing about where it sits, and the current one is shorter than
    /// it looks — half of today is not in it yet.
    function periodRangeLabel(granularity, offset) {
        const dates = root.periodDates(granularity, offset);
        if (dates.length === 0) return "";
        const start = root.periodStart(granularity, offset);
        if (granularity === "day") return start.toLocaleDateString(Qt.locale(), "d MMMM yyyy");

        const last = dates[dates.length - 1].split("-");
        const end = new Date(parseInt(last[0]), parseInt(last[1]) - 1, parseInt(last[2]));
        const sameMonth = start.getMonth() === end.getMonth();
        const from = sameMonth ? `${start.getDate()}` : start.toLocaleDateString(Qt.locale(), "d MMM");
        return `${from} – ${end.toLocaleDateString(Qt.locale(), "d MMM")}`;
    }

    function parseDoc(text) {
        if (!text || text.length === 0) return null;
        try {
            const doc = JSON.parse(text);
            if (doc.v !== root.schema) {
                console.warn(`[AppStats] day file has schema ${doc.v}, expected ${root.schema}`);
                return null;
            }
            return doc;
        } catch (e) {
            console.warn("[AppStats] malformed day file:", e);
            return null;
        }
    }

    function storeDay(date, doc) {
        const next = Object.assign({}, root.history);
        next[date] = doc;
        root.history = next;
    }

    /// Request whichever of `dates` is not cached yet. Today is excluded: it belongs
    /// to the watched view, which the sampler keeps current on its own.
    function ensureDates(dates) {
        const wanted = [];
        for (const date of dates) {
            if (date === root.todayDate) continue;
            if (root.history[date] !== undefined) continue;
            if (wanted.includes(date)) continue;
            wanted.push(date);
        }
        if (wanted.length === 0) return;
        // Days still in flight stay in the batch; dropping one cancels its read.
        for (const date of root.loadBatch) {
            if (root.history[date] === undefined && !wanted.includes(date)) wanted.push(date);
        }
        if (wanted.length === root.loadBatch.length && wanted.every(d => root.loadBatch.includes(d))) return;
        root.loadBatch = wanted;
    }

    /// Ask the sampler to write the day file now, so the overlay opens on data that
    /// is seconds old rather than up to `flushMs` old.
    function refresh() {
        if (sampler.running) {
            sampler.write(`${JSON.stringify({
                t: "flush"
            })}\n`);
            // On a cold shell the day file did not exist when the view was set up, and
            // FileView cannot watch a path that is not there — nothing would tell us the
            // flush landed, and the overlay would sit empty until the retry came round.
            reloadTimer.restart();
            return;
        }
        todayView.reload();
    }

    /// Days on disk and the bytes they take, or -1 until asked for. Measured with a
    /// shell rather than a FolderListModel: the settings page wants a size as well
    /// as a count, and nothing else in the shell needs either.
    property int storedDays: -1
    property real storedBytes: -1

    function measureStorage() {
        storageProcess.running = false;
        storageProcess.running = true;
    }

    /// Delete every day file, keeping whatever the sampler has in memory — the next
    /// flush writes today's again. Nothing here asks for confirmation; the caller does.
    function clearHistory() {
        Quickshell.execDetached(["sh", "-c", `rm -f -- "${root.stateDir}"/*.json`]);
        root.history = ({});
        root.loadBatch = [];
        clearTimer.restart();
    }

    function openStateDir() {
        Quickshell.execDetached(["xdg-open", root.stateDir]);
    }

    /// What the install screen is answering: is there a binary to run, and can this
    /// user read the energy counters. Both are one-shot filesystem tests, run at
    /// startup and again whenever the overlay opens, so building the daemon while the
    /// shell is up is picked up without a reload.
    function checkInstall() {
        installProbe.running = false;
        installProbe.running = true;
    }

    function pushState() {
        if (!sampler.running) return;
        sampler.write(`${JSON.stringify({
            t: "state",
            locked: GlobalStates.screenLocked,
            idle: idleMonitor.enabled && idleMonitor.isIdle
        })}\n`);
    }

    /// Sampler flags are read once at startup, so a settings change has to relaunch it.
    function restart() {
        root.restarting = true;
        restartTimer.restart();
    }

    function handleLine(line) {
        if (!line || line.length === 0) return;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.warn("[AppStats] unparseable line:", line);
            return;
        }

        switch (msg.t) {
        case "ready":
            root.source = msg.src ?? "";
            root.running = true;
            root.pushState();
            break;
        case "sample":
            root.lastSample = msg;
            break;
        case "flush":
            todayView.reload();
            break;
        }
    }

    function blankRecord(key, exe, headless) {
        return {
            key: key,
            exe: exe ?? "",
            headless: headless ?? false,
            fg: 0,
            bg: 0,
            focus: 0,
            cpu: 0,
            gpu: 0,
            ramAvg: 0,
            ramPeak: 0,
            mjFg: 0,
            mjBg: 0,
            launches: 0,
            sessions: 0,
            hourCount: 0
        };
    }

    function addTuple(rec, t) {
        const f = root.field;
        rec.fg += t[f.fg] ?? 0;
        rec.bg += t[f.bg] ?? 0;
        rec.focus += t[f.focus] ?? 0;
        rec.cpu += t[f.cpu] ?? 0;
        rec.gpu += t[f.gpu] ?? 0;
        rec.mjFg += t[f.mjFg] ?? 0;
        rec.mjBg += t[f.mjBg] ?? 0;
        rec.launches += t[f.launches] ?? 0;
        rec.sessions += t[f.sessions] ?? 0;
        rec.ramPeak = Math.max(rec.ramPeak, t[f.ramPeak] ?? 0);
        // Each stored hour already holds a mean; averaging those means weights every
        // hour equally, so a partial hour counts as much as a full one. Close enough
        // for a memory figure, and far cheaper than keeping per-sample counts on disk.
        const avg = t[f.ramAvg] ?? 0;
        if (avg > 0) {
            rec.ramAvg += avg;
            rec.hourCount += 1;
        }
    }

    /**
     * Sum stored hours into one record per app across `dates`.
     *
     * `opts`: `{ headless: bool, hourFrom: int, hourTo: int }` — `headless` defaults
     * to the `showHeadless` setting, the hour bounds to the whole day.
     *
     * Returns `{ apps, system, totals }`, apps sorted by foreground time descending.
     * The unattributed remainder is kept out of `apps` and returned as `system`;
     * it is not an application and would otherwise top every chart.
     */
    function summarize(dates, opts) {
        const o = opts ?? {};
        const from = o.hourFrom ?? 0;
        const to = o.hourTo ?? 23;
        const wantHeadless = o.headless ?? root.showHeadless;

        const byKey = ({});
        const system = root.blankRecord(root.systemKey, root.systemKey, true);

        for (const date of dates) {
            const apps = root.history[date]?.apps;
            if (!apps) continue;
            for (const key in apps) {
                const rec = apps[key];
                let target = system;
                if (key !== root.systemKey) {
                    if (!byKey[key]) byKey[key] = root.blankRecord(key, rec.exe, rec.headless);
                    target = byKey[key];
                }
                for (const hour in rec.h) {
                    const h = parseInt(hour);
                    if (h < from || h > to) continue;
                    root.addTuple(target, rec.h[hour]);
                }
            }
        }

        const totals = root.blankRecord("", "", false);
        const list = [];
        for (const key in byKey) {
            const rec = byKey[key];
            rec.ramAvg = rec.hourCount > 0 ? Math.round(rec.ramAvg / rec.hourCount) : 0;
            rec.wh = root.wh(rec.mjFg + rec.mjBg);
            if (rec.headless && !wantHeadless) {
                // Hiding services hides their rows, not the power they drew. Their
                // energy joins the unattributed remainder so the total stays equal
                // to what the package meter actually measured, and equal to the sum
                // of the rows on screen.
                system.mjFg += rec.mjFg;
                system.mjBg += rec.mjBg;
                continue;
            }
            list.push(rec);
            root.addTotals(totals, rec);
        }
        system.ramAvg = 0;
        system.wh = root.wh(system.mjFg + system.mjBg);

        list.sort((a, b) => b.fg - a.fg || b.bg - a.bg);
        return {
            apps: list,
            system: system,
            totals: totals
        };
    }

    function addTotals(totals, rec) {
        totals.fg += rec.fg;
        totals.bg += rec.bg;
        totals.focus += rec.focus;
        totals.cpu += rec.cpu;
        totals.gpu += rec.gpu;
        totals.mjFg += rec.mjFg;
        totals.mjBg += rec.mjBg;
        totals.launches += rec.launches;
        totals.sessions += rec.sessions;
        totals.ramPeak = Math.max(totals.ramPeak, rec.ramPeak);
        totals.wh = root.wh(totals.mjFg + totals.mjBg);
    }

    /// Whether an app key contributes to a series asked for `key`. A null `key` sums
    /// the apps and leaves out the unattributed remainder; naming `systemKey` asks
    /// for that row alone, which is how screen time is read without counting two
    /// windows visible at once twice.
    function inSeries(appKey, rec, key) {
        if (key) return appKey === key;
        if (appKey === root.systemKey) return false;
        return !rec.headless || root.showHeadless;
    }

    /**
     * One field per hour of day (24 entries) for a single date, read off the device
     * row rather than summed over the apps — two windows on screen at once are two
     * apps' worth of foreground time but still only one hour of screen time.
     *
     * Hours the sampler recorded before it counted device time hold nothing there,
     * and fall back to the app sum. That overstates any such hour that had two
     * windows up, but a hole in the middle of the day would be worse. The fallback
     * is decided per hour and not per day, so one hour of real device time cannot
     * blank out the rest of the day around it.
     */
    function deviceHours(date, fieldName) {
        const idx = root.field[fieldName];
        const device = new Array(24).fill(0);
        const fallback = new Array(24).fill(0);
        const apps = root.history[date]?.apps;
        if (!apps) return device;

        for (const appKey in apps) {
            const rec = apps[appKey];
            const isSystem = appKey === root.systemKey;
            if (!isSystem && rec.headless && !root.showHeadless) continue;
            const target = isSystem ? device : fallback;
            for (const hour in rec.h) target[parseInt(hour)] += rec.h[hour][idx] ?? 0;
        }
        return device.map((value, hour) => value > 0 ? value : fallback[hour]);
    }

    /// One field summed per hour of day (24 entries) across `dates`.
    function hourlySeries(dates, fieldName, key) {
        const idx = root.field[fieldName];
        const out = new Array(24).fill(0);
        for (const date of dates) {
            const apps = root.history[date]?.apps;
            if (!apps) continue;
            for (const appKey in apps) {
                const rec = apps[appKey];
                if (!root.inSeries(appKey, rec, key)) continue;
                for (const hour in rec.h) out[parseInt(hour)] += rec.h[hour][idx] ?? 0;
            }
        }
        return out;
    }

    /// One field summed per date, parallel to `dates`. Same selection as above.
    function dailySeries(dates, fieldName, key) {
        const idx = root.field[fieldName];
        return dates.map(date => {
            const apps = root.history[date]?.apps;
            if (!apps) return 0;
            let sum = 0;
            for (const appKey in apps) {
                const rec = apps[appKey];
                if (!root.inSeries(appKey, rec, key)) continue;
                for (const hour in rec.h) sum += rec.h[hour][idx] ?? 0;
            }
            return sum;
        });
    }

    /**
     * The battery's own hours for one date: 24 entries, null where nothing was
     * recorded.
     *
     * Kept in a section of its own rather than as another app row, because it is a
     * level as well as an amount — the day view has to know where each hour opened
     * and closed, which no tuple of totals can say. A day file written before the
     * sampler knew about batteries simply has no section, and reads as a day with
     * no battery history rather than as a day at zero percent.
     */
    function batteryHours(date) {
        const stored = root.history[date]?.bat?.h;
        const out = new Array(24).fill(null);
        if (!stored) return out;
        for (const hour in stored) {
            const index = parseInt(hour);
            const t = stored[hour];
            if (!t || !(index >= 0 && index < 24)) continue;
            out[index] = {
                // Tenths of a percent on disk; percent everywhere above this line.
                start: (t[0] ?? 0) / 10,
                end: (t[1] ?? 0) / 10,
                low: (t[2] ?? 0) / 10,
                high: (t[3] ?? 0) / 10,
                outMwh: t[4] ?? 0,
                inMwh: t[5] ?? 0,
                offAc: t[6] ?? 0,
                charging: t[7] ?? 0,
                onAc: t[8] ?? 0
            };
        }
        return out;
    }

    /// Capacity of a full pack in mWh, as measured on `date`. Zero for a day with
    /// no battery section.
    function batteryFull(date) {
        return root.history[date]?.bat?.full ?? 0;
    }

    /**
     * Every recorded battery hour across `dates`, rolled into one figure set.
     * `opts.hourFrom` / `opts.hourTo` narrow it to part of a single day.
     *
     * `hours` is the count of hours that hold anything at all: it is what tells a
     * period the sampler never watched from one where the machine sat untouched,
     * and both look identical in the totals.
     */
    function batteryRollup(dates, opts) {
        const from = opts?.hourFrom ?? 0;
        const to = opts?.hourTo ?? 23;
        const acc = {
            outMwh: 0,
            inMwh: 0,
            offAc: 0,
            charging: 0,
            onAc: 0,
            low: NaN,
            high: NaN,
            first: NaN,
            last: NaN,
            hours: 0,
            fullMwh: 0
        };
        for (const date of dates) {
            const hours = root.batteryHours(date);
            acc.fullMwh = Math.max(acc.fullMwh, root.batteryFull(date));
            for (let hour = from; hour <= to; hour++) {
                const bucket = hours[hour];
                if (!bucket) continue;
                acc.outMwh += bucket.outMwh;
                acc.inMwh += bucket.inMwh;
                acc.offAc += bucket.offAc;
                acc.charging += bucket.charging;
                acc.onAc += bucket.onAc;
                acc.low = isNaN(acc.low) ? bucket.low : Math.min(acc.low, bucket.low);
                acc.high = isNaN(acc.high) ? bucket.high : Math.max(acc.high, bucket.high);
                if (isNaN(acc.first)) acc.first = bucket.start;
                acc.last = bucket.end;
                acc.hours++;
            }
        }
        return acc;
    }

    /// One rollup per date, parallel to `dates`, for the week and month views.
    function batteryDaily(dates) {
        return dates.map(date => root.batteryRollup([date]));
    }

    function wh(mj) {
        return mj / 3600000;
    }

    function entryFor(key) {
        if (!key || key === root.systemKey) return null;
        return DesktopEntries.heuristicLookup(key) ?? DesktopEntries.byId(key) ?? null;
    }

    function displayName(key) {
        if (key === root.systemKey) return Translation.tr("System");
        const name = root.entryFor(key)?.name;
        if (name) return name;
        // A headless daemon, or a window class matching no desktop entry. Its own
        // name still reads better than the raw class string.
        return key.replace(/[-_.]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
    }

    /// Icon theme name for an app key, or "" when nothing matches — headless daemons
    /// and the system row have no desktop entry, and the caller should fall back to
    /// a material symbol rather than showing a broken image.
    ///
    /// The desktop entry is asked first, so an app resolves its icon through the same
    /// lookup that gave it its name. The heuristic guess alone disagrees with that
    /// lookup often enough to matter: it finds no icon for `brave-browser` while the
    /// entry it takes its name from sits right there.
    function iconFor(key) {
        if (key === root.systemKey) return "";
        const entryIcon = root.entryFor(key)?.icon;
        if (entryIcon) return entryIcon;
        const icon = AppSearch.guessIcon(key);
        return (icon === "application-x-executable" || icon === "image-missing") ? "" : icon;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // Wayland reports idleness; nothing else in the shell does. Without this the
    // daemon would keep crediting foreground time to whatever was left on screen.
    IdleMonitor {
        id: idleMonitor
        enabled: root.enabled && root.idleTimeout > 0
        timeout: root.idleTimeout
        respectInhibitors: true
        onIsIdleChanged: root.pushState()
    }

    Connections {
        target: GlobalStates

        function onScreenLockedChanged() {
            root.pushState();
        }
    }

    Timer {
        id: restartTimer
        interval: 200
        onTriggered: root.restarting = false
    }

    // The sampler writes its first day file one flush interval after launch, and
    // FileView cannot watch a path that does not exist yet. Only worth retrying while
    // there is a sampler that could still write it — without a binary the file is
    // never coming, and the retry would otherwise run for the life of the session.
    // The interval backs off so a sampler that keeps failing does not poll at full rate
    // forever, but stays short enough that a first flush is picked up soon after it lands.
    Timer {
        id: todayRetryTimer
        interval: 5000
        repeat: true
        running: root.enabled && root.binaryPresent && root.history[root.todayDate] === null
        onRunningChanged: if (running) interval = 5000
        onTriggered: {
            todayView.reload();
            interval = Math.min(interval * 2, 30000);
        }
    }

    Timer {
        id: reloadTimer
        interval: 200
        onTriggered: todayView.reload()
    }

    // The unlink is detached, so the count that follows it has to wait for the
    // filesystem rather than for the call to return.
    Timer {
        id: clearTimer
        interval: 400
        onTriggered: {
            todayView.reload();
            root.measureStorage();
        }
    }

    Component.onCompleted: root.checkInstall()

    Process {
        id: installProbe
        command: ["sh", "-c", `b=0; [ -x "${root.binaryPath}" ] && b=1; r=2; for f in /sys/class/powercap/intel-rapl:*/energy_uj; do [ -e "$f" ] || continue; if head -c1 "$f" >/dev/null 2>&1; then r=1; else r=0; fi; break; done; printf '%s %s' "$b" "$r"`]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                // The sampler launches off this, so a binary that appeared while the
                // shell was up — one just built — starts collecting on its own.
                root.binaryPresent = parts[0] === "1";
                root.raplState = parseInt(parts[1]);
                root.probed = true;
            }
        }
    }

    Process {
        id: storageProcess
        command: ["sh", "-c", `printf '%s %s' "$(ls -1 "${root.stateDir}"/*.json 2>/dev/null | wc -l)" "$(du -sb "${root.stateDir}" 2>/dev/null | cut -f1)"`]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.storedDays = parseInt(parts[0]) || 0;
                root.storedBytes = parseInt(parts[1]) || 0;
            }
        }
    }

    FileView {
        id: todayView
        path: `${root.stateDir}/${root.todayDate}.json`
        watchChanges: true
        // A day file that does not exist yet is the normal state before the first
        // flush, and the permanent state where the sampler was never built. Neither
        // is worth a warning per retry.
        printErrors: false

        onFileChanged: reloadTimer.restart()
        onLoaded: root.storeDay(root.todayDate, root.parseDoc(todayView.text()))
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.storeDay(root.todayDate, null);
        }
    }

    // One reader per requested day, in parallel. Day files are small and immutable
    // once the date has passed, so there is nothing to serialise them for.
    Instantiator {
        model: root.loadBatch

        delegate: FileView {
            required property string modelData
            path: `${root.stateDir}/${modelData}.json`
            printErrors: false

            onLoaded: root.storeDay(modelData, root.parseDoc(text()))
            onLoadFailed: root.storeDay(modelData, null)
        }
    }

    readonly property string launchKey: [root.intervalMs, root.flushMs, root.retentionDays, root.retentionMode, root.energySource, root.gpuFullEvery, root.trackHeadless].join("|")
    onLaunchKeyChanged: root.restart()

    Process {
        id: sampler
        running: root.enabled && root.probed && root.binaryPresent && !root.restarting
        stdinEnabled: true
        command: {
            const args = [root.binaryPath, "--state-dir", root.stateDir, "--interval-ms", `${root.intervalMs}`, "--flush-ms", `${root.flushMs}`, "--retention-days", `${root.retentionDays}`, "--retention-mode", root.retentionMode === "previousMonth" ? "previous-month" : "fixed", "--energy", root.energySource, "--gpu-full-every", `${root.gpuFullEvery}`];
            if (!root.trackHeadless) args.push("--no-headless");
            return args;
        }

        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }

        stderr: SplitParser {
            onRead: data => console.warn("[AppStats]", data)
        }

        onExited: (code, status) => {
            root.running = false;
            root.lastSample = null;
            if (code !== 0 && !root.restarting) console.warn(`[AppStats] sampler exited with code ${code}`);
        }
    }
}
