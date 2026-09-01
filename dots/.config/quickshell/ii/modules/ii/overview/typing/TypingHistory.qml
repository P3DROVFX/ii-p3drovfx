pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * Local, bounded score history for the typing test.
 *
 * Only aggregate metrics are stored — never the target text and never the keys
 * that were pressed — and only when the user has left history enabled. Writes
 * happen once per finished test, never on the input path.
 */
Singleton {
    id: root

    readonly property var results: Persistent.states.typingTest.recentResults ?? []
    readonly property var personalBests: Persistent.states.typingTest.personalBests ?? []
    readonly property int testsStarted: Persistent.states.typingTest.testsStarted ?? 0
    readonly property int testsCompleted: Persistent.states.typingTest.testsCompleted ?? 0
    readonly property real secondsTyping: Persistent.states.typingTest.secondsTyping ?? 0
    readonly property var activity: Persistent.states.typingTest.activity ?? []
    /** Days kept in the activity tally — a year plus a little slack. */
    readonly property int activityWindowDays: 372

    /**
     * Lifetime counters only started being kept once this page existed, so on
     * their own they read zero next to a history full of results. The stored
     * results are a floor for all three: they are tests that certainly ran.
     * Exact from here on, honest about what came before.
     */
    readonly property int completedTotal: Math.max(root.testsCompleted, root.results.length)
    readonly property int startedTotal: Math.max(root.testsStarted, root.completedTotal)
    readonly property real typingSeconds: {
        if (root.secondsTyping > 0)
            return root.secondsTyping;
        return Array.from(root.results).reduce((total, entry) => total + (entry.duration ?? 0), 0);
    }

    readonly property real averageWpm: {
        const entries = Array.from(root.results);
        if (entries.length === 0)
            return 0;
        return entries.reduce((total, entry) => total + (entry.wpm ?? 0), 0) / entries.length;
    }
    readonly property real averageAccuracy: {
        const entries = Array.from(root.results);
        if (entries.length === 0)
            return 0;
        return entries.reduce((total, entry) => total + (entry.accuracy ?? 0), 0) / entries.length;
    }

    function dayKey(timestamp) {
        return Qt.formatDate(new Date(Number(timestamp)), "yyyy-MM-dd");
    }

    /** Tests finished on a given day, for the activity map. */
    function testsOn(key) {
        return Array.from(root.activity).find(entry => entry.d === key)?.n ?? 0;
    }

    function resultsSince(sinceMs) {
        return Array.from(root.results)
            .filter(entry => sinceMs <= 0 || Number(entry.timestamp ?? 0) >= sinceMs);
    }

    /** Best stored result for one mode and length, across languages. */
    function bestOf(mode, modeValue) {
        let best = null;
        for (const entry of Array.from(root.personalBests)) {
            if (entry.mode !== mode || entry.modeValue !== modeValue)
                continue;
            if (!best || (entry.wpm ?? 0) > (best.wpm ?? 0))
                best = entry;
        }
        return best;
    }

    /** Personal bests are per exact test setup: a 15s PB is not a 60s PB. */
    function keyOf(result) {
        return [result.mode, result.modeValue, result.language,
            result.punctuation ? "p" : "-", result.numbers ? "n" : "-"].join(":");
    }

    function describe(result) {
        if (result.mode === "time")
            return Translation.tr("%1s").arg(String(result.modeValue));
        if (result.mode === "words")
            return Translation.tr("%1 words").arg(String(result.modeValue));
        return Translation.tr("zen");
    }

    function bestFor(result) {
        const key = root.keyOf(result);
        return Array.from(root.personalBests).find(best => best.key === key) ?? null;
    }

    /** True when this result beat the stored best, evaluated before recording. */
    function beatsBest(result) {
        const best = root.bestFor(result);
        return !best || result.wpm > best.wpm;
    }

    /**
     * A test began. Counted separately from completions so the ratio of
     * abandoned runs stays visible, and written straight to Persistent — its
     * own write timer debounces, so this costs one property assignment on the
     * first keystroke rather than a disk touch.
     */
    function registerStart() {
        if (!Config.options.search.typingTest.history.enable)
            return;
        Persistent.states.typingTest.testsStarted = root.testsStarted + 1;
    }

    /** Time spent typing counts every mode, zen included. */
    function registerFinish(result) {
        if (!Config.options.search.typingTest.history.enable || result.duration < 1)
            return;
        Persistent.states.typingTest.testsCompleted = root.testsCompleted + 1;
        Persistent.states.typingTest.secondsTyping = root.secondsTyping + result.duration;

        const key = root.dayKey(result.timestamp);
        const cutoff = Date.now() - root.activityWindowDays * 86400000;
        const kept = Array.from(root.activity)
            .filter(entry => new Date(entry.d + "T00:00:00").getTime() >= cutoff);
        const existing = kept.find(entry => entry.d === key);
        if (existing)
            existing.n = (existing.n ?? 0) + 1;
        else
            kept.push({ d: key, n: 1 });
        Persistent.states.typingTest.activity = kept;
    }

    function record(result) {
        if (!Config.options.search.typingTest.history.enable)
            return false;
        root.registerFinish(result);
        // Zen has no target, so its WPM is not comparable with a real test.
        if (result.mode === "zen" || result.duration < 1)
            return false;

        const improved = root.beatsBest(result);
        const limit = Math.max(1, Math.min(500, Config.options.search.typingTest.history.maxEntries));
        Persistent.states.typingTest.recentResults = [result]
            .concat(Array.from(root.results))
            .slice(0, limit);

        if (improved) {
            const key = root.keyOf(result);
            Persistent.states.typingTest.personalBests = Array.from(root.personalBests)
                .filter(best => best.key !== key)
                .concat([Object.assign({ key: key }, result)]);
        }
        return improved;
    }

    function clear() {
        Persistent.states.typingTest.recentResults = [];
        Persistent.states.typingTest.personalBests = [];
        Persistent.states.typingTest.testsStarted = 0;
        Persistent.states.typingTest.testsCompleted = 0;
        Persistent.states.typingTest.secondsTyping = 0;
        Persistent.states.typingTest.activity = [];
    }
}
