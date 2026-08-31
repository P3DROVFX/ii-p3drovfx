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

    function record(result) {
        if (!Config.options.search.typingTest.history.enable)
            return false;
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
    }
}
