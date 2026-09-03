pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.tablet.navigation

/**
 * Which app icons sit on which home screen, and where.
 *
 * A workspace is a home screen in this family, so the store is keyed by workspace id. It
 * is read and written as JSON through Persistent rather than as typed lists: the shape is
 * a map that grows an entry per workspace the user drops something on, which is the case
 * the project's own notes call out as fragile for Config/Persistent's typed arrays.
 *
 * Every mutation goes through here so the JSON is parsed and re-serialised in one place;
 * callers deal in plain objects.
 */
Singleton {
    id: root

    /// Bumped on every write so views re-read without watching the string itself, which
    /// would also fire for unrelated whitespace changes on load.
    property int revision: 0

    readonly property int currentWorkspace: Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1

    /**
     * Where an icon added from the drawer should land.
     *
     * The current workspace when it is bare, because that is the page the user is looking
     * at. The home workspace otherwise: dropping an icon onto a workspace full of windows
     * puts it somewhere invisible, and an action whose result cannot be seen reads as an
     * action that failed. The drawer can be opened from anywhere in this family, so "the
     * page you are on" is not always a page.
     */
    readonly property int addTargetWorkspace: {
        const current = root.currentWorkspace;
        const occupied = HyprlandData.hyprlandClientsForWorkspace(current).length > 0;
        return occupied ? TabletNavigation.homeWorkspaceId("") : current;
    }

    property string pendingSecondAppId: ""
    Timer {
        id: pairSecondLaunchTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (root.pendingSecondAppId) {
                TaskbarApps.getCachedDesktopEntry(root.pendingSecondAppId)?.execute();
                root.pendingSecondAppId = "";
            }
        }
    }

    function launchPair(firstAppId, secondAppId) {
        if (!firstAppId)
            return;
        TaskbarApps.getCachedDesktopEntry(firstAppId)?.execute();
        if (secondAppId) {
            root.pendingSecondAppId = secondAppId;
            pairSecondLaunchTimer.restart();
        }
    }

    function _all() {
        try {
            return JSON.parse(Persistent.states.tablet.homeIconsJson || "{}") ?? {};
        } catch (e) {
            console.log("[TabletHomeIcons] stored icons were not valid JSON, starting empty:", e);
            return {};
        }
    }

    function _save(all) {
        Persistent.states.tablet.homeIconsJson = JSON.stringify(all);
        root.revision++;
    }

    /// Icons on one workspace, as [{ id, x, y, type?, apps?, name? }].
    function iconsFor(workspaceId) {
        const all = root._all();
        const list = all[String(workspaceId)];
        return Array.isArray(list) ? list : [];
    }

    function has(workspaceId, appId) {
        const list = root.iconsFor(workspaceId);
        return list.some(icon => {
            if (icon.id === appId)
                return true;
            if (Array.isArray(icon.apps) && icon.apps.indexOf(appId) !== -1)
                return true;
            return false;
        });
    }

    function add(workspaceId, appId, x, y) {
        if (!appId || root.has(workspaceId, appId))
            return;
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key].slice() : [];
        list.push({ id: appId, x: Math.round(x), y: Math.round(y) });
        all[key] = list;
        root._save(all);
    }

    function addPair(workspaceId, firstAppId, secondAppId, name, x, y) {
        if (!firstAppId || !secondAppId)
            return;
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key].slice() : [];
        const id = `pair:${firstAppId}+${secondAppId}_${Date.now()}`;
        list.push({
            id: id,
            type: "pair",
            apps: [firstAppId, secondAppId],
            name: name || "",
            x: Math.round(x),
            y: Math.round(y)
        });
        all[key] = list;
        root._save(all);
    }

    function addFolder(workspaceId, name, appsList, x, y) {
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key].slice() : [];
        const id = `folder:${Date.now()}`;
        list.push({
            id: id,
            type: "folder",
            name: name || Translation.tr("Folder"),
            apps: Array.isArray(appsList) ? appsList.slice() : [],
            x: Math.round(x),
            y: Math.round(y)
        });
        all[key] = list;
        root._save(all);
    }

    function combineIntoFolder(workspaceId, targetItemId, draggedItemId, x, y) {
        if (!targetItemId || !draggedItemId || targetItemId === draggedItemId)
            return;
        const all = root._all();
        const key = String(workspaceId);
        let list = Array.isArray(all[key]) ? all[key].slice() : [];

        const targetIndex = list.findIndex(icon => icon.id === targetItemId);
        const draggedIndex = list.findIndex(icon => icon.id === draggedItemId);
        if (targetIndex === -1 || draggedIndex === -1)
            return;

        const target = Object.assign({}, list[targetIndex]);
        const dragged = list[draggedIndex];

        // Gather app IDs from dragged item
        const appsToAdd = (dragged.type === "folder" || dragged.type === "pair") && Array.isArray(dragged.apps)
            ? dragged.apps : [dragged.id];

        if (target.type === "folder") {
            const currentApps = Array.isArray(target.apps) ? target.apps.slice() : [];
            for (const appId of appsToAdd) {
                if (currentApps.indexOf(appId) === -1)
                    currentApps.push(appId);
            }
            target.apps = currentApps;
            list[targetIndex] = target;
            list.splice(draggedIndex, 1);
        } else {
            // Target is a single app or pair -> create a new folder
            const initialApps = (target.type === "pair" && Array.isArray(target.apps))
                ? target.apps.slice() : [target.id];
            for (const appId of appsToAdd) {
                if (initialApps.indexOf(appId) === -1)
                    initialApps.push(appId);
            }
            const folder = {
                id: `folder:${Date.now()}`,
                type: "folder",
                name: Translation.tr("Folder"),
                apps: initialApps,
                x: target.x !== undefined ? target.x : Math.round(x),
                y: target.y !== undefined ? target.y : Math.round(y)
            };
            // Remove both and insert folder
            list = list.filter(icon => icon.id !== targetItemId && icon.id !== draggedItemId);
            list.push(folder);
        }

        all[key] = list;
        root._save(all);
    }

    function addAppToFolder(workspaceId, folderId, appId) {
        if (!folderId || !appId)
            return;
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key].slice() : [];
        const index = list.findIndex(icon => icon.id === folderId && icon.type === "folder");
        if (index === -1)
            return;
        const folder = Object.assign({}, list[index]);
        const apps = Array.isArray(folder.apps) ? folder.apps.slice() : [];
        if (apps.indexOf(appId) === -1) {
            apps.push(appId);
            folder.apps = apps;
            list[index] = folder;
            all[key] = list;
            root._save(all);
        }
    }

    function removeAppFromFolder(workspaceId, folderId, appId) {
        if (!folderId || !appId)
            return;
        const all = root._all();
        const key = String(workspaceId);
        let list = Array.isArray(all[key]) ? all[key].slice() : [];
        const index = list.findIndex(icon => icon.id === folderId && icon.type === "folder");
        if (index === -1)
            return;
        const folder = Object.assign({}, list[index]);
        const apps = (folder.apps || []).filter(id => id !== appId);

        if (apps.length === 0) {
            // Remove empty folder
            list.splice(index, 1);
        } else if (apps.length === 1) {
            // Dissolve folder into single app
            list[index] = { id: apps[0], x: folder.x, y: folder.y };
        } else {
            folder.apps = apps;
            list[index] = folder;
        }

        all[key] = list;
        root._save(all);
    }

    function renameFolder(workspaceId, folderId, newName) {
        if (!folderId)
            return;
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key].slice() : [];
        const index = list.findIndex(icon => icon.id === folderId);
        if (index === -1)
            return;
        const folder = Object.assign({}, list[index]);
        folder.name = newName || "";
        list[index] = folder;
        all[key] = list;
        root._save(all);
    }

    function move(workspaceId, itemId, x, y) {
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key] : [];
        const index = list.findIndex(icon => icon.id === itemId);
        if (index === -1)
            return;
        const current = Object.assign({}, list[index]);
        current.x = Math.round(x);
        current.y = Math.round(y);
        list[index] = current;
        all[key] = list;
        root._save(all);
    }

    function remove(workspaceId, itemId) {
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key] : [];
        const next = list.filter(icon => icon.id !== itemId);
        if (next.length === list.length)
            return;
        all[key] = next;
        root._save(all);
    }

    /**
     * Send an icon to another home page.
     */
    function moveToWorkspace(fromWorkspaceId, toWorkspaceId, itemId) {
        if (fromWorkspaceId === toWorkspaceId || !itemId)
            return false;
        const item = root.iconsFor(fromWorkspaceId).find(entry => entry.id === itemId);
        if (!item || root.has(toWorkspaceId, itemId))
            return false;

        const all = root._all();
        const fromKey = String(fromWorkspaceId);
        const toKey = String(toWorkspaceId);
        all[fromKey] = (Array.isArray(all[fromKey]) ? all[fromKey] : [])
            .filter(entry => entry.id !== itemId);
        all[toKey] = (Array.isArray(all[toKey]) ? all[toKey].slice() : [])
            .concat([Object.assign({}, item)]);
        root._save(all);
        return true;
    }

    /// Somewhere free-ish on the current home screen.
    function nextFreeSlot(workspaceId, columnsPerRow) {
        const step = Math.max(1, Appearance.sizes.widgetGridStep);
        const cell = step * 3;
        const taken = root.iconsFor(workspaceId).length;
        const perRow = Math.max(1, columnsPerRow);
        return {
            x: step + (taken % perRow) * cell,
            y: Math.round(Appearance.sizes.barHeight) + step + Math.floor(taken / perRow) * cell
        };
    }
}
