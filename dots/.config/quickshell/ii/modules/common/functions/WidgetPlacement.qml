pragma Singleton
import Quickshell
import qs.modules.common

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
 * shows, and a lock surface without a fork follows the desktop. The lock map
 * is only read for a widget whose lockBehavior gives it a lock placement of
 * its own ("custom", or "lockOnly", which has no desktop one); "keep" always
 * follows the desktop, so a fork left behind by an earlier custom placement
 * waits there until the widget is made custom again. An older
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

    // Whether `entry` places itself on the lock screen rather than following
    // the desktop there.
    function ownsLockPlacement(entry) {
        const behavior = entry ? (entry.lockBehavior || "hide") : "hide";
        return behavior === "custom" || behavior === "lockOnly";
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
        lock = lock && root.ownsLockPlacement(entry);
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

        // A lock without its own placement can inherit this monitor's desktop
        // coordinates. They are already local, even though hasLocalFork is false.
        // Only legacy or other-monitor coordinates need resolution adaptation.
        const inheritsLocalDesktop = lock && lockFork === null && localDesktop !== null;
        if (!hasLocalFork && !inheritsLocalDesktop && screenW > 0 && screenH > 0) {
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

    // ── Which monitors build a widget ──────────────────────────────────────
    // An entry may carry `monitors`: the screen names it is drawn on, or "*"
    // for every screen. Without it the widget lives on the primary monitor
    // only. Every screen used to build every widget, which on two monitors
    // paid each widget twice in RAM; a widget is now built only where it is
    // shown, so a second screen costs nothing until something is added there.
    // An entry whose monitors are all disconnected falls back to the primary
    // one rather than disappearing with the cable.

    readonly property var connectedScreens: Quickshell.screens.map(s => s.name)

    // targetMonitor when set and connected, else the first external screen
    // (a laptop on a desk shows its widgets on the big one), else the first.
    readonly property string primaryMonitor: {
        const names = root.connectedScreens;
        const target = Config.options?.background?.widgets?.targetMonitor ?? "";
        if (target !== "" && names.includes(target))
            return target;
        const external = names.find(n => !/^(eDP|LVDS|DSI)/.test(n));
        return external ?? names[0] ?? "";
    }

    function monitorsOf(entry) {
        // Read back from Config's list<var>, the nested array is a QML sequence
        // wrapper, not a JS Array: Array.isArray rejects it, so take any array-like.
        const m = entry?.monitors;
        if (!m || typeof m === "string" || typeof m.length !== "number")
            return [];
        return Array.from(m).filter(n => typeof n === "string" && n !== "");
    }

    function showsOn(entry, monitorName) {
        if (!entry)
            return false;
        if (!monitorName)
            return true;
        const own = root.monitorsOf(entry);
        if (own.includes("*") || own.includes(monitorName))
            return true;
        if (own.some(n => root.connectedScreens.includes(n)))
            return false;
        return monitorName === root.primaryMonitor;
    }

    function showsOnAll(entry) {
        return root.monitorsOf(entry).includes("*");
    }

    // Writers mutate `entry` in place (callers pass a clone).
    function setShownOn(entry, monitorName, shown) {
        if (!entry || !monitorName)
            return;
        let own = root.monitorsOf(entry).filter(n => n !== "*");
        if (own.length === 0 || root.showsOnAll(entry))
            own = root.showsOnAll(entry) ? root.connectedScreens.slice() : [root.primaryMonitor];
        own = own.filter(n => n !== monitorName);
        if (shown)
            own.push(monitorName);
        entry.monitors = own;
    }

    function setShownOnAll(entry, all, monitorName) {
        if (!entry)
            return;
        entry.monitors = all ? ["*"] : [monitorName || root.primaryMonitor];
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

    // Moving or resizing a widget on the lock surface gives it a lock
    // placement of its own: a "keep" or "center" widget turns "custom", its
    // fork on this monitor seeded from what the desktop shows so claiming
    // never moves anything (a stale fork from an earlier custom placement is
    // replaced). The caller writes the new position or scale right after.
    function claimLockPlacement(entry, monitorName) {
        if (!entry || root.ownsLockPlacement(entry))
            return;
        entry.lockBehavior = "custom";
        if (!monitorName)
            return;
        const desktop = root.resolve(entry, monitorName, false);
        const forked = { "x": desktop.x, "y": desktop.y };
        if (entry.scale !== undefined || root.fork(entry, monitorName, false)?.scale !== undefined)
            forked.scale = desktop.scale;
        if (!entry.lockPositions || typeof entry.lockPositions !== "object")
            entry.lockPositions = {};
        entry.lockPositions[monitorName] = forked;
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
