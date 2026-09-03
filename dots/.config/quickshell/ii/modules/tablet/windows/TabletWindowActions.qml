pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.services
import qs.modules.common

/**
 * Window arithmetic for a family that has no pointer to drag windows with.
 *
 * Hyprland can move and resize a floating window perfectly well, but every affordance it
 * ships for doing so is a *pointer* binding: `movewindow` and `resizewindow` follow a mouse
 * that a tablet does not have, and the keyboard equivalents need a keyboard. So the shell
 * has to compute the geometry itself and dispatch it, and this is the one place that knows
 * how.
 *
 * The two dispatchers behave differently and the difference matters everywhere below:
 *
 *   `hl.dsp.window.move({ x, y })`     — absolute position, in layout coordinates.
 *   `hl.dsp.window.resize({ x, y })`   — absolute *size*, and it resizes about the window's
 *                                        centre, so the top-left moves unless a move is
 *                                        dispatched after it. Negative values are refused
 *                                        outright ("Invalid size"), hence the floor.
 *
 * Both take `window = "address:0x…"`; dispatching without one acts on whatever is focused,
 * which is never reliably the window a finger is on.
 */
Singleton {
    id: root

    /// Nothing smaller is a window any more; it is a handle with a title in it.
    readonly property int minimumWidth: 240
    readonly property int minimumHeight: 160

    readonly property var settings: Config.options?.tablet?.windows

    function normalizeAddress(address) {
        const raw = String(address ?? "").trim();
        if (raw.length === 0)
            return "";
        return raw.startsWith("0x") ? raw : `0x${raw}`;
    }

    function clientFor(address) {
        const wanted = root.normalizeAddress(address);
        if (wanted.length === 0)
            return null;
        for (const client of (HyprlandData.windowList ?? [])) {
            if (root.normalizeAddress(client?.address) === wanted)
                return client;
        }
        return null;
    }

    /**
     * The window in front, or null.
     *
     * `focusHistoryID === 0` is the focused window anywhere; restricting it to the active
     * workspace is what keeps a control strip from appearing over an empty home screen
     * because something is focused two workspaces away.
     */
    function focusedClient() {
        const activeWorkspace = Number(HyprlandData.activeWorkspace?.id ?? -1);
        for (const client of (HyprlandData.windowList ?? [])) {
            if (Number(client?.focusHistoryID ?? -1) !== 0)
                continue;
            if (activeWorkspace !== -1 && Number(client?.workspace?.id ?? -2) !== activeWorkspace)
                return null;
            return client;
        }
        return null;
    }

    function monitorForClient(client) {
        if (!client)
            return null;
        const monitorId = Number(client?.monitor ?? -1);
        for (const monitor of (HyprlandData.monitors ?? [])) {
            if (Number(monitor?.id ?? -2) === monitorId)
                return monitor;
        }
        return null;
    }

    /**
     * A monitor's usable rectangle in layout coordinates.
     *
     * `width`/`height` come back in physical pixels while `x`/`y` are layout coordinates, so
     * the size has to be divided by the scale and the origin must not be. `reserved` is
     * already what the layer-shell surfaces took — the bar at the top and the dock at the
     * bottom — so a window placed inside this never lands under either of them.
     */
    function usableArea(monitor) {
        if (!monitor)
            return null;
        const scale = Number(monitor?.scale ?? 1) || 1;
        const reserved = monitor?.reserved ?? [0, 0, 0, 0];
        const left = Number(reserved[0] ?? 0);
        const top = Number(reserved[1] ?? 0);
        const right = Number(reserved[2] ?? 0);
        const bottom = Number(reserved[3] ?? 0);
        return {
            x: Number(monitor?.x ?? 0) + left,
            y: Number(monitor?.y ?? 0) + top,
            width: Math.round(Number(monitor?.width ?? 0) / scale) - left - right,
            height: Math.round(Number(monitor?.height ?? 0) / scale) - top - bottom
        };
    }

    // ── Dispatch ────────────────────────────────────────────────────────────

    function moveTo(address, x, y) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.move({ x = ${Math.round(x)}, y = ${Math.round(y)}, window = "address:${target}" })`);
    }

    function resizeTo(address, width, height) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        const w = Math.max(root.minimumWidth, Math.round(width));
        const h = Math.max(root.minimumHeight, Math.round(height));
        Hyprland.dispatch(`hl.dsp.window.resize({ x = ${w}, y = ${h}, window = "address:${target}" })`);
    }

    /// Resize keeps the centre, so the top-left has to be restored afterwards or a window
    /// being made bigger by its bottom-right handle also walks up and to the left.
    function setGeometry(address, x, y, width, height) {
        root.resizeTo(address, width, height);
        root.moveTo(address, x, y);
    }

    function setFloating(address, floating) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.float({ action = '${floating ? "on" : "off"}', window = "address:${target}" })`);
    }

    function toggleFloating(address) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.float({ action = 'toggle', window = "address:${target}" })`);
    }

    function toggleFullscreen(address) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = 'fullscreen', action = 'toggle', window = "address:${target}" })`);
    }

    function togglePinned(address) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.pin({ action = 'toggle', window = "address:${target}" })`);
    }

    function centerWindow(address) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.center({ window = "address:${target}" })`);
    }

    function closeWindow(address) {
        const target = root.normalizeAddress(address);
        if (target.length === 0)
            return;
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${target}" })`);
    }

    // ── Placement of a freshly floated window ───────────────────────────────

    /// How far each successive window steps down and right of the last one.
    readonly property int cascadeStep: 36
    property int cascadeIndex: 0

    function nextCascadeOffset() {
        if (!(root.settings?.cascade ?? true))
            return 0;
        // Four steps and back to the top-left: any more and the last window in the run is
        // most of a screen away from the first, which is not a cascade, it is a diagonal.
        root.cascadeIndex = (root.cascadeIndex + 1) % 5;
        return root.cascadeIndex * root.cascadeStep;
    }

    /**
     * Where a window should land when this family floats it for you.
     *
     * Centred in the monitor's usable area at a share of it the user picks, then nudged by
     * the cascade so a second window does not sit exactly on the first — which on a
     * touchscreen is the difference between two windows and one window that will not come
     * to the front.
     */
    function placementFor(monitor) {
        const area = root.usableArea(monitor);
        if (!area || area.width <= 0 || area.height <= 0)
            return null;

        const widthShare = Math.max(20, Math.min(100, Number(root.settings?.floatWidthPercent ?? 62))) / 100;
        const heightShare = Math.max(20, Math.min(100, Number(root.settings?.floatHeightPercent ?? 68))) / 100;

        const width = Math.max(root.minimumWidth, Math.round(area.width * widthShare));
        const height = Math.max(root.minimumHeight, Math.round(area.height * heightShare));

        const offset = root.nextCascadeOffset();
        // Clamped rather than allowed to run off: a cascade that pushes the title strip past
        // the bottom edge takes the only touch handle with it.
        const x = Math.min(area.x + area.width - width,
                           Math.round(area.x + (area.width - width) / 2) + offset);
        const y = Math.min(area.y + area.height - height,
                           Math.round(area.y + (area.height - height) / 2) + offset);

        return { x: Math.max(area.x, x), y: Math.max(area.y, y), width: width, height: height };
    }

    /// Case-insensitive, because a `.desktop` id and a Hyprland class disagree on case more
    /// often than they agree, and an exclusion list nobody can spell is not a list.
    function isExcluded(windowClass) {
        const name = String(windowClass ?? "").trim().toLowerCase();
        if (name.length === 0)
            return true;
        for (const entry of (root.settings?.exclusions ?? [])) {
            const excluded = String(entry ?? "").trim().toLowerCase();
            if (excluded.length > 0 && name.indexOf(excluded) !== -1)
                return true;
        }
        return false;
    }
}
