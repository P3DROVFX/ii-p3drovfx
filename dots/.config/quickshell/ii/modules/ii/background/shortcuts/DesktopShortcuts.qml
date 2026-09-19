pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

Singleton {
    id: root

    // Decode only when persisted state changes, not on pointer movement or per icon.
    readonly property var screens: {
        try {
            const value = JSON.parse(Persistent.states.desktopShortcutsJson);
            return value && typeof value === "object" && !Array.isArray(value) ? value : {};
        } catch (error) {
            console.warn("[DesktopShortcuts] Invalid persisted data:", error);
            return {};
        }
    }
    property string error: ""
    property var importQueue: []
    property var currentImport: null

    function importUrls(screenName, urls, x, y, targetId, width, height) {
        if (!Persistent.ready || !urls.length)
            return false;
        root.importQueue.push({ screen: screenName, urls: urls, x: x, y: y,
            target: targetId, width: width, height: height });
        root.startImport();
        return true;
    }

    function startImport() {
        if (root.currentImport || !root.importQueue.length)
            return;
        root.error = "";
        root.currentImport = root.importQueue.shift();
        resolver.command = ["/usr/bin/python3", Directories.scriptPath + "/desktop_shortcuts.py",
            JSON.stringify(root.currentImport.urls)];
        resolver.running = true;
    }

    Process {
        id: resolver
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    const request = root.currentImport;
                    root.error = result.errors.join("\n");
                    root.add(request.screen, result.items, request.x, request.y, request.target, request.width, request.height);
                } catch (error) {
                    root.error = Translation.tr("Could not import desktop shortcut");
                    console.warn("[DesktopShortcuts]", error);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.error = Translation.tr("Could not import desktop shortcut");
            root.currentImport = null;
            resolver.command = [];
            Qt.callLater(root.startImport);
        }
    }

    function itemsFor(screenName) {
        const items = root.screens[screenName];
        return Array.isArray(items) ? items : [];
    }

    function save(screenName, items) {
        if (!Persistent.ready || Persistent.blockWrites)
            return false;
        const next = Object.assign({}, root.screens);
        next[screenName] = items;
        Persistent.states.desktopShortcutsJson = JSON.stringify(next);
        return true;
    }

    function add(screenName, entries, x, y, targetId, width, height) {
        if (!entries.length)
            return false;
        const items = root.itemsFor(screenName).slice();
        const targetIndex = targetId && entries.every(entry => root.isGroupable(entry))
            ? items.findIndex(item => item.id === targetId && root.isGroupable(item)) : -1;
        if (targetIndex >= 0) {
            const target = items[targetIndex];
            const apps = target.type === "group" ? target.apps.slice() : [target];
            for (const entry of entries) {
                if (!root.isGroupable(entry))
                    continue;
                for (const app of entry.type === "group" ? entry.apps : [entry]) {
                    if (!apps.some(existing => existing.id === app.id))
                        apps.push(app);
                }
            }
            items[targetIndex] = { id: target.type === "group" ? target.id : "group:" + Date.now(),
                type: "group", name: target.type === "group" ? target.name : Translation.tr("App group"),
                apps: apps, x: target.x, y: target.y };
        } else {
            for (const entry of entries) {
                if (items.some(item => item.id === entry.id))
                    continue;
                const maxX = Math.max(0, (width || 1920) - 100);
                const maxY = Math.max(0, (height || 1080) - 100);
                let px = Math.max(0, Math.min(maxX, Math.round(x / 10) * 10));
                let py = Math.max(0, Math.min(maxY, Math.round(y / 10) * 10));
                if (items.some(item => Math.abs(item.x - px) < 100 && Math.abs(item.y - py) < 100)) {
                    let found = false;
                    for (let row = 0; row <= maxY && !found; row += 100) {
                        for (let col = 0; col <= maxX; col += 100) {
                            if (!items.some(item => Math.abs(item.x - col) < 100 && Math.abs(item.y - row) < 100)) {
                                px = col;
                                py = row;
                                found = true;
                                break;
                            }
                        }
                    }
                    if (!found) {
                        root.error = Translation.tr("No free space for desktop shortcuts");
                        break;
                    }
                }
                items.push(Object.assign({}, entry, { x: px, y: py }));
            }
        }
        return root.save(screenName, items);
    }

    function move(screenName, itemId, x, y, targetId) {
        const items = root.itemsFor(screenName);
        const source = items.find(item => item.id === itemId);
        if (!source)
            return;
        const target = items.find(item => item.id === targetId && item.id !== itemId && root.isGroupable(item));
        if (target && root.isGroupable(source)) {
            const apps = target.type === "group" ? target.apps.slice() : [target];
            for (const app of source.type === "group" ? source.apps : [source]) {
                if (!apps.some(existing => existing.id === app.id))
                    apps.push(app);
            }
            root.save(screenName, items.filter(item => item.id !== itemId).map(item => item.id === target.id
                ? { id: target.type === "group" ? target.id : "group:" + Date.now(), type: "group",
                    name: target.type === "group" ? target.name : Translation.tr("App group"),
                    apps: apps, x: target.x, y: target.y } : item));
        } else {
            root.save(screenName, items.map(item => item.id === itemId
                ? Object.assign({}, item, { x: Math.round(x), y: Math.round(y) }) : item));
        }
    }

    function remove(screenName, itemId) {
        root.save(screenName, root.itemsFor(screenName).filter(item => item.id !== itemId));
    }
    // Bulk forms of the two gestures a multi-selection produces. One save
    // for the whole set: a group move must not write the store per icon, and
    // a map/filter pass over a handful of entries is cheaper than any merge
    // bookkeeping.
    function moveMany(screenName, moves) {
        const landed = new Map(moves.map(move => [move.id, move]));
        root.save(screenName, root.itemsFor(screenName).map(item => landed.has(item.id)
            ? Object.assign({}, item, { x: Math.round(landed.get(item.id).x), y: Math.round(landed.get(item.id).y) })
            : item));
    }

    function removeMany(screenName, ids) {
        const gone = new Set(ids);
        root.save(screenName, root.itemsFor(screenName).filter(item => !gone.has(item.id)));
    }
    // "Align to grid": sort the screen's icons in reading order (rows
    // top-to-bottom, within a row left-to-right) and hand each the next
    // free cell of the 100px lattice, anchored at the first icon's snapped
    // position so alignment never teleports the set to a corner. A taken
    // cell pushes its collision down, never sideways. One save through
    // moveMany — the same single-write rule every bulk gesture obeys.
    function alignToGrid(screenName) {
        const items = root.itemsFor(screenName).slice()
            .sort((a, b) => (a.y - b.y) || (a.x - b.x));
        if (items.length === 0)
            return;
        const originX = Math.round(items[0].x / 100) * 100;
        const originY = Math.round(items[0].y / 100) * 100;
        const taken = new Set();
        const moves = [];
        for (const item of items) {
            let col = Math.max(0, Math.round((item.x - originX) / 100));
            let row = Math.max(0, Math.round((item.y - originY) / 100));
            while (taken.has(col + ":" + row))
                ++row;
            taken.add(col + ":" + row);
            const gx = originX + col * 100;
            const gy = originY + row * 100;
            if (gx !== item.x || gy !== item.y)
                moves.push({ id: item.id, x: gx, y: gy });
        }
        if (moves.length > 0)
            root.moveMany(screenName, moves);
    }

    function rename(screenName, itemId, name) {
        if (!name.trim())
            return;
        root.save(screenName, root.itemsFor(screenName).map(item => item.id === itemId
            ? Object.assign({}, item, { name: name.trim() }) : item));
    }

    function removeMember(screenName, groupId, appId) {
        root.save(screenName, root.itemsFor(screenName).map(item => item.id === groupId
            ? Object.assign({}, item, { apps: item.apps.filter(app => app.id !== appId) }) : item));
    }

    // Dissolve a group: its members return to the desktop as individual
    // tiles, fanning out from the group's own cell. The rest of the store
    // is saved FIRST so add()'s free-space search does not count the group
    // itself as an occupant of the cells the members are about to take.
    function ungroup(screenName, groupId) {
        const items = root.itemsFor(screenName);
        const group = items.find(item => item.id === groupId && item.type === "group");
        if (!group)
            return;
        root.save(screenName, items.filter(item => item.id !== groupId));
        root.add(screenName, group.apps, group.x, group.y, "");
    }

    function application(appId) {
        const entry = TaskbarApps.getCachedDesktopEntry(appId);
        return entry ? { id: entry.id, type: "app", name: entry.name, icon: entry.icon, path: "" } : null;
    }

    function launch(entry) {
        // Folders and plain files go to the default handler; only .desktop
        // paths are launchable through gio directly.
        if ((entry.type === "directory" || entry.type === "file") && entry.path)
            Quickshell.execDetached(["xdg-open", entry.path]);
        else if (entry.path)
            Quickshell.execDetached(["gio", "launch", entry.path]);
        else
            TaskbarApps.getCachedDesktopEntry(entry.id)?.execute();
    }

    // Only apps and groups fold into a group: a folder or a file on the
    // desktop is its own thing, never merge fuel. The layer's targetAt and
    // the guards below share this one rule.
    function isGroupable(item) {
        return item.type !== "directory" && item.type !== "file";
    }
}
