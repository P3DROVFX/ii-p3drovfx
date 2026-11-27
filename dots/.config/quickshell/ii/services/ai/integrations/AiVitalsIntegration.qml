pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import "../../vitals/VitalsLogic.js" as Logic

/**
 * The assistant's view of ii Vitals: three read-only tools over VitalsService (a range
 * at a glance, one day, one metric's trend). The registry offers them only while
 * `vitals.assistant.enable` is on, since their answers leave the PC for the provider.
 *
 * Everything goes through VitalsLogic's digests, which return aggregates only: age
 * instead of the birth date, no route points or record ids, nothing finer than hours.
 */
QtObject {
    id: root

    /// An asynchronous tool finished; Ai settles the broker call with it.
    signal resultReady(string key, var outcome)

    /// Broker key → date of a vitals_day call waiting for its day file.
    property var _waiting: ({})
    // Set by the first wait: a bound target would create VitalsService with Ai, vitals on or not.
    property bool _listening: false

    function _today(): string {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    /// The service's verdict when there is nothing to read, else null.
    function _unavailable(): var {
        if (!VitalsService.enabled)
            return { status: "error", summary: Translation.tr("ii Vitals is off"), data: null };
        if (VitalsService.dates.length === 0)
            return { status: "error", summary: Translation.tr("No health data synced yet"), data: null };
        return null;
    }

    /// [from, to] from the arguments: dates as given, `to` today and `from` a week
    /// before it by default, at most a year apart.
    function _range(args, defaultDays): var {
        const to = Logic.isDate(String(args?.to ?? "")) ? String(args.to) : root._today();
        let from = Logic.isDate(String(args?.from ?? "")) ? String(args.from) : Logic.addDays(to, -(defaultDays - 1));
        if (from > to)
            return null;
        if (Logic.daysBetween(from, to) > 365)
            from = Logic.addDays(to, -365);
        return [from, to];
    }

    function summary(args): var {
        const off = root._unavailable();
        if (off)
            return off;
        const range = root._range(args, 7);
        if (!range)
            return { status: "error", summary: Translation.tr("'from' is after 'to'"), data: null, retryable: true };
        return {
            status: "success",
            summary: Translation.tr("Vitals %1 – %2").arg(range[0]).arg(range[1]),
            data: {
                profile: Logic.profileDigest(VitalsService.meta, root._today()),
                goals: VitalsService.meta?.goals ?? {},
                kinds: Object.keys(VitalsService.present),
                range: Logic.rangeDigest(VitalsService.index, VitalsService.dates, range[0], range[1])
            }
        };
    }

    function day(key, args): var {
        const off = root._unavailable();
        if (off)
            return off;
        const date = Logic.isDate(String(args?.date ?? "")) ? String(args.date) : root._today();
        if (!VitalsService.summary(date))
            return { status: "error", summary: Translation.tr("No vitals for %1").arg(date), data: null, retryable: true };
        const d = VitalsService.day(date);
        if (d !== null)
            return root._dayOutcome(date, d);
        // The file is loading: answer when it lands, or from the index alone if it never does.
        root._waiting[key] = date;
        root._listening = true;
        root.dayTimeout.restart();
        return { status: "pending" };
    }

    function _dayOutcome(date, d): var {
        return {
            status: "success",
            summary: Translation.tr("Vitals for %1").arg(date),
            data: Logic.dayDigest(date, VitalsService.summary(date), d)
        };
    }

    function _settle(date, d): void {
        for (const key of Object.keys(root._waiting)) {
            if (date !== null && root._waiting[key] !== date)
                continue;
            const when = root._waiting[key];
            delete root._waiting[key];
            root.resultReady(key, root._dayOutcome(when, d));
        }
    }

    readonly property Connections _loads: Connections {
        target: root._listening ? VitalsService : null
        function onDayLoaded(date) {
            if (Object.values(root._waiting).includes(date))
                root._settle(date, VitalsService.day(date));
        }
    }

    readonly property Timer dayTimeout: Timer {
        interval: 3000
        onTriggered: root._settle(null, null)
    }

    function trend(args): var {
        const off = root._unavailable();
        if (off)
            return off;
        // Sessions have no per-day value of their own: their minutes do.
        const asked = String(args?.key ?? "");
        const key = asked === "sleep" ? "sleepMin" : asked === "exercise" ? "exMin" : asked;
        const known = VitalsService.present[key] === true || key === "sleepMin" || key === "exMin"
            || (key.indexOf(".") > 0 && VitalsService.present[key.slice(0, key.indexOf("."))] === true);
        if (!known)
            return { status: "error", summary: Translation.tr("No such metric"), data: { kinds: Object.keys(VitalsService.present) }, retryable: true };
        const range = root._range(args, 30);
        if (!range)
            return { status: "error", summary: Translation.tr("'from' is after 'to'"), data: null, retryable: true };
        return {
            status: "success",
            summary: Translation.tr("%1 trend").arg(VitalsTypes.label(key.split(".")[0])),
            data: Logic.trendDigest(VitalsService.index, VitalsService.dates, key, range[0], range[1])
        };
    }
}
