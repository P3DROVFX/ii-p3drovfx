pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.services
import qs.modules.common

/**
 * New windows open floating, the way they do on Windows and on a Chromebook.
 *
 * Hyprland tiles by default, so on a touchscreen every application takes a whole workspace
 * and "two things at once" means learning about workspaces. A tablet user expects a window:
 * something with a size, sitting over what was already there, which they can push around
 * with a finger.
 *
 * Implemented against the `openwindow` event rather than as a window rule, deliberately:
 *
 *  - a rule lives in the user's Hyprland config, and this shell must not write into that
 *    for a preference the user can flip in Settings;
 *  - `hyprctl keyword` rules are runtime-only and are dropped by the next config reload,
 *    which this shell triggers whenever any Hyprland option changes;
 *  - a rule can float a window but cannot cascade it, because it has no memory of the last
 *    one placed.
 *
 * Nothing here runs unless `tablet.windows.floatMode` says so, and turning it off leaves the
 * compositor's own behaviour untouched — no rule to unwind, no state to restore.
 */
Scope {
    id: root

    readonly property var settings: Config.options?.tablet?.windows
    readonly property string floatMode: root.settings?.floatMode ?? "off"
    readonly property bool active: Config.ready && root.floatMode !== "off"

    /**
     * Windows waiting to be placed, by address.
     *
     * A client is not sized or mapped at `openwindow` time — Hyprland has an address for it
     * and little else — so floating it in that turn produces a window with whatever
     * geometry the toolkit asked for and then a second reflow when the real surface
     * arrives. One short delay lets it settle, and batching means ten windows opening at
     * once cost one pass rather than ten timers.
     */
    property var pending: []

    /// `hyprctl clients` is a process, so the window list catches up some time after the
    /// event does. A window not in it yet is not a window that will never arrive.
    readonly property int maximumAttempts: 6

    function queue(address) {
        const target = TabletWindowActions.normalizeAddress(address);
        if (target.length === 0)
            return;
        if (root.pending.some(entry => entry.address === target))
            return;
        root.pending = root.pending.concat([{ address: target, attempts: 0 }]);
        // Ask for fresh monitor data now, so it has arrived by the time placement needs it.
        //
        // `reserved` is what the bar and the dock took out of the screen, and placement has
        // to respect it or a floated window lands under one of them. HyprlandData refreshes
        // monitors on workspace and monitor events only — a layer surface changing its
        // exclusive zone emits neither — so without this the reserved values read here are
        // whatever they were at boot, which is before anything had reserved at all. That is
        // exactly how the first windows came out sized against the whole screen.
        HyprlandData.updateMonitors();
        settleTimer.restart();
    }

    function placeQueued() {
        const entries = root.pending;
        root.pending = [];
        const retry = [];
        for (const entry of entries) {
            if (root.place(entry.address))
                continue;
            if (entry.attempts + 1 < root.maximumAttempts)
                retry.push({ address: entry.address, attempts: entry.attempts + 1 });
        }
        if (retry.length > 0) {
            root.pending = retry;
            settleTimer.restart();
        }
    }

    /// Returns false only when the window is not in the client list yet, which is the one
    /// case worth trying again. A window deliberately left alone counts as handled.
    function place(address) {
        if (!root.active)
            return true;
        const client = TabletWindowActions.clientFor(address);
        if (!client)
            return false;

        // The scratchpad is a place you put a window, not a window that wants placing.
        if (Number(client?.workspace?.id ?? 0) <= 0)
            return true;
        if (TabletWindowActions.isExcluded(client?.class ?? ""))
            return true;
        // A window that came up fullscreen asked for the whole screen; floating it is
        // overruling the application about the one thing it was explicit about.
        if (client?.fullscreen)
            return true;
        // "keepDialogs" leaves anything the compositor already floated exactly as it is: an
        // application's own dialog usually knows both its size and where it wants to be, and
        // re-placing it is how a file chooser ends up centred over nothing.
        if (root.floatMode === "keepDialogs" && client?.floating)
            return true;

        const monitor = TabletWindowActions.monitorForClient(client);
        const placement = TabletWindowActions.placementFor(monitor);

        TabletWindowActions.setFloating(address, true);
        if (!placement)
            return true;
        // After the float, and after another beat: the window is being taken out of the
        // layout in the same turn, and a geometry set against its tiled size is immediately
        // overwritten by the float's own.
        geometryTimer.enqueue(address, placement);
        return true;
    }

    Timer {
        id: settleTimer
        interval: 90
        repeat: false
        onTriggered: root.placeQueued()
    }

    /// Geometry, applied a beat after the float has landed. Keyed by address so a burst of
    /// windows opening together does not lose all but the last.
    Timer {
        id: geometryTimer
        property var queued: []

        function enqueue(address, placement) {
            geometryTimer.queued = geometryTimer.queued.concat([{ address: address, placement: placement }]);
            geometryTimer.restart();
        }

        interval: 70
        repeat: false
        onTriggered: {
            const entries = geometryTimer.queued;
            geometryTimer.queued = [];
            for (const entry of entries) {
                TabletWindowActions.setGeometry(entry.address, entry.placement.x, entry.placement.y,
                                                entry.placement.width, entry.placement.height);
            }
        }
    }

    Connections {
        target: Hyprland
        enabled: root.active

        function onRawEvent(event) {
            if (event.name !== "openwindow")
                return;
            // openwindow is ADDRESS,WORKSPACENAME,CLASS,TITLE — and a title may contain
            // commas, so only the first field is ever safe to read positionally.
            const address = String(event.data ?? "").split(",")[0];
            root.queue(address);
        }
    }
}
