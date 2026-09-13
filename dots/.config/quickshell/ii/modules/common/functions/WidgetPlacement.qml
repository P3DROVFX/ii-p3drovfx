pragma Singleton
import Quickshell

/**
 * Per-monitor placement of desktop widgets.
 *
 * An activeWidgets entry carries a legacy top-level x/y/scale plus an optional
 * `positions` map keyed by monitor name, and an optional `lockPositions` map
 * with the same shape for the lock screen:
 *
 *     { "id": "widget_clock_cookie_1", "x": 200, "y": 200, "scale": 1.25,
 *       "positions": { "DP-1": { "x": 640, "y": 80, "scale": 1.25 } },
 *       "lockPositions": { "DP-1": { "x": 640, "y": 300 } } }
 *
 * A monitor with an entry in a map owns its own placement; every other
 * monitor shows the legacy values. The first move or resize on a monitor forks
 * it into the map, and this shell never writes the legacy values again for
 * that entry. The lock map forks the same way from whatever the desktop
 * shows, and a lock surface without a fork follows the desktop. An older
 * shell keeps reading and writing the legacy values and carries both maps
 * along untouched (every writer clones the whole entry), so neither side
 * loses the other's layout.
 *
 * Entries are plain JS objects here: readers get them straight out of the
 * config list, writers get the JSON clone Config makes before reassigning.
 */
Singleton {
    id: root

    function _mapKey(lock) {
        return lock ? "lockPositions" : "positions";
    }

    function fork(entry, monitorName, lock = false) {
        if (!entry || !monitorName)
            return null;
        const map = entry[root._mapKey(lock)];
        if (!map || typeof map !== "object")
            return null;
        const forked = map[monitorName];
        return (forked && typeof forked === "object") ? forked : null;
    }

    // Fallback: If this monitor has no fork, check if any other monitor has a configured fork.
    function fallbackFork(entry, lock = false) {
        if (!entry)
            return null;
        const map = entry[root._mapKey(lock)];
        if (!map || typeof map !== "object")
            return null;
        const keys = Object.keys(map);
        for (let i = 0; i < keys.length; i++) {
            const f = map[keys[i]];
            if (f && typeof f === "object" && (f.x !== undefined || f.y !== undefined))
                return f;
        }
        return null;
    }

    // What `entry` shows on `monitorName`: {x, y, scale, forked}. Never null.
    // With `lock`, the lock screen's placement: its own fork when there is
    // one, the desktop's placement otherwise.
    function resolve(entry, monitorName, lock = false, screenW = 0, screenH = 0) {
        if (!entry)
            return { "x": 0, "y": 0, "scale": 1.0, "forked": false };
        const localDesktop = root.fork(entry, monitorName, false);
        const localLock = lock ? root.fork(entry, monitorName, true) : null;
        const hasLocalFork = (lock ? localLock : localDesktop) !== null;

        const desktop = localDesktop ?? root.fallbackFork(entry, false);
        const lockFork = lock ? (localLock ?? root.fallbackFork(entry, true)) : null;
        const src = lockFork ?? desktop ?? entry;
        const base = desktop ?? entry;

        let rawX = Number(src.x ?? base.x ?? entry.x ?? 0);
        let rawY = Number(src.y ?? base.y ?? entry.y ?? 0);
        let rawScale = Number(src.scale ?? base.scale ?? entry.scale ?? 1.0);

        // If this monitor does NOT have its own fork (i.e. using a fallback from an
        // imported preset or other monitor), adapt to screen proportions if screenW/H are provided:
        if (!hasLocalFork && screenW > 0 && screenH > 0) {
            const refW = Number(entry.refWidth || (typeof Config !== "undefined" && Config.options && Config.options.background && Config.options.background.referenceResolution ? Config.options.background.referenceResolution.width : 0) || 1920);
            const refH = Number(entry.refHeight || (typeof Config !== "undefined" && Config.options && Config.options.background && Config.options.background.referenceResolution ? Config.options.background.referenceResolution.height : 0) || 1080);
            if (refW > 0 && refH > 0 && (screenW !== refW || screenH !== refH)) {
                rawX = Math.round(rawX * (screenW / refW));
                rawY = Math.round(rawY * (screenH / refH));
            }
        }

        return {
            "x": rawX,
            "y": rawY,
            "scale": rawScale,
            "forked": hasLocalFork
        };
    }

    function findEntry(list, instanceId) {
        const entries = list || [];
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].id === instanceId)
                return entries[i];
        }
        return null;
    }

    function resolveIn(list, instanceId, monitorName, lock = false, screenW = 0, screenH = 0) {
        return root.resolve(root.findEntry(list, instanceId), monitorName, lock, screenW, screenH);
    }

    // The fork starts from whatever the surface currently shows, so forking
    // never moves anything.
    function _ensureFork(entry, monitorName, lock) {
        const key = root._mapKey(lock);
        if (!entry[key] || typeof entry[key] !== "object")
            entry[key] = {};
        let forked = entry[key][monitorName];
        if (!forked || typeof forked !== "object") {
            const current = root.resolve(entry, monitorName, lock);
            forked = { "x": current.x, "y": current.y };
            if (entry.scale !== undefined)
                forked.scale = current.scale;
            entry[key][monitorName] = forked;
        }
        return forked;
    }

    // Writers mutate `entry` in place; callers pass a clone. Without a monitor
    // name the legacy values are written, which is what every pre-fork caller
    // did and what a monitor without a fork follows.
    function setPosition(entry, monitorName, x, y, lock = false) {
        if (!entry)
            return;
        if (!lock) {
            entry.x = x;
            entry.y = y;
        }
        if (!monitorName)
            return;
        const forked = root._ensureFork(entry, monitorName, lock);
        forked.x = x;
        forked.y = y;
    }

    function setScale(entry, monitorName, scale, lock = false) {
        if (!entry)
            return;
        if (!lock) {
            entry.scale = scale;
        }
        if (!monitorName)
            return;
        root._ensureFork(entry, monitorName, lock).scale = scale;
    }

    // Drops the monitor's fork so it follows the legacy values (or, for the
    // lock surface, the desktop) again. Returns whether anything changed.
    function clearFork(entry, monitorName, lock = false) {
        if (!root.fork(entry, monitorName, lock))
            return false;
        const key = root._mapKey(lock);
        delete entry[key][monitorName];
        if (Object.keys(entry[key]).length === 0)
            delete entry[key];
        return true;
    }
}
