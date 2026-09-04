pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import "../../common/draw/StrokeGeometry.js" as StrokeGeometry

/**
 * The ink, and which home screen each sheet of it belongs to.
 *
 * A drawing here is not a document — it is a note stuck to a workspace. You draw on top
 * of whatever is there, and it stays over that workspace until you rub it out or save
 * it, the way a sticky note stays on the monitor it was stuck to. So the store is keyed
 * by workspace, and the surface that draws it shows the sheet for the workspace in
 * front and nothing else.
 *
 * Deliberately in memory only. A workspace annotation that outlived a reboot would be a
 * surprise — you would come back to a machine with drawings on it and no memory of
 * making them — and the ink that is meant to last has a button that puts it in Notes.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.tablet?.liveDraw ?? null

    /// A stroke: { points: [{x, y, p}], color, width, usePressure }.
    /// Sheets: { "<monitor>:<workspace>": [stroke, …] }.
    property var sheets: ({})
    /// Bumped on every change, because a nested mutation of `sheets` is invisible to a
    /// binding. Everything that draws watches this rather than the object.
    property int revision: 0

    /**
     * Whether the pen is down.
     *
     * Off with the tray still up is the "keep it on this workspace" state: the ink shows,
     * taps go through to the applications, and one tap on the pencil picks the pen back
     * up. That round trip is the whole point — the first version had no way back, so a
     * sheet you had stopped drawing on could never be drawn on again, and the toolbar sat
     * there looking like it should still work.
     */
    property bool drawing: false

    /**
     * Whether the toolbar is on screen.
     *
     * Separate from `drawing`, because "put the pen down" and "put everything away" are
     * different requests and were previously the same button. Closing the tray leaves the
     * ink exactly where it is: losing work must never be a side effect of tidying up.
     */
    property bool trayOpen: false

    /// Enter live draw: tray up, pen down.
    function open() {
        root.ensureTools();
        root.trayOpen = true;
        root.drawing = true;
    }

    /// Leave live draw entirely. The ink stays on its workspace until it is rubbed out.
    function close() {
        root.drawing = false;
        root.trayOpen = false;
    }

    function toggleDrawing() {
        if (!root.trayOpen) {
            root.open();
            return;
        }
        root.drawing = !root.drawing;
    }

    // ── Tools ───────────────────────────────────────────────────────────────
    // Live, not persisted: which colour you were last using is a property of the drawing
    // you were doing. The defaults come from Config, which is where the durable
    // preferences live.
    property string color: ""
    property real width: 0
    property bool eraser: false

    readonly property var palette: {
        const configured = root.opts?.palette ?? [];
        const list = [];
        for (const entry of configured) {
            const value = String(entry ?? "").trim();
            if (value.length > 0)
                list.push(value);
        }
        return list.length > 0 ? list : ["#ffffff"];
    }

    readonly property bool usePressure: root.opts?.pressure ?? true
    readonly property real smoothing: Math.max(0, Math.min(0.95, (root.opts?.smoothing ?? 55) / 100))

    function ensureTools() {
        if (root.color.length === 0)
            root.color = root.palette[0];
        if (root.width <= 0)
            root.width = Math.max(1, root.opts?.width ?? 4);
    }

    // ── Which sheet ─────────────────────────────────────────────────────────
    /**
     * The key for the workspace in front of a given monitor.
     *
     * Monitor as well as workspace, because Hyprland numbers workspaces across the whole
     * layout: two monitors never show the same one, but a sheet drawn on an external
     * display should not reappear on the laptop's because the numbers happened to line up
     * after a hotplug.
     */
    function keyFor(screenName) {
        const name = String(screenName ?? "");
        for (const monitor of (Hyprland.monitors?.values ?? [])) {
            if (String(monitor?.name ?? "") === name)
                return `${name}:${monitor?.activeWorkspace?.id ?? -1}`;
        }
        return `${name}:${Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1}`;
    }

    function strokesFor(key) {
        return root.sheets[key] ?? [];
    }

    function hasInk(key) {
        return root.strokesFor(key).length > 0;
    }

    /// Every sheet with something on it, so the surface knows whether to exist at all.
    readonly property int sheetCount: {
        void root.revision;
        let count = 0;
        for (const key in root.sheets) {
            if ((root.sheets[key] ?? []).length > 0)
                count++;
        }
        return count;
    }

    // ── Editing ─────────────────────────────────────────────────────────────
    function addStroke(key, stroke) {
        if (!stroke || !stroke.points || stroke.points.length === 0)
            return;
        const next = Object.assign({}, root.sheets);
        next[key] = (next[key] ?? []).concat([stroke]);
        root.sheets = next;
        root.revision++;
    }

    function undo(key) {
        const existing = root.sheets[key] ?? [];
        if (existing.length === 0)
            return;
        const next = Object.assign({}, root.sheets);
        next[key] = existing.slice(0, existing.length - 1);
        root.sheets = next;
        root.revision++;
    }

    /// Removes the strokes a rubbing gesture touched. Returns how many went.
    function eraseAt(key, x, y, radius) {
        const existing = root.sheets[key] ?? [];
        if (existing.length === 0)
            return 0;
        const kept = existing.filter(stroke => !StrokeGeometry.strokeHitBy(stroke, x, y, radius));
        if (kept.length === existing.length)
            return 0;
        const next = Object.assign({}, root.sheets);
        next[key] = kept;
        root.sheets = next;
        root.revision++;
        return existing.length - kept.length;
    }

    function clear(key) {
        if ((root.sheets[key] ?? []).length === 0)
            return;
        const next = Object.assign({}, root.sheets);
        delete next[key];
        root.sheets = next;
        root.revision++;
    }

    function clearAll() {
        root.sheets = ({});
        root.revision++;
    }
}
