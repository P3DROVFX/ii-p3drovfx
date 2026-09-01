pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common

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

    /// Icons on one workspace, as [{ id, x, y }].
    function iconsFor(workspaceId) {
        const all = root._all();
        const list = all[String(workspaceId)];
        return Array.isArray(list) ? list : [];
    }

    function has(workspaceId, appId) {
        return root.iconsFor(workspaceId).some(icon => icon.id === appId);
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

    function move(workspaceId, appId, x, y) {
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key] : [];
        const index = list.findIndex(icon => icon.id === appId);
        if (index === -1)
            return;
        list[index] = { id: appId, x: Math.round(x), y: Math.round(y) };
        all[key] = list;
        root._save(all);
    }

    function remove(workspaceId, appId) {
        const all = root._all();
        const key = String(workspaceId);
        const list = Array.isArray(all[key]) ? all[key] : [];
        const next = list.filter(icon => icon.id !== appId);
        if (next.length === list.length)
            return;
        all[key] = next;
        root._save(all);
    }

    /// Somewhere free-ish on the current home screen, for an icon added from the drawer
    /// rather than dropped at a point. Fills left to right, then wraps.
    ///
    /// Starts below the bar. The icons surface spans the whole screen — it has to, since
    /// the user may drag an icon anywhere — so an icon placed at the top corner would be
    /// born underneath the status bar with no way to see or grab it.
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
