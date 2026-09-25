pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Every world clock in the shell reads from here: the bar's clock popup and the clock app.
 *
 * Offsets come from one Python process per refresh instead of one `date` per city. A
 * refresh happens when the list changes, when a surface that shows the clocks opens and
 * finds them stale, and on the hour while a surface holds the service (DST moves offsets
 * on the hour). Nothing ticks here: the clocks themselves are drawn from `DateTime`.
 */
Singleton {
    id: root

    readonly property string scriptPath: `${Directories.scriptPath}/clock/timezones.py`
    readonly property int staleAfterMs: 30 * 60 * 1000

    readonly property var clocks: Array.from(Config.options?.time?.worldClocks ?? [])
    property var offsets: ({})
    property string localZone: ""
    property real refreshedAt: 0
    property int holders: 0

    property var catalog: []
    property bool catalogLoading: false

    readonly property bool use12Hour: DateUtils.is12HourTimeFormat(Config.options?.time?.format ?? "hh:mm")
    readonly property int localOffsetMinutes: -DateTime.clock.date.getTimezoneOffset()

    onClocksChanged: root.refresh()
    Component.onCompleted: root.refresh()

    Connections {
        target: DateTime
        function onHoursChanged() {
            if (root.holders > 0)
                root.refresh();
        }
    }

    function retain(): void {
        root.holders++;
        root.refreshIfStale();
    }

    function release(): void {
        root.holders = Math.max(0, root.holders - 1);
    }

    function refresh(): void {
        const zones = root.clocks.map(entry => String(entry?.tz ?? "")).filter(tz => tz.length > 0);
        if (zones.length === 0) {
            root.offsets = {};
            return;
        }
        offsetProcess.running = false;
        offsetProcess.command = ["python3", root.scriptPath].concat(zones);
        offsetProcess.running = true;
    }

    function refreshIfStale(): void {
        if (Date.now() - root.refreshedAt > root.staleAfterMs)
            root.refresh();
    }

    function loadCatalog(): void {
        if (root.catalog.length > 0 || catalogProcess.running)
            return;
        root.catalogLoading = true;
        catalogProcess.running = true;
    }

    function releaseCatalog(): void {
        catalogProcess.running = false;
        root.catalogLoading = false;
        root.catalog = [];
    }

    Process {
        id: offsetProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const reply = JSON.parse(this.text);
                    const next = {};
                    for (const zone of reply.zones ?? [])
                        next[zone.tz] = { offsetMins: Number(zone.offset), abbreviation: String(zone.abbr ?? "") };
                    root.offsets = next;
                    root.localZone = String(reply.local ?? "");
                    root.refreshedAt = Date.now();
                } catch (error) {
                    console.warn("[WorldClockService] Could not read offsets:", error);
                }
            }
        }
    }

    Process {
        id: catalogProcess
        command: ["python3", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.catalogLoading = false;
                try {
                    const reply = JSON.parse(this.text);
                    root.localZone = String(reply.local ?? root.localZone);
                    root.catalog = (reply.zones ?? []).map(zone => ({
                        tz: zone.tz,
                        offsetMins: Number(zone.offset),
                        abbreviation: String(zone.abbr ?? ""),
                        city: root.cityFromZone(zone.tz),
                        region: root.regionFromZone(zone.tz)
                    }));
                } catch (error) {
                    console.warn("[WorldClockService] Could not read the timezone catalog:", error);
                }
            }
        }
    }

    // ── Reading ─────────────────────────────────────────────────────────

    function cityFromZone(tz): string {
        const parts = String(tz ?? "").split("/");
        return parts[parts.length - 1].replace(/_/g, " ");
    }

    function regionFromZone(tz): string {
        const parts = String(tz ?? "").split("/");
        return parts.length > 1 ? parts.slice(0, parts.length - 1).join(" / ").replace(/_/g, " ") : "";
    }

    function displayName(entry): string {
        const name = String(entry?.name ?? "").trim();
        return name.length > 0 ? name : root.cityFromZone(entry?.tz);
    }

    function hasOffset(tz): bool {
        return root.offsets[tz] !== undefined;
    }

    function offsetMinutes(tz): real {
        const data = root.offsets[tz];
        return data ? data.offsetMins : NaN;
    }

    function abbreviation(tz): string {
        return root.offsets[tz]?.abbreviation ?? "";
    }

    /** Milliseconds whose UTC fields read as the wall clock in `tz`. */
    function zonedTime(tz, date): real {
        const offset = root.offsetMinutes(tz);
        return isNaN(offset) ? NaN : date.getTime() + offset * 60000;
    }

    /** A local Date carrying the wall-clock fields of `tz`, for Qt's formatters and dials. */
    function wallClock(tz, date): var {
        const zoned = root.zonedTime(tz, date);
        if (isNaN(zoned))
            return null;
        const shifted = new Date(zoned);
        return new Date(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate(),
            shifted.getUTCHours(), shifted.getUTCMinutes(), shifted.getUTCSeconds());
    }

    function formatTime(tz, date, withSeconds = false): string {
        const wall = root.wallClock(tz, date);
        if (!wall)
            return "--:--";
        const format = Config.options?.time?.format ?? "hh:mm";
        const withSecondsFormat = withSeconds ? format.replace(/mm/, "mm:ss") : format;
        return Qt.locale().toString(wall, withSecondsFormat);
    }

    function formatHourMinute(tz, date): string {
        const wall = root.wallClock(tz, date);
        if (!wall)
            return "--:--";
        const hour = root.use12Hour ? (wall.getHours() % 12 || 12) : wall.getHours();
        return String(hour).padStart(2, "0") + ":" + String(wall.getMinutes()).padStart(2, "0");
    }

    function meridiem(tz, date): string {
        const wall = root.wallClock(tz, date);
        if (!wall || !root.use12Hour)
            return "";
        return wall.getHours() >= 12 ? Qt.locale().pmText : Qt.locale().amText;
    }

    function formatDate(tz, date, format = "ddd, d MMM"): string {
        const wall = root.wallClock(tz, date);
        return wall ? Qt.locale().toString(wall, format) : "";
    }

    /** -1 yesterday, 0 today, 1 tomorrow — relative to the local calendar day. */
    function dayRelation(tz, date): int {
        const wall = root.wallClock(tz, date);
        if (!wall)
            return 0;
        const local = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        const there = new Date(wall.getFullYear(), wall.getMonth(), wall.getDate());
        return Math.round((there.getTime() - local.getTime()) / 86400000);
    }

    function dayRelationLabel(tz, date): string {
        const relation = root.dayRelation(tz, date);
        if (relation > 0)
            return Translation.tr("Tomorrow");
        if (relation < 0)
            return Translation.tr("Yesterday");
        return Translation.tr("Today");
    }

    function formatOffset(minutes): string {
        if (minutes === 0)
            return "";
        const sign = minutes > 0 ? "+" : "-";
        const hours = Math.floor(Math.abs(minutes) / 60);
        const rest = Math.abs(minutes) % 60;
        return rest === 0 ? `${sign}${hours}h` : `${sign}${hours}h ${rest}m`;
    }

    /** The difference to local time, "" when there is none. */
    function relativeOffsetLabel(tz, date): string {
        const offset = root.offsetMinutes(tz);
        if (isNaN(offset))
            return "";
        return root.formatOffset(offset + date.getTimezoneOffset());
    }

    function utcOffsetLabel(minutes): string {
        const sign = minutes < 0 ? "-" : "+";
        const hours = String(Math.floor(Math.abs(minutes) / 60)).padStart(2, "0");
        const rest = String(Math.abs(minutes) % 60).padStart(2, "0");
        return `UTC${sign}${hours}:${rest}`;
    }

    function isNight(tz, date): bool {
        const wall = root.wallClock(tz, date);
        if (!wall)
            return false;
        const hour = wall.getHours();
        return hour < 6 || hour >= 18;
    }

    /** Fraction of the day passed in `tz`, 0..1. */
    function dayFraction(tz, date): real {
        const wall = root.wallClock(tz, date);
        if (!wall)
            return 0;
        return (wall.getHours() * 3600 + wall.getMinutes() * 60 + wall.getSeconds()) / 86400;
    }

    // ── Editing ─────────────────────────────────────────────────────────

    function write(list): void {
        if (Config.options?.time)
            Config.options.time.worldClocks = list;
    }

    function contains(tz): bool {
        return root.clocks.some(entry => entry?.tz === tz);
    }

    function addClock(tz, name = ""): bool {
        const zone = String(tz ?? "").trim();
        if (zone.length === 0 || root.contains(zone))
            return false;
        root.write(root.clocks.concat([{ name: String(name ?? "").trim(), tz: zone }]));
        return true;
    }

    function removeClock(index): void {
        if (index < 0 || index >= root.clocks.length)
            return;
        const next = root.clocks.slice();
        next.splice(index, 1);
        root.write(next);
    }

    function renameClock(index, name): void {
        if (index < 0 || index >= root.clocks.length)
            return;
        const next = root.clocks.map((entry, i) => i === index
            ? { name: String(name ?? "").trim(), tz: entry.tz }
            : { name: entry.name ?? "", tz: entry.tz });
        root.write(next);
    }

    function moveClock(from, to): void {
        if (from === to || from < 0 || to < 0 || from >= root.clocks.length || to >= root.clocks.length)
            return;
        const next = root.clocks.slice();
        const moved = next.splice(from, 1)[0];
        next.splice(to, 0, moved);
        root.write(next);
    }
}
